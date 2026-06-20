# frozen_string_literal: true

RSpec.describe Navesti::Providers::Revolut::Config do
  subject(:config) { described_class.new(env: :sandbox) }

  let(:api)   { "https://sandbox-oba.revolut.com" }
  let(:token) { "https://sandbox-oba-auth.revolut.com" }

  describe "endpoint builders" do
    it "builds the token URL on the auth host" do
      expect(config.token_url).to eq("#{token}/token")
    end

    it "uses the API origin as the request-object audience" do
      expect(config.audience).to eq(api)
    end

    it "builds the OBIE endpoints at the API root (no version prefix)" do
      expect(config.account_access_consents_url).to eq("#{api}/account-access-consents")
      expect(config.accounts_url).to eq("#{api}/accounts")
      expect(config.account_url("504")).to eq("#{api}/accounts/504")
      expect(config.account_balances_url("504")).to eq("#{api}/accounts/504/balances")
      expect(config.account_transactions_url("504")).to eq("#{api}/accounts/504/transactions")
      expect(config.domestic_payment_consents_url).to eq("#{api}/domestic-payment-consents")
      expect(config.domestic_payments_url).to eq("#{api}/domestic-payments")
      expect(config.domestic_payment_url("p1")).to eq("#{api}/domestic-payments/p1")
    end

    it "percent-encodes id segments" do
      expect(config.account_url("a/b")).to eq("#{api}/accounts/a%2Fb")
    end

    it "exposes the fixed financial id" do
      expect(described_class::FINANCIAL_ID).to eq("001580000103UAvAAM")
    end

    it "selects the production hosts" do
      prod = described_class.new(env: :production)
      expect(prod.token_url).to eq("https://auth.revolut.com/token")
      expect(prod.accounts_url).to eq("https://oba.revolut.com/accounts")
    end

    it "raises on an unknown env" do
      expect { described_class.new(env: :staging) }.to raise_error(ArgumentError, /unknown Revolut env/)
    end
  end

  describe "#oauth_authorize_url (Hybrid Flow UI)" do
    subject(:url) do
      config.oauth_authorize_url(
        client_id: "rev-client", redirect_uri: "https://tpp/cb",
        scope: "openid accounts", request_jwt: "eyJ.signed.jwt", state: "s1", nonce: "n1"
      )
    end

    it "targets the authorize UI on the API host" do
      expect(url).to start_with("#{api}/ui/index.html?")
    end

    it "carries response_type=code id_token, the request object, and params" do
      q = URI.decode_www_form(URI.parse(url).query).to_h
      expect(q).to include(
        "response_type" => "code id_token", "client_id" => "rev-client",
        "redirect_uri" => "https://tpp/cb", "scope" => "openid accounts",
        "request" => "eyJ.signed.jwt", "state" => "s1", "nonce" => "n1"
      )
    end
  end

  describe "#absolute (origin-pinned)" do
    it "resolves a root-relative path against the API origin" do
      expect(config.absolute("/accounts/504/balances")).to eq("#{api}/accounts/504/balances")
    end

    it "allows an absolute URL on the API origin" do
      expect(config.absolute("#{api}/accounts/504")).to eq("#{api}/accounts/504")
    end

    it "rejects off-origin, the token host, look-alikes, userinfo, downgrade, traversal" do
      [
        "https://evil.com/accounts",
        "#{token}/accounts",                               # different host
        "https://sandbox-oba.revolut.com.evil.com/x",
        "https://sandbox-oba.revolut.com@evil.com/x",
        "http://sandbox-oba.revolut.com/x",                # scheme downgrade
        "//evil.com/x",
        "/accounts/../../etc",
        ""
      ].each do |bad|
        expect { config.absolute(bad) }.to raise_error(Navesti::UnsafeUrlError), "expected #{bad.inspect} to be refused"
      end
    end
  end
end
