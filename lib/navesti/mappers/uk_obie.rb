# frozen_string_literal: true

require "time"

module Navesti
  module Mappers
    # The UK OBIE (Open Banking 3.1.x) response grammar: maps the OBIE `Data`
    # envelope into Navesti value objects, shared by every OBIE bank (Wise,
    # Revolut). Extracted under the ADR-0004 three-times rule alongside the OBIE
    # dialect (docs/adr/0007) — the mappers were identical bar the provider name
    # and dialect. Raw evidence is preserved on every object (docs/01, docs/07);
    # the available/booked split and the Debit sign are dialect decisions.
    #
    # A provider Mappers module adopts it with `extend` (the mappers become
    # callable as `Mappers.accounts`) and supplies two hooks:
    #
    #   module Mappers
    #     extend Navesti::Mappers::UkObie
    #     def self.provider_name = Config::PROVIDER   # "wise"
    #     def self.dialect       = Dialect            # Wise::Dialect
    #   end
    #
    # It includes Mappers::Evidence, so `extend`ing UkObie also brings #evidence.
    module UkObie
      include Navesti::Mappers::Evidence

      # GET /accounts → [Navesti::Account].
      #
      # The OBIE basic account has no single "iban" — identification lives in a
      # scheme-tagged inner Account[] (UK.OBIE.IBAN vs SortCodeAccountNumber), and
      # some currency accounts carry no inner details at all. Use the stable
      # AccountId as provider_account_id; surface iban only when an IBAN-scheme
      # entry is present. Raw preserves exactly what the bank sent.
      def accounts(response)
        list = response.json.dig("Data", "Account") || []
        captured_at = Time.now.utc.iso8601

        list.map do |acc|
          Account.new(
            provider: provider_name,
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

      # GET /accounts/{id}/balances → [Navesti::Balance], one per currency. OBIE
      # returns unsigned amounts with a CreditDebitIndicator; a Debit balance is
      # negative (the dialect classifies both the sign and the available/booked
      # split). All raw entries are preserved.
      def balances(response, provider_account_id:)
        entries = response.json.dig("Data", "Balance") || []
        captured_at = Time.now.utc.iso8601

        entries.group_by { |e| e.dig("Amount", "Currency") }.map do |currency, group|
          if currency.nil?
            raise MappingError.new("balance entry missing Amount.Currency", field: :currency)
          end

          Balance.new(
            provider: provider_name,
            provider_account_id: provider_account_id,
            currency: currency,
            available: pick_balance(group, currency) { |t| dialect.available_balance_type?(t) },
            booked: pick_balance(group, currency) { |t| dialect.booked_balance_type?(t) },
            captured_at: captured_at,
            raw: { entries: group, response: evidence(response) }
          )
        end
      end

      # POST /account-access-consents (or its GET) → Navesti::Consent. No
      # interaction: the OBIE authorize URL is built + signed by the adapter
      # (Hybrid Flow), not handed back in the consent body.
      def consent(response)
        data = response.json["Data"] || {}
        Consent.new(
          provider: provider_name,
          consent_id: data["ConsentId"],
          status: dialect.consent_status(data["Status"]),
          raw_status: data["Status"],
          # AIS consents carry ExpirationDateTime; PIS payment consents carry a
          # CutOffDateTime (30 min) instead — surface whichever is present.
          valid_until: data["ExpirationDateTime"] || data["CutOffDateTime"],
          raw: evidence(response)
        )
      end

      # GET /account-access-consents/{id} → Navesti::Consent (status-only use).
      def consent_status(response)
        consent(response)
      end

      # POST /token → Navesti::Token. The body is the secret — store redacted
      # evidence; the typed access_token field still carries the real value.
      def token(response)
        body = response.json
        Token.new(
          access_token: body["access_token"],
          token_type: body["token_type"] || "bearer",
          refresh_token: body["refresh_token"],
          expires_in: body["expires_in"],
          scope: body["scope"],
          obtained_at: Time.now.utc.iso8601,
          raw: evidence(response, redact: true)
        )
      end

      # POST /domestic-payments → Navesti::PaymentSubmission. No interaction: OBIE
      # runs SCA during the payment-CONSENT authorization, so the submission
      # carries a status, not a redirect.
      def payment_submission(response, idempotency_key: nil)
        data = response.json["Data"] || {}
        ref = payment_reference(data["DomesticPaymentId"])
        status = dialect.payment_status(data["Status"], provider_reference: ref, raw: evidence(response))

        PaymentSubmission.new(
          status: status,
          provider_reference: ref,
          idempotency_key: idempotency_key,
          submitted_at: Time.now.utc.iso8601,
          raw: evidence(response)
        )
      end

      # GET /domestic-payments/{id} → Navesti::PaymentStatus.
      def payment_status(response, payment_id: nil)
        data = response.json["Data"] || {}
        dialect.payment_status(
          data["Status"],
          provider_reference: payment_id && payment_reference(payment_id),
          raw: evidence(response)
        )
      end

      # --- helpers ---

      def payment_reference(payment_id)
        return nil if payment_id.to_s.empty?

        ProviderReference.new(value: payment_id, kind: :payment, connector: provider_name)
      end

      # First inner Account[] identifier tagged with an IBAN scheme, or nil.
      def iban_for(acc)
        entry = Array(acc["Account"]).find { |a| a["SchemeName"].to_s.include?("IBAN") }
        entry && entry["Identification"]
      end

      # The display Name on the first inner identifier, or nil.
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

        signed = dialect.debit?(entry["CreditDebitIndicator"]) ? "-#{amount}" : amount.to_s
        Money.from_decimal(signed, currency)
      end
    end
  end
end
