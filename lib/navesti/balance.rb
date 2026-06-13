# frozen_string_literal: true

module Navesti
  # A balance snapshot at a moment in time. The money-evidence object: this is
  # where real, ISO-4217 currency lives (Account is only a container — see
  # docs/02-domain-model.md). A multi-currency LHV account yields several
  # Balances, one per currency.
  #
  # Defined for the domain model; the LHV balances endpoint itself is deferred
  # past Phase 1 (docs/12-first-adapters.md).
  class Balance < ValueObject
    attribute :account_ref
    attribute :currency
    attribute :available, required: false   # Navesti::Money
    attribute :booked, required: false      # Navesti::Money
    attribute :credit_limit, required: false
    attribute :balance_type, required: false
    attribute :captured_at, required: false
    attribute :raw, required: false

    private

    def validate
      unless /\A[A-Z]{3}\z/.match?(currency.to_s)
        raise ValidationError, "Balance#currency must be ISO-4217 (real currency lives here), got #{currency.inspect}"
      end
    end
  end
end
