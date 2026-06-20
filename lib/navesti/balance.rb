# frozen_string_literal: true

module Navesti
  # A balance snapshot for one currency at a moment in time. The money-evidence
  # object: this is where real, ISO-4217 currency lives (Account is only a
  # container — docs/02-domain-model.md). A multi-currency LHV account yields
  # several Balances, one per currency.
  #
  # Shape mirrors the AIS BalanceProvider port output (docs/03): currency +
  # available/booked money + captured_at + raw. `available`/`booked` are Money
  # (type-safe internally); the *_amount_minor delegators expose the flat
  # minor-unit fields the port contract names. Either may be nil when the bank
  # omits that balance type — Navesti never invents a number.
  class Balance < ValueObject
    attribute :provider
    attribute :provider_account_id
    attribute :currency                  # real ISO-4217 money currency
    attribute :available, required: false # Navesti::Money
    attribute :booked, required: false    # Navesti::Money
    attribute :captured_at, required: false
    attribute :raw, required: false

    # Flat minor-unit accessors matching the BalanceProvider port contract.
    def available_amount_minor = available&.amount_minor
    def booked_amount_minor = booked&.amount_minor

    private

    def validate
      # Real money currency lives here — reject the "XXX" container sentinel
      # that Account carries for multi-currency accounts (docs/02).
      if currency.to_s == "XXX" || !/\A[A-Z]{3}\z/.match?(currency.to_s)
        raise ValidationError,
              "Balance#currency must be a real ISO-4217 currency, not 'XXX', got #{currency.inspect}"
      end
      if available.nil? && booked.nil?
        raise ValidationError, "Balance needs at least one of :available or :booked"
      end
      check_money!(:available, available)
      check_money!(:booked, booked)
    end

    def check_money!(name, money)
      return if money.nil?
      raise ValidationError, "Balance##{name} must be a Navesti::Money" unless money.is_a?(Money)
      return if money.currency == currency

      raise ValidationError,
            "Balance##{name} currency #{money.currency} does not match Balance#currency #{currency}"
    end
  end
end
