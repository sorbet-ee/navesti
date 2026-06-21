# frozen_string_literal: true

# Direct contract for the shared UK OBIE response grammar, independent of Wise or
# Revolut. An adopter supplies #provider_name and #dialect; the grammar maps the
# OBIE `Data` envelope into Navesti value objects with raw evidence preserved.
RSpec.describe Navesti::Mappers::UkObie do
  # Adopter: a fixed provider name + a concrete OBIE dialect (one that has
  # adopted the family, so its normalizers are callable) for classification.
  let(:mappers) do
    Module.new do
      extend Navesti::Mappers::UkObie
      def self.provider_name = "testbank"
      def self.dialect = Navesti::Providers::Wise::Dialect
    end
  end

  def response(body)
    FakeHTTPClient.json_response(status: 200, body: body)
  end

  it "brings #evidence along via the include (so extend carries it)" do
    expect(mappers).to respond_to(:evidence)
  end

  describe "#accounts" do
    it "maps the Data.Account[] envelope, surfacing the IBAN-scheme identifier" do
      r = response("Data" => { "Account" => [{
        "AccountId" => "acc-1", "Currency" => "GBP", "Nickname" => "Main", "AccountSubType" => "CurrentAccount",
        "AccountType" => "Personal", "Status" => "Enabled",
        "Account" => [{ "SchemeName" => "UK.OBIE.IBAN", "Identification" => "GB00BANK0001", "Name" => "Jane Doe" }]
      }] })
      a = mappers.accounts(r).first
      expect([a.provider, a.provider_account_id, a.iban, a.owner_name, a.cash_account_type, a.status])
        .to eq(["testbank", "acc-1", "GB00BANK0001", "Jane Doe", "Personal", "Enabled"])
      expect(a.raw[:account]["AccountId"]).to eq("acc-1") # raw evidence preserved
    end

    it "leaves iban nil when no IBAN-scheme identifier is present" do
      r = response("Data" => { "Account" => [{ "AccountId" => "acc-2", "Currency" => "GBP" }] })
      expect(mappers.accounts(r).first.iban).to be_nil
    end
  end

  describe "#balances" do
    it "groups by currency, classifies available/booked, and applies the Debit sign" do
      r = response("Data" => { "Balance" => [
        { "Type" => "InterimAvailable", "CreditDebitIndicator" => "Credit", "Amount" => { "Amount" => "100.00", "Currency" => "GBP" } },
        { "Type" => "InterimBooked",    "CreditDebitIndicator" => "Debit",  "Amount" => { "Amount" => "30.00",  "Currency" => "GBP" } }
      ] })
      b = mappers.balances(r, provider_account_id: "acc-1").first
      expect(b.currency).to eq("GBP")
      expect(b.available.amount_minor).to eq(10_000)
      expect(b.booked.amount_minor).to eq(-3_000) # Debit -> negative
      expect(b.provider).to eq("testbank")
    end

    it "raises MappingError when a balance entry lacks Amount.Currency" do
      r = response("Data" => { "Balance" => [{ "Type" => "InterimAvailable", "Amount" => { "Amount" => "1.00" } }] })
      expect { mappers.balances(r, provider_account_id: "x") }.to raise_error(Navesti::MappingError, /Currency/)
    end
  end

  describe "#consent / #consent_status" do
    it "maps ConsentId + Status (via the dialect) and the validity window" do
      r = response("Data" => { "ConsentId" => "c-1", "Status" => "AwaitingAuthorisation", "ExpirationDateTime" => "2026-09-01T00:00:00Z" })
      c = mappers.consent(r)
      expect([c.provider, c.consent_id, c.status, c.raw_status, c.valid_until])
        .to eq(["testbank", "c-1", :received, "AwaitingAuthorisation", "2026-09-01T00:00:00Z"])
    end

    it "falls back to CutOffDateTime for a payment consent" do
      r = response("Data" => { "ConsentId" => "pc-1", "Status" => "Authorised", "CutOffDateTime" => "2026-06-21T10:30:00Z" })
      expect(mappers.consent(r).valid_until).to eq("2026-06-21T10:30:00Z")
    end
  end

  describe "#token (secret body)" do
    it "maps the token and stores REDACTED evidence (the body is the secret)" do
      r = response("access_token" => "SECRET-TOKEN", "token_type" => "Bearer", "expires_in" => 3600, "scope" => "accounts")
      t = mappers.token(r)
      expect(t.access_token).to eq("SECRET-TOKEN") # the typed field still carries the real value
      expect(t.raw[:body]).not_to include("SECRET-TOKEN") # but evidence is scrubbed
    end
  end

  describe "#payment_submission / #payment_status" do
    it "maps a submission with the payment reference and status" do
      r = response("Data" => { "DomesticPaymentId" => "pay-9", "Status" => "AcceptedSettlementInProcess" })
      sub = mappers.payment_submission(r, idempotency_key: "idem-1")
      expect(sub.provider_reference.value).to eq("pay-9")
      expect(sub.provider_reference.connector).to eq("testbank")
      expect(sub.status.status).to eq(:pending_execution)
      expect(sub.idempotency_key).to eq("idem-1")
    end

    it "maps a status read, attaching the payment reference" do
      r = response("Data" => { "Status" => "AcceptedSettlementCompleted" })
      st = mappers.payment_status(r, payment_id: "pay-9")
      expect([st.status, st.safety_status, st.provider_reference.value]).to eq([:confirmed, :confirmed, "pay-9"])
    end
  end
end
