# frozen_string_literal: true

RSpec.describe Navesti::Money do
  describe ".from_decimal" do
    it "parses a EUR amount into minor units" do
      money = described_class.from_decimal("123.50", "EUR")
      expect(money.amount_minor).to eq(12_350)
      expect(money.currency).to eq("EUR")
    end

    it "uppercases and trims the currency" do
      expect(described_class.from_decimal("1.00", " eur ").currency).to eq("EUR")
    end

    it "handles zero-exponent currencies (JPY) without a decimal point" do
      expect(described_class.from_decimal("4000", "JPY").amount_minor).to eq(4000)
    end

    it "handles three-exponent currencies (BHD)" do
      expect(described_class.from_decimal("1.234", "BHD").amount_minor).to eq(1234)
    end

    it "rejects more precision than the currency allows" do
      expect { described_class.from_decimal("1.234", "EUR") }
        .to raise_error(Navesti::MappingError, /more precision/)
    end

    it "rejects non-decimal input" do
      expect { described_class.from_decimal("twelve", "EUR") }
        .to raise_error(Navesti::MappingError, /not a decimal/)
    end
  end

  describe "#to_decimal_string" do
    it "renders EUR minor units as a decimal string" do
      expect(described_class.new(amount_minor: 12_350, currency: "EUR").to_decimal_string).to eq("123.50")
    end

    it "pads fractional digits" do
      expect(described_class.new(amount_minor: 5, currency: "EUR").to_decimal_string).to eq("0.05")
    end

    it "renders negative amounts" do
      expect(described_class.new(amount_minor: -1_999, currency: "EUR").to_decimal_string).to eq("-19.99")
    end

    it "renders zero-exponent currencies with no point" do
      expect(described_class.new(amount_minor: 4000, currency: "JPY").to_decimal_string).to eq("4000")
    end

    it "round-trips decimal -> minor -> decimal" do
      %w[0.00 0.05 19.99 123.50 1000000.01].each do |str|
        expect(described_class.from_decimal(str, "EUR").to_decimal_string).to eq(str)
      end
    end
  end

  describe "validation" do
    it "rejects non-integer minor units" do
      expect { described_class.new(amount_minor: 1.5, currency: "EUR") }
        .to raise_error(Navesti::ValidationError, /Integer/)
    end

    it "rejects a malformed currency" do
      expect { described_class.new(amount_minor: 1, currency: "EURO") }
        .to raise_error(Navesti::ValidationError, /ISO-4217/)
    end
  end
end
