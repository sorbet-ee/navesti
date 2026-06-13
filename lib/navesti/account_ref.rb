# frozen_string_literal: true

module Navesti
  # A reference to a bank account used as input (debtor/creditor on a
  # PaymentOrder, or the target of an AIS call). For LHV this is IBAN-based.
  #
  # This is a *reference*, not the Account container object (docs/02): it
  # carries only what's needed to address an account in a request.
  class AccountRef < ValueObject
    attribute :iban, required: false
    attribute :provider_account_id, required: false
    attribute :currency, required: false

    # Convenience builder for the common IBAN case.
    def self.iban(value, currency: nil)
      new(iban: value, currency: currency)
    end

    private

    def validate
      if iban.nil? && provider_account_id.nil?
        raise ValidationError, "AccountRef needs at least an :iban or :provider_account_id"
      end
      if iban && !/\A[A-Z]{2}\d{2}[A-Z0-9]{1,30}\z/.match?(iban.to_s.delete(" "))
        raise ValidationError, "AccountRef#iban is not a well-formed IBAN: #{iban.inspect}"
      end
    end
  end
end
