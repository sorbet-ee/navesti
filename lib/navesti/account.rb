# frozen_string_literal: true

module Navesti
  # A provider account *container* (an IBAN/resource), NOT money evidence
  # (docs/02-domain-model.md). Per-currency monetary values live in Balance.
  #
  # `provider_reported_currency` is preserved verbatim and is NOT
  # ISO-4217-validated: LHV accounts are multi-currency and report "XXX";
  # other providers may send nil. Real currency belongs to Balance.
  class Account < ValueObject
    attribute :provider
    attribute :provider_account_id
    attribute :provider_reported_currency, required: false
    attribute :iban, required: false
    attribute :owner_name, required: false
    attribute :name, required: false
    attribute :product, required: false
    attribute :cash_account_type, required: false
    attribute :status, required: false
    attribute :raw, required: false

    private

    def validate
      raise ValidationError, "Account#provider must be present" if provider.to_s.empty?
      if provider_account_id.to_s.empty?
        raise ValidationError, "Account#provider_account_id must be present"
      end
      # Deliberately NO currency validation — see class docs.
    end
  end
end
