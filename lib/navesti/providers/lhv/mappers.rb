# frozen_string_literal: true

require "time"

module Navesti
  module Providers
    module LHV
      # Maps LHV JSON responses into Navesti value objects, preserving the raw
      # payload as evidence on every object (docs/01, docs/07). Mapping adds a
      # canonical reading alongside the original; it never mutates raw.
      module Mappers
        module_function

        # Builds the raw-evidence hash carried by provider-derived objects.
        #
        # redact: true scrubs secrets from the body and headers before storing —
        # used for OAuth token responses, whose body *is* the secret. Other
        # responses keep verbatim evidence (their bodies are not secrets), so
        # auditability is preserved where it is safe.
        def evidence(response, redact: false)
          body = response.body
          headers = response.headers
          if redact
            body = Navesti::Redaction.scrub(body.to_s)
            headers = headers.transform_values { |v| Navesti::Redaction.scrub(v.to_s) }
          end
          { status: response.status, headers: headers, body: body, captured_at: Time.now.utc.iso8601 }
        end

        # GET /v1/tpp-verification → Navesti::TppVerification
        #
        # The certificate-invalid case has no "access" field — only
        # tppMessages[].code == CERTIFICATE_INVALID — so derive it from there
        # (docs/13 Q-accepted, providers/lhv/swagger-notes.md).
        def tpp_verification(response)
          body = response.json
          access = if certificate_invalid?(body)
                     :invalid_certificate
                   else
                     Dialect.access(body["access"])
                   end

          TppVerification.new(
            provider: Config::PROVIDER,
            access: access,
            tpp_id: body["tppId"],
            name: body["name"],
            roles: body["roles"] || [],
            raw: evidence(response)
          )
        end

        # GET /v1/accounts-list → [Navesti::Account]
        def accounts(response)
          body = response.json
          reject_on_error!(body)
          list = body.is_a?(Hash) ? (body["accounts"] || []) : body

          list.map do |acc|
            Account.new(
              provider: Config::PROVIDER,
              provider_account_id: acc["resourceId"],
              # provider-reported, may be "XXX"/nil — never ISO-validated.
              provider_reported_currency: acc["currency"],
              iban: acc["iban"],
              owner_name: acc["ownerName"],
              name: acc["name"],
              product: acc["product"],
              cash_account_type: acc["cashAccountType"],
              status: normalize_account_status(acc["status"]),
              raw: { account: acc, captured_at: Time.now.utc.iso8601 }
            )
          end
        end

        # GET /v1/accounts/{id}/balances → [Navesti::Balance], one per currency.
        #
        # Berlin Group returns an array of typed balance entries; we group by
        # currency and project the available/booked facts (Dialect classifies
        # the balanceType). Every raw entry is preserved. A missing available or
        # booked balance is nil — never invented (docs/08, GPT LHV-2A).
        def balances(response, provider_account_id:)
          body = response.json
          reject_on_error!(body)
          entries = body.is_a?(Hash) ? (body["balances"] || []) : []
          captured_at = Time.now.utc.iso8601

          entries.group_by { |e| e.dig("balanceAmount", "currency") }.map do |currency, group|
            if currency.nil?
              raise MappingError.new("balance entry missing balanceAmount.currency", field: :currency)
            end

            available = pick_balance(group, currency) { |t| Dialect.available_balance_type?(t) }
            booked    = pick_balance(group, currency) { |t| Dialect.booked_balance_type?(t) }

            Balance.new(
              provider: Config::PROVIDER,
              provider_account_id: provider_account_id,
              currency: currency,
              available: available,
              booked: booked,
              captured_at: captured_at,
              # Preserve all raw entries for this currency, plus full evidence.
              raw: { entries: group, response: evidence(response) }
            )
          end
        end

        # POST /oauth/token → Navesti::Token
        def token(response)
          body = response.json
          Token.new(
            access_token: body["access_token"],
            token_type: body["token_type"] || "bearer",
            refresh_token: body["refresh_token"],
            expires_in: body["expires_in"],
            scope: body["scope"],
            obtained_at: Time.now.utc.iso8601,
            # Token response body contains access/refresh tokens — store redacted
            # evidence so Token#raw / #to_h never leak the secret (the typed
            # access_token field still carries the real value for the host).
            raw: evidence(response, redact: true)
          )
        end

        # POST /v1.1/payments/sepa-credit-transfers → Navesti::PaymentSubmission
        def payment_submission(response, idempotency_key: nil)
          body = response.json
          reject_on_error!(body)

          payment_id = body["paymentId"]
          links = body["_links"] || {}
          provider_reference = payment_reference(payment_id)

          status = Dialect.payment_status(
            body["transactionStatus"],
            provider_reference: provider_reference,
            raw: evidence(response)
          )

          PaymentSubmission.new(
            status: status,
            provider_reference: provider_reference,
            interaction: sca_interaction(links, provider_reference, response),
            status_url: link_href(links, "status"),
            authorisation_url: link_href(links, "startAuthorisationWithAuthenticationMethodSelection"),
            sca_methods: sca_methods(body),
            idempotency_key: idempotency_key,
            submitted_at: Time.now.utc.iso8601,
            raw: evidence(response)
          )
        end

        # DELETE /v1.1/payments/sepa-credit-transfers/{id}/cancel → PaymentStatus
        #
        # Cancellation is only valid before the PSU completes SCA; on success the
        # bank-side initiation is cancelled and no money moved. A body with a
        # transactionStatus (typically CANC) is normalized through the dialect;
        # an empty/204 success is synthesized as a cancelled, no-side-effect
        # status. Failure (e.g. SCA already done) surfaces via guard as an error.
        def cancellation(response, payment_id:)
          ref = payment_reference(payment_id)
          body = response.body.to_s.strip.empty? ? nil : response.json_or_nil
          raw_status = body.is_a?(Hash) ? body["transactionStatus"] : nil

          if raw_status
            Dialect.payment_status(raw_status, provider_reference: ref, raw: evidence(response))
          else
            PaymentStatus.new(
              status: :cancelled, safety_status: :rejected, side_effect_possible: false,
              raw_status: nil, provider_reference: ref, raw: evidence(response)
            )
          end
        end

        # GET /v1.1/payments/sepa-credit-transfers/{id}/status → PaymentStatus
        def payment_status(response, payment_id: nil)
          body = response.json
          reject_on_error!(body)
          Dialect.payment_status(
            body["transactionStatus"],
            provider_reference: payment_id && payment_reference(payment_id),
            raw: evidence(response)
          )
        end

        # --- helpers ---

        # Picks the first balance entry of a matching type and converts its
        # amount to Money. Returns nil when no entry of that class is present.
        def pick_balance(group, currency)
          entry = group.find { |e| yield(e["balanceType"]) }
          return nil if entry.nil?

          amount = entry.dig("balanceAmount", "amount")
          return nil if amount.nil?

          Money.from_decimal(amount, currency)
        end

        def payment_reference(payment_id)
          return nil if payment_id.to_s.empty?

          ProviderReference.new(value: payment_id, kind: :payment, connector: Config::PROVIDER)
        end

        # Decoupled SCA discovery: the methods the bank offers for this payment.
        def sca_methods(body)
          return [] unless body.is_a?(Hash)

          (body["scaMethods"] || []).map do |m|
            ScaMethod.new(
              method_id: m["authenticationMethodId"],
              authentication_type: m["authenticationType"],
              name: m["name"]
            )
          end
        end

        # Redirect SCA is offered when _links.scaRedirect is present. Its
        # absence on an ACSC response means an SCA exemption applied (the
        # payment is already confirmed) → no interaction.
        def sca_interaction(links, provider_reference, response)
          href = link_href(links, "scaRedirect")
          return nil if href.nil?

          Interaction.new(
            type: :redirect,
            url: href,
            provider_reference: provider_reference,
            raw: { links: links, captured_at: Time.now.utc.iso8601 }
          )
        end

        def link_href(links, name)
          link = links[name]
          link && link["href"]
        end

        def certificate_invalid?(body)
          tpp_messages(body).any? { |m| m["code"] == "CERTIFICATE_INVALID" }
        end

        # Raises ProviderError on an LHV error message (category ERROR).
        # ROLE_INVALID (PSU-Corporate-ID mismatch) surfaces as a ProviderError.
        def reject_on_error!(body)
          return unless body.is_a?(Hash)

          error = tpp_messages(body).find { |m| m["category"] == "ERROR" }
          return unless error

          raise ProviderError.new(
            "LHV returned error #{error['code']}",
            provider_code: error["code"]
          )
        end

        def tpp_messages(body)
          return [] unless body.is_a?(Hash)

          body["tppMessages"] || []
        end

        def normalize_account_status(status)
          case status.to_s
          when "enabled" then :enabled
          when "blocked" then :blocked
          else status
          end
        end
      end
    end
  end
end
