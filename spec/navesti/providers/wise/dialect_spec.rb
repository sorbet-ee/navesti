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
end
