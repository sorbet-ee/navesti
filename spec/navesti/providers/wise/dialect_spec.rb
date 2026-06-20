# frozen_string_literal: true

RSpec.describe Navesti::Providers::Wise::Dialect do
  describe ".consent_status" do
    # OBIE Status => normalized symbol. The safety contract: an unknown status
    # never collapses to :valid. Pin it.
    {
      "AwaitingAuthorisation" => :received,
      "Authorised"            => :valid,
      "Rejected"              => :rejected,
      "Revoked"               => :revoked_by_psu,
      "Expired"               => :expired,
      "Consumed"              => :consumed
    }.each do |raw, symbol|
      it "maps #{raw} -> #{symbol}" do
        expect(described_class.consent_status(raw)).to eq(symbol)
      end
    end

    it "maps an unknown status to :unknown, never :valid" do
      expect(described_class.consent_status("SomethingNew")).to eq(:unknown)
      expect(described_class.consent_status(nil)).to eq(:unknown)
    end

    it "reports whether a status is known" do
      expect(described_class.known_consent_status?("Authorised")).to be(true)
      expect(described_class.known_consent_status?("authorised")).to be(false) # case-sensitive OBIE
    end
  end

  describe "balance type classification" do
    it "classifies available balance types" do
      %w[InterimAvailable ClosingAvailable ForwardAvailable OpeningAvailable Expected].each do |t|
        expect(described_class.available_balance_type?(t)).to be(true)
      end
      expect(described_class.available_balance_type?("InterimBooked")).to be(false)
    end

    it "classifies booked balance types" do
      %w[InterimBooked ClosingBooked OpeningBooked PreviouslyClosedBooked].each do |t|
        expect(described_class.booked_balance_type?(t)).to be(true)
      end
      expect(described_class.booked_balance_type?("InterimAvailable")).to be(false)
    end
  end

  describe ".debit?" do
    it "treats only Debit as negative" do
      expect(described_class.debit?("Debit")).to be(true)
      expect(described_class.debit?("Credit")).to be(false)
      expect(described_class.debit?(nil)).to be(false)
    end
  end

  describe "permission constants" do
    it "exposes the OBIE AISP permissions and a balance-reading default" do
      expect(described_class::PERMISSIONS).to include("ReadAccountsBasic", "ReadBalances", "ReadTransactionsDetail")
      expect(described_class::DEFAULT_PERMISSIONS).to eq(%w[ReadAccountsBasic ReadBalances])
    end
  end

  describe ".payment_status" do
    # The safety contract: a Wise payment-order is POSTed post-SCA, so every
    # status but Rejected is side_effect_possible: true. Pin it.
    {
      "Pending"                           => [:pending_execution, :pending,   true],
      "AcceptedSettlementInProcess"       => [:pending_execution, :pending,   true],
      "AcceptedWithoutPosting"            => [:pending_execution, :pending,   true],
      "AcceptedSettlementCompleted"       => [:confirmed,         :confirmed, true],
      "AcceptedCreditSettlementCompleted" => [:confirmed,         :confirmed, true],
      "Rejected"                          => [:rejected,          :rejected,  false]
    }.each do |raw, (status, safety, side_effect)|
      it "maps #{raw} -> #{status} / #{safety} / side_effect=#{side_effect}" do
        result = described_class.payment_status(raw)
        expect([result.status, result.safety_status, result.side_effect_possible]).to eq([status, safety, side_effect])
        expect(result.raw_status).to eq(raw)
      end
    end

    it "maps an unknown status to :unknown with side_effect true, preserving raw" do
      result = described_class.payment_status("SomethingNew")
      expect(result.status).to eq(:unknown)
      expect(result.side_effect_possible).to be(true)
      expect(result.raw_status).to eq("SomethingNew")
    end
  end

  describe ".validate_payment_order!" do
    def order(currency: "GBP", reference: "INV-1", creditor_name: "Acme Ltd", creditor_iban: "GB94BARC10201530093459")
      Navesti::PaymentOrder.new(
        money: Navesti::Money.from_decimal("10.00", currency),
        debtor: Navesti::AccountRef.iban("GB29NWBK60161331926819"),
        creditor: creditor_iban ? Navesti::AccountRef.iban(creditor_iban) : Navesti::AccountRef.new(provider_account_id: "x"),
        creditor_name: creditor_name,
        end_to_end_reference: reference
      )
    end

    it "accepts a GBP order with an <=18 char reference" do
      expect { described_class.validate_payment_order!(order(reference: "INV-12345")) }.not_to raise_error
    end

    it "rejects a GBP reference over 18 chars" do
      expect { described_class.validate_payment_order!(order(currency: "GBP", reference: "X" * 19)) }
        .to raise_error(Navesti::ValidationError, /18-char limit for GBP/)
    end

    it "allows EUR references up to 35 chars, rejecting longer" do
      expect { described_class.validate_payment_order!(order(currency: "EUR", reference: "X" * 35)) }.not_to raise_error
      expect { described_class.validate_payment_order!(order(currency: "EUR", reference: "X" * 36)) }
        .to raise_error(Navesti::ValidationError, /35-char limit for EUR/)
    end

    it "rejects a creditor name over 70 chars" do
      expect { described_class.validate_payment_order!(order(creditor_name: "N" * 71)) }
        .to raise_error(Navesti::ValidationError, /70-char/)
    end

    it "requires a creditor IBAN" do
      expect { described_class.validate_payment_order!(order(creditor_iban: nil)) }
        .to raise_error(Navesti::ValidationError, /creditor IBAN/)
    end
  end
end
