# frozen_string_literal: true

require "time"

module Navesti
  module Providers
    module Wise
      # Maps Wise (UK OBIE) JSON responses into Navesti value objects, preserving
      # the raw payload as evidence on every object (docs/01, docs/07).
      #
      # The OBIE wire shape differs from LHV's Berlin Group: everything is nested
      # under a `Data` envelope, accounts carry an inner `Account[]` of scheme-
      # tagged identifiers, and balances are unsigned amounts plus a
      # CreditDebitIndicator. The *mechanics* (evidence wrapping, group-by-
      # currency, available/booked classification) are the same as LHV — that
      # sameness is the evidence for a future shared mapper
      # (docs/14-semantic-compression-and-the-connector-layer.md). Only the
      # source paths differ; they live here, in the dialect's mapper.
      module Mappers
        extend Navesti::Mappers::Evidence # provides #evidence (shared substrate)
        module_function

        # GET /aisp/accounts → [Navesti::Account]
        #
        # The OBIE basic account has no single "iban" — identification lives in
        # a scheme-tagged inner Account[] (UK.OBIE.IBAN vs SortCodeAccountNumber),
        # and some Wise currency accounts carry no inner details at all. Use the
        # stable AccountId as provider_account_id; surface iban only when an
        # IBAN-scheme entry is present. Raw preserves exactly what Wise sent.
        def accounts(response)
          list = response.json.dig("Data", "Account") || []
          captured_at = Time.now.utc.iso8601

          list.map do |acc|
            Account.new(
              provider: Config::PROVIDER,
              provider_account_id: acc["AccountId"],
              provider_reported_currency: acc["Currency"],
              iban: iban_for(acc),
              owner_name: identifier_name(acc),
              name: acc["Nickname"],
              product: acc["AccountSubType"],
              cash_account_type: acc["AccountType"],
              status: acc["Status"],
              raw: { account: acc, captured_at: captured_at }
            )
          end
        end

        # GET /aisp/accounts/{id}/balances → [Navesti::Balance], one per currency.
        #
        # OBIE returns unsigned amounts with a CreditDebitIndicator; a Debit
        # balance is negative (the dialect classifies both the sign and the
        # available/booked split). All raw entries are preserved.
        def balances(response, provider_account_id:)
          entries = response.json.dig("Data", "Balance") || []
          captured_at = Time.now.utc.iso8601

          entries.group_by { |e| e.dig("Amount", "Currency") }.map do |currency, group|
            if currency.nil?
              raise MappingError.new("balance entry missing Amount.Currency", field: :currency)
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
              raw: { entries: group, response: evidence(response) }
            )
          end
        end

        # POST /aisp/account-access-consents → Navesti::Consent.
        #
        # No interaction is returned here: unlike LHV's _links.scaRedirect, the
        # OBIE authorize URL is built and signed by the adapter (Hybrid Flow),
        # not handed back in the consent body. The host stores ConsentId and
        # embeds it as openbanking_intent_id when building the authorize URL.
        def consent(response)
          data = response.json["Data"] || {}
          Consent.new(
            provider: Config::PROVIDER,
            consent_id: data["ConsentId"],
            status: Dialect.consent_status(data["Status"]),
            raw_status: data["Status"],
            # AIS consents carry ExpirationDateTime; PIS payment consents carry
            # a CutOffDateTime (30 min) instead — surface whichever is present.
            valid_until: data["ExpirationDateTime"] || data["CutOffDateTime"],
            raw: evidence(response)
          )
        end

        # GET /aisp/account-access-consents/{id} → Navesti::Consent (status-only
        # use). Same body shape as creation; ConsentId echoes in the body.
        def consent_status(response)
          consent(response)
        end

        # POST /auth/token → Navesti::Token
        def token(response)
          body = response.json
          Token.new(
            access_token: body["access_token"],
            token_type: body["token_type"] || "bearer",
            refresh_token: body["refresh_token"],
            expires_in: body["expires_in"],
            scope: body["scope"],
            obtained_at: Time.now.utc.iso8601,
            # Token body is the secret — store redacted evidence; the typed
            # access_token field still carries the real value for the host.
            raw: evidence(response, redact: true)
          )
        end

        # POST /pisp/domestic-payments → Navesti::PaymentSubmission.
        #
        # No interaction here: OBIE runs SCA during the payment-CONSENT
        # authorization (Hybrid Flow), so by the time the payment-order is
        # POSTed the instruction is already committed — the submission carries a
        # status, not a redirect.
        def payment_submission(response, idempotency_key: nil)
          data = response.json["Data"] || {}
          ref = payment_reference(data["DomesticPaymentId"])
          status = Dialect.payment_status(data["Status"], provider_reference: ref, raw: evidence(response))

          PaymentSubmission.new(
            status: status,
            provider_reference: ref,
            idempotency_key: idempotency_key,
            submitted_at: Time.now.utc.iso8601,
            raw: evidence(response)
          )
        end

        # GET /pisp/domestic-payments/{id} → Navesti::PaymentStatus.
        def payment_status(response, payment_id: nil)
          data = response.json["Data"] || {}
          Dialect.payment_status(
            data["Status"],
            provider_reference: payment_id && payment_reference(payment_id),
            raw: evidence(response)
          )
        end

        # --- helpers ---

        def payment_reference(payment_id)
          return nil if payment_id.to_s.empty?

          ProviderReference.new(value: payment_id, kind: :payment, connector: Config::PROVIDER)
        end

        # First inner Account[] identifier tagged with an IBAN scheme, or nil.
        def iban_for(acc)
          entry = Array(acc["Account"]).find { |a| a["SchemeName"].to_s.include?("IBAN") }
          entry && entry["Identification"]
        end

        # The display Name on the first inner identifier (e.g. "Jane Doe (GBP)"),
        # or nil when the account carries no inner details.
        def identifier_name(acc)
          entry = Array(acc["Account"]).find { |a| a["Name"] }
          entry && entry["Name"]
        end

        # Picks the first balance of a matching type and converts it to Money,
        # applying the CreditDebitIndicator sign. Returns nil when absent.
        def pick_balance(group, currency)
          entry = group.find { |e| yield(e["Type"]) }
          return nil if entry.nil?

          amount = entry.dig("Amount", "Amount")
          return nil if amount.nil?

          signed = Dialect.debit?(entry["CreditDebitIndicator"]) ? "-#{amount}" : amount.to_s
          Money.from_decimal(signed, currency)
        end
      end
    end
  end
end
