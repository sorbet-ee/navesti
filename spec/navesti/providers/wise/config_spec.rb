# frozen_string_literal: true

RSpec.describe Navesti::Providers::Wise::Config do
  subject(:config) { described_class.new(env: :sandbox) }

  let(:api)      { "https://openbanking.wise-sandbox.com/open-banking" }
  let(:identity) { "https://wise-sandbox.com" }

  describe "endpoint builders" do
    it "builds the unversioned token URL on the API host" do
      expect(config.token_url).to eq("#{api}/auth/token")
    end

    it "builds the well-known URL on the identity host" do
      expect(config.well_known_url)
        .to eq("#{identity}/openbanking/.well-known/openid-configuration")
    end

    it "builds versioned AISP URLs" do
      expect(config.account_access_consents_url).to eq("#{api}/v3.1.11/aisp/account-access-consents")
      expect(config.accounts_url).to eq("#{api}/v3.1.11/aisp/accounts")
      expect(config.account_url("504")).to eq("#{api}/v3.1.11/aisp/accounts/504")
      expect(config.account_balances_url("504")).to eq("#{api}/v3.1.11/aisp/accounts/504/balances")
      expect(config.account_transactions_url("504")).to eq("#{api}/v3.1.11/aisp/accounts/504/transactions")
    end

    it "percent-encodes account id segments" do
      expect(config.account_url("a/b?c")).to eq("#{api}/v3.1.11/aisp/accounts/a%2Fb%3Fc")
    end

    it "selects the production hosts" do
      prod = described_class.new(env: :production)
      expect(prod.token_url).to eq("https://openbanking.transferwise.com/open-banking/auth/token")
      expect(prod.well_known_url).to eq("https://wise.com/openbanking/.well-known/openid-configuration")
    end

    it "raises on an unknown env" do
      expect { described_class.new(env: :staging) }.to raise_error(ArgumentError, /unknown Wise env/)
    end
  end

  describe "#oauth_authorize_url (Hybrid Flow)" do
    subject(:url) do
      config.oauth_authorize_url(
        client_id: "ob-dummy-tpp", redirect_uri: "https://ob-dummy-tpp/redirect",
        scope: "openid accounts", request_jwt: "eyJ0.signed.jwt", state: "st1", nonce: "n1"
      )
    end

    it "targets the identity host's authorize endpoint" do
      expect(url).to start_with("#{identity}/openbanking/authorize?")
    end

    it "carries response_type=code id_token, the signed request object, and the params" do
      q = URI.decode_www_form(URI.parse(url).query).to_h
      expect(q["response_type"]).to eq("code id_token")
      expect(q["client_id"]).to eq("ob-dummy-tpp")
      expect(q["redirect_uri"]).to eq("https://ob-dummy-tpp/redirect")
      expect(q["scope"]).to eq("openid accounts")
      expect(q["request"]).to eq("eyJ0.signed.jwt")
      expect(q["state"]).to eq("st1")
      expect(q["nonce"]).to eq("n1")
    end

    it "omits optional state/nonce when not supplied" do
      bare = config.oauth_authorize_url(
        client_id: "c", redirect_uri: "https://t/cb", scope: "openid accounts", request_jwt: "j"
      )
      q = URI.decode_www_form(URI.parse(bare).query).to_h
      expect(q).not_to have_key("state")
      expect(q).not_to have_key("nonce")
    end
  end

  describe "#absolute (origin-pinned link following)" do
    it "resolves a leading-slash path against the API origin" do
      expect(config.absolute("/open-banking/v3.1.11/aisp/accounts/504/balances"))
        .to eq("#{api}/v3.1.11/aisp/accounts/504/balances")
    end

    it "allows an absolute URL on the configured API origin and base path" do
      url = "#{api}/v3.1.11/aisp/accounts/504"
      expect(config.absolute(url)).to eq(url)
    end

    it "rejects a path outside the /open-banking base" do
      expect { config.absolute("https://openbanking.wise-sandbox.com/evil") }
        .to raise_error(Navesti::UnsafeUrlError)
    end

    it "rejects an off-origin absolute URL" do
      expect { config.absolute("https://evil.com/open-banking/x") }
        .to raise_error(Navesti::UnsafeUrlError)
    end

    it "rejects the identity host (different origin from the API root)" do
      expect { config.absolute("#{identity}/open-banking/x") }
        .to raise_error(Navesti::UnsafeUrlError)
    end

    it "rejects a look-alike host" do
      expect { config.absolute("https://openbanking.wise-sandbox.com.evil.com/open-banking/x") }
        .to raise_error(Navesti::UnsafeUrlError)
    end

    it "rejects userinfo-smuggled hosts" do
      expect { config.absolute("https://openbanking.wise-sandbox.com@evil.com/x") }
        .to raise_error(Navesti::UnsafeUrlError)
    end

    it "rejects a scheme downgrade" do
      expect { config.absolute("http://openbanking.wise-sandbox.com/open-banking/x") }
        .to raise_error(Navesti::UnsafeUrlError)
    end

    it "rejects protocol-relative and traversal URLs" do
      expect { config.absolute("//evil.com/x") }.to raise_error(Navesti::UnsafeUrlError)
      expect { config.absolute("/open-banking/../../etc") }.to raise_error(Navesti::UnsafeUrlError)
      expect { config.absolute("") }.to raise_error(Navesti::UnsafeUrlError)
    end
  end
end
