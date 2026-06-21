# frozen_string_literal: true

# Direct contract for the shared UK OBIE dialect family, independent of Wise or
# Revolut. A future OBIE bank adopts this and inherits exactly these semantics.
RSpec.describe Navesti::Dialects::UkObie do
  # An adopter that supplies only #provider_label, so validation messages can be
  # checked for the substitution.
  let(:dialect) do
    Module.new do
      extend Navesti::Dialects::UkObie
      def self.provider_label = "TestBank"
    end
  end

  describe ".consent_status" do
    {
      "AwaitingAuthorisation" => :received, "Authorised" => :valid, "Rejected" => :rejected,
      "Revoked" => :revoked_by_psu, "Expired" => :expired, "Consumed" => :consumed
    }.each do |raw, sym|
      it("maps #{raw} -> #{sym}") { expect(dialect.consent_status(raw)).to eq(sym) }
    end

    it "never maps an unknown status to :valid" do
      expect(dialect.consent_status("Brand New")).to eq(:unknown)
      expect(dialect.consent_status(nil)).to eq(:unknown)
      expect(dialect.known_consent_status?("Authorised")).to be(true)
      expect(dialect.known_consent_status?("Nope")).to be(false)
    end
  end

  describe ".payment_status (post-SCA: side_effect true except Rejected)" do
    {
      "Pending" => [:pending_execution, :pending, true],
      "AcceptedSettlementCompleted" => [:confirmed, :confirmed, true],
      "Rejected" => [:rejected, :rejected, false]
    }.each do |raw, (status, safety, side_effect)|
      it "maps #{raw} preserving the raw code" do
        r = dialect.payment_status(raw)
        expect([r.status, r.safety_status, r.side_effect_possible, r.raw_status]).to eq([status, safety, side_effect, raw])
      end
    end

    it "maps an unknown code to :unknown with side_effect_possible true" do
      r = dialect.payment_status("Whatever")
      expect([r.status, r.side_effect_possible, r.raw_status]).to eq([:unknown, true, "Whatever"])
    end
  end

  describe "balance classification + debit?" do
    it "classifies available vs booked types and only treats Debit as negative" do
      expect(dialect.available_balance_type?("InterimAvailable")).to be(true)
      expect(dialect.booked_balance_type?("ClosingBooked")).to be(true)
      expect(dialect.available_balance_type?("ClosingBooked")).to be(false)
      expect(dialect.debit?("Debit")).to be(true)
      expect(dialect.debit?("Credit")).to be(false)
    end
  end

  describe ".validate_payment_order! (host-side OBIE limits, labelled per bank)" do
    def order(currency: "GBP", reference: "INV-1", creditor_name: "Acme Ltd", creditor_iban: "GB94BARC10201530093459")
      Navesti::PaymentOrder.new(
        money: Navesti::Money.from_decimal("10.00", currency),
        debtor: Navesti::AccountRef.iban("GB29NWBK60161331926819"),
        creditor: creditor_iban ? Navesti::AccountRef.iban(creditor_iban) : Navesti::AccountRef.new(provider_account_id: "x"),
        creditor_name: creditor_name, end_to_end_reference: reference
      )
    end

    it "accepts a valid GBP order and bounds the reference (18 GBP / 35 default)" do
      expect { dialect.validate_payment_order!(order(reference: "INV-12345")) }.not_to raise_error
      expect { dialect.validate_payment_order!(order(reference: "X" * 19)) }
        .to raise_error(Navesti::ValidationError, /18-char limit for GBP/)
      expect { dialect.validate_payment_order!(order(currency: "EUR", reference: "X" * 36)) }
        .to raise_error(Navesti::ValidationError, /35-char/)
    end

    it "requires a creditor IBAN, bounds the name, and labels the message with the bank" do
      expect { dialect.validate_payment_order!(order(creditor_iban: nil)) }
        .to raise_error(Navesti::ValidationError, "TestBank domestic payment requires a creditor IBAN")
      expect { dialect.validate_payment_order!(order(creditor_name: "N" * 71)) }
        .to raise_error(Navesti::ValidationError, /70-char/)
    end
  end

  describe "tables (frozen, OBIE-standard)" do
    it "exposes the permission sets and freezes the tables" do
      expect(described_class::DEFAULT_PERMISSIONS).to eq(%w[ReadAccountsBasic ReadBalances])
      expect(described_class::PERMISSIONS).to include("ReadAccountsBasic", "ReadBalances", "ReadDirectDebits")
      expect(described_class::CONSENT_STATUS).to be_frozen
      expect(described_class::PAYMENT_STATUS).to be_frozen
    end
  end
end
