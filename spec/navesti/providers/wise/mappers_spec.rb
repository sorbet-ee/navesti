# frozen_string_literal: true

RSpec.describe Navesti::Providers::Wise::Mappers do
  describe ".accounts" do
    subject(:accounts) { described_class.accounts(Fixtures.wise_response("accounts")) }

    it "maps every account with the stable AccountId as provider_account_id" do
      expect(accounts.map(&:provider_account_id)).to eq(%w[504 777 888])
      expect(accounts).to all(be_a(Navesti::Account))
      expect(accounts).to all(have_attributes(provider: "wise"))
    end

    it "surfaces iban only for an IBAN-scheme account" do
      by_id = accounts.each_with_object({}) { |a, h| h[a.provider_account_id] = a }
      expect(by_id["777"].iban).to eq("BE00000000000000000") # UK.OBIE.IBAN
      expect(by_id["504"].iban).to be_nil                     # SortCodeAccountNumber
      expect(by_id["888"].iban).to be_nil                     # no inner details
    end

    it "carries currency, type/subtype, and the inner display name" do
      gbp = accounts.first
      expect(gbp.provider_reported_currency).to eq("GBP")
      expect(gbp.cash_account_type).to eq("Personal")
      expect(gbp.product).to eq("EMoney")
      expect(gbp.owner_name).to eq("Jane Doe (GBP)")
    end

    it "preserves the raw account object as evidence" do
      expect(accounts.first.raw[:account]).to include("AccountId" => "504")
    end
  end

  describe ".balances" do
    subject(:balances) { described_class.balances(Fixtures.wise_response("account_balances"), provider_account_id: "504") }

    it "groups by currency into one Balance each" do
      expect(balances.map(&:currency)).to contain_exactly("GBP", "EUR")
      expect(balances).to all(have_attributes(provider: "wise", provider_account_id: "504"))
    end

    it "classifies InterimAvailable vs InterimBooked into available/booked (minor units)" do
      gbp = balances.find { |b| b.currency == "GBP" }
      expect(gbp.available_amount_minor).to eq(10_000) # 100.00
      expect(gbp.booked_amount_minor).to eq(9_550)     # 95.50
    end

    it "applies the CreditDebitIndicator sign (Debit -> negative)" do
      eur = balances.find { |b| b.currency == "EUR" }
      expect(eur.available_amount_minor).to eq(-1_234) # Debit 12.34
      expect(eur.booked).to be_nil                     # no booked entry
    end

    it "raises a MappingError when an entry has no currency" do
      resp = FakeHTTPClient.json_response(body: { "Data" => { "Balance" => [{ "Type" => "InterimAvailable" }] } })
      expect { described_class.balances(resp, provider_account_id: "504") }
        .to raise_error(Navesti::MappingError, /Amount.Currency/)
    end
  end

  describe ".consent" do
    subject(:consent) { described_class.consent(Fixtures.wise_response("consent_awaiting", status: 201)) }

    it "maps Status -> :received and carries the ConsentId, with no interaction" do
      expect(consent).to be_a(Navesti::Consent)
      expect(consent.consent_id).to eq("urn-wise-aac-000111")
      expect(consent.status).to eq(:received)
      expect(consent.raw_status).to eq("AwaitingAuthorisation")
      expect(consent.interaction).to be_nil # authorize URL is built by the adapter, not returned
    end
  end

  describe ".token" do
    subject(:token) { described_class.token(Fixtures.wise_response("token")) }

    it "maps the OAuth token pair" do
      expect(token.access_token).to eq("wise-access-token-AAAA")
      expect(token.refresh_token).to eq("wise-refresh-token-BBBB")
      expect(token.expires_in).to eq(6000)
      expect(token.scope).to eq("accounts openbanking")
    end

    it "stores redacted evidence so raw never leaks the token" do
      expect(token.raw[:body]).not_to include("wise-access-token-AAAA")
    end
  end
end
