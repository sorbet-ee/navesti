# frozen_string_literal: true

require "bigdecimal"

module Navesti
  # A quantity of money: integer minor units + ISO-4217 currency. The only
  # representation of amounts in Navesti. Amounts are `amount_minor`, never
  # `amount_cents` (CLAUDE.md rule 20). May be negative (AIS transactions).
  #
  # Decimal <-> minor conversion uses the currency's ISO-4217 exponent, never
  # a hardcoded *100 (docs/07-mapping-language.md). Conversion goes through
  # integer/BigDecimal arithmetic — never a binary Float.
  class Money < ValueObject
    # Currencies whose minor-unit exponent is not 2. Everything else defaults
    # to 2. Extend as real banks require; never guess at call sites.
    EXPONENTS = {
      "JPY" => 0, "KRW" => 0, "ISK" => 0, "HUF" => 0,
      "CLP" => 0, "VND" => 0, "XOF" => 0, "XAF" => 0,
      "BHD" => 3, "KWD" => 3, "OMR" => 3, "TND" => 3, "JOD" => 3,
    }.freeze
    DEFAULT_EXPONENT = 2

    attribute :amount_minor
    attribute :currency

    # Builds Money from a provider decimal string, e.g. ("123.50", "EUR").
    # Rejects values with more fractional digits than the currency allows —
    # a mapping error, not a rounding opportunity.
    def self.from_decimal(amount_string, currency)
      currency = normalize_currency(currency)
      exp = exponent_for(currency)
      str = amount_string.to_s.strip
      unless /\A-?\d+(\.\d+)?\z/.match?(str)
        raise MappingError.new("not a decimal amount: #{str.inspect}", field: :amount)
      end

      decimal = BigDecimal(str)
      scaled = decimal * (10**exp)
      unless scaled.frac.zero?
        raise MappingError.new(
          "amount #{str.inspect} has more precision than #{currency} allows (exponent #{exp})",
          field: :amount
        )
      end

      new(amount_minor: scaled.to_i, currency: currency)
    end

    def self.exponent_for(currency)
      EXPONENTS.fetch(normalize_currency(currency), DEFAULT_EXPONENT)
    end

    def self.normalize_currency(currency)
      currency.to_s.strip.upcase
    end

    # The provider-facing decimal string, e.g. 12_350 EUR -> "123.50".
    def to_decimal_string
      exp = self.class.exponent_for(currency)
      sign = amount_minor.negative? ? "-" : ""
      unit, frac = amount_minor.abs.divmod(10**exp)
      return "#{sign}#{unit}" if exp.zero?

      "#{sign}#{unit}.#{frac.to_s.rjust(exp, '0')}"
    end

    private

    def validate
      unless amount_minor.is_a?(Integer)
        raise ValidationError, "Money#amount_minor must be an Integer, got #{amount_minor.class}"
      end
      unless /\A[A-Z]{3}\z/.match?(currency.to_s)
        raise ValidationError, "Money#currency must be a 3-letter ISO-4217 code, got #{currency.inspect}"
      end
    end
  end
end
