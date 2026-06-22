# frozen_string_literal: true

require "time"

module Navesti
  module Providers
    module Revolut
      # Maps Revolut (UK OBIE) JSON into Navesti value objects. Same OBIE `Data`
      # envelope as Wise — the shared shape is the docs/14 extraction signal.
      module Mappers
        module_function

        def evidence(response, redact: false)
          body = response.body
          headers = response.headers
          if redact
            body = Navesti::Redaction.scrub(body.to_s)
            headers = headers.transform_values { |v| Navesti::Redaction.scrub(v.to_s) }
          end
          { status: response.status, headers: headers, body: body, captured_at: Time.now.utc.iso8601 }
        end

        # GET /accounts → [Account]
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

        # GET /accounts/{id}/balances → [Balance], one per currency.
        def balances(response, provider_account_id:)
          entries = response.json.dig("Data", "Balance") || []
          captured_at = Time.now.utc.iso8601
          entries.group_by { |e| e.dig("Amount", "Currency") }.map do |currency, group|
            raise MappingError.new("balance entry missing Amount.Currency", field: :currency) if currency.nil?

            Balance.new(
              provider: Config::PROVIDER,
              provider_account_id: provider_account_id,
              currency: currency,
              available: pick_balance(group, currency) { |t| Dialect.available_balance_type?(t) },
              booked: pick_balance(group, currency) { |t| Dialect.booked_balance_type?(t) },
              captured_at: captured_at,
              raw: { entries: group, response: evidence(response) }
            )
          end
        end

        # POST /account-access-consents (or its GET) → Consent. No interaction —
        # the authorize URL is built + signed by the adapter (Hybrid Flow).
        def consent(response)
          data = response.json["Data"] || {}
          Consent.new(
            provider: Config::PROVIDER,
            consent_id: data["ConsentId"],
            status: Dialect.consent_status(data["Status"]),
            raw_status: data["Status"],
            valid_until: data["ExpirationDateTime"] || data["CutOffDateTime"],
            raw: evidence(response)
          )
        end
        def consent_status(response) = consent(response)

        # POST /token → Token
        def token(response)
          body = response.json
          Token.new(
            access_token: body["access_token"], token_type: body["token_type"] || "bearer",
            refresh_token: body["refresh_token"], expires_in: body["expires_in"], scope: body["scope"],
            obtained_at: Time.now.utc.iso8601, raw: evidence(response, redact: true)
          )
        end

        # POST /domestic-payments → PaymentSubmission (post-SCA, no interaction).
        def payment_submission(response, idempotency_key: nil)
          data = response.json["Data"] || {}
          ref = payment_reference(data["DomesticPaymentId"])
          PaymentSubmission.new(
            status: Dialect.payment_status(data["Status"], provider_reference: ref, raw: evidence(response)),
            provider_reference: ref, idempotency_key: idempotency_key,
            submitted_at: Time.now.utc.iso8601, raw: evidence(response)
          )
        end

        # GET /domestic-payments/{id} → PaymentStatus
        def payment_status(response, payment_id: nil)
          data = response.json["Data"] || {}
          Dialect.payment_status(
            data["Status"],
            provider_reference: payment_id && payment_reference(payment_id),
            raw: evidence(response)
          )
        end

        # --- helpers ---
        def payment_reference(id)
          return nil if id.to_s.empty?

          ProviderReference.new(value: id, kind: :payment, connector: Config::PROVIDER)
        end

        def iban_for(acc)
          entry = Array(acc["Account"]).find { |a| a["SchemeName"].to_s.include?("IBAN") }
          entry && entry["Identification"]
        end

        def identifier_name(acc)
          entry = Array(acc["Account"]).find { |a| a["Name"] }
          entry && entry["Name"]
        end

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
