# frozen_string_literal: true

RSpec.describe Navesti::Providers::Revolut::Dialect do
  describe ".consent_status" do
    {
      "AwaitingAuthorisation" => :received,
      "Authorised"            => :valid,
      "Rejected"              => :rejected,
      "Revoked"               => :revoked_by_psu,
      "Expired"               => :expired,
      "Consumed"              => :consumed
    }.each do |raw, symbol|
      it("maps #{raw} -> #{symbol}") { expect(described_class.consent_status(raw)).to eq(symbol) }
    end

    it "maps unknown to :unknown, never :valid" do
      expect(described_class.consent_status("New")).to eq(:unknown)
      expect(described_class.consent_status(nil)).to eq(:unknown)
    end
  end

  describe ".payment_status (post-SCA: side_effect true except Rejected)" do
    {
      "Pending"                           => [:pending_execution, :pending,   true],
      "AcceptedSettlementInProcess"       => [:pending_execution, :pending,   true],
      "AcceptedWithoutPosting"            => [:pending_execution, :pending,   true],
      "AcceptedSettlementCompleted"       => [:confirmed,         :confirmed, true],
      "AcceptedCreditSettlementCompleted" => [:confirmed,         :confirmed, true],
      "Rejected"                          => [:rejected,          :rejected,  false]
    }.each do |raw, (status, safety, side_effect)|
      it "maps #{raw}" do
        r = described_class.payment_status(raw)
        expect([r.status, r.safety_status, r.side_effect_possible]).to eq([status, safety, side_effect])
        expect(r.raw_status).to eq(raw)
      end
    end

    it "maps unknown to :unknown / side_effect true, preserving raw" do
      r = described_class.payment_status("Whatever")
      expect(r.status).to eq(:unknown)
      expect(r.side_effect_possible).to be(true)
      expect(r.raw_status).to eq("Whatever")
    end
  end

  describe "balance classification + debit?" do
    it "classifies available/booked types" do
      expect(described_class.available_balance_type?("InterimAvailable")).to be(true)
      expect(described_class.booked_balance_type?("ClosingBooked")).to be(true)
      expect(described_class.available_balance_type?("ClosingBooked")).to be(false)
    end

    it "treats only Debit as negative" do
      expect(described_class.debit?("Debit")).to be(true)
      expect(described_class.debit?("Credit")).to be(false)
    end
  end

  describe ".validate_payment_order!" do
    def order(currency: "GBP", reference: "INV-1", creditor_name: "Acme Ltd", creditor_iban: "GB94BARC10201530093459")
      Navesti::PaymentOrder.new(
        money: Navesti::Money.from_decimal("10.00", currency),
        debtor: Navesti::AccountRef.iban("GB29NWBK60161331926819"),
        creditor: creditor_iban ? Navesti::AccountRef.iban(creditor_iban) : Navesti::AccountRef.new(provider_account_id: "x"),
        creditor_name: creditor_name, end_to_end_reference: reference
      )
    end

    it "accepts a valid GBP order (<=18 char reference)" do
      expect { described_class.validate_payment_order!(order(reference: "INV-12345")) }.not_to raise_error
    end

    it "rejects a GBP reference over 18 chars" do
      expect { described_class.validate_payment_order!(order(reference: "X" * 19)) }
        .to raise_error(Navesti::ValidationError, /18-char limit for GBP/)
    end

    it "allows EUR up to 35 chars" do
      expect { described_class.validate_payment_order!(order(currency: "EUR", reference: "X" * 35)) }.not_to raise_error
      expect { described_class.validate_payment_order!(order(currency: "EUR", reference: "X" * 36)) }
        .to raise_error(Navesti::ValidationError, /35-char/)
    end

    it "requires a creditor IBAN and bounds the creditor name" do
      expect { described_class.validate_payment_order!(order(creditor_iban: nil)) }
        .to raise_error(Navesti::ValidationError, /creditor IBAN/)
      expect { described_class.validate_payment_order!(order(creditor_name: "N" * 71)) }
        .to raise_error(Navesti::ValidationError, /70-char/)
    end
  end

  describe "permission constants" do
    it "exposes OBIE AISP permissions + a balance-reading default" do
      expect(described_class::PERMISSIONS).to include("ReadAccountsBasic", "ReadBalances")
      expect(described_class::DEFAULT_PERMISSIONS).to eq(%w[ReadAccountsBasic ReadBalances])
    end
  end
end
