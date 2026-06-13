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
        def evidence(response)
          {
            status: response.status,
            headers: response.headers,
            body: response.body,
            captured_at: Time.now.utc.iso8601
          }
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
            raw: evidence(response)
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
            idempotency_key: idempotency_key,
            submitted_at: Time.now.utc.iso8601,
            raw: evidence(response)
          )
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

        def payment_reference(payment_id)
          return nil if payment_id.to_s.empty?

          ProviderReference.new(value: payment_id, kind: :payment, connector: Config::PROVIDER)
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
