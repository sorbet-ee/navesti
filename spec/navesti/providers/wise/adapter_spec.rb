# frozen_string_literal: true

require "base64"
require "tempfile"
require "openssl"

RSpec.describe Navesti::Providers::Wise::Adapter do
  # One OBSeal keypair for the suite, written to a temp PEM the Credentials can
  # read (RSA generation is slow; do it once).
  WISE_SIGNING_KEY = OpenSSL::PKey::RSA.new(2048)
  _kf = Tempfile.create(["obseal", ".pem"])
  _kf.write(WISE_SIGNING_KEY.to_pem)
  _kf.flush
  WISE_SIGNING_KEY_PATH = _kf.path

  FROZEN_NOW = 1_700_000_000

  def credentials(tpp_id: "ob-dummy-tpp", signing: true)
    Navesti::Credentials.new(
      client_cert_path: "c", client_key_path: "k", tpp_id: tpp_id,
      signing_key_path: signing ? WISE_SIGNING_KEY_PATH : nil,
      signing_kid: signing ? "kid-1" : nil
    )
  end

  def adapter(*responses, creds: credentials)
    http = FakeHTTPClient.new(*responses)
    a = described_class.new(
      credentials: creds, http: http,
      request_id: -> { "req-fixed" }, clock: -> { Time.at(FROZEN_NOW).utc }
    )
    [a, http]
  end

  def b64url(segment)
    Base64.urlsafe_decode64(segment + ("=" * ((4 - (segment.length % 4)) % 4)))
  end

  def jwt_part(jwt, index)
    JSON.parse(b64url(jwt.split(".")[index]))
  end

  describe "#app_token" do
    it "requests a client_credentials app token (form body + client_id, mTLS)" do
      a, http = adapter(Fixtures.wise_response("token"))
      token = a.app_token

      expect(token).to be_a(Navesti::Token)
      expect(token.access_token).to eq("wise-access-token-AAAA")
      req = http.last_request
      expect(req[:url]).to eq("https://openbanking.wise-sandbox.com/open-banking/auth/token")
      expect(req[:headers]["Content-Type"]).to eq("application/x-www-form-urlencoded")
      body = URI.decode_www_form(req[:body]).to_h
      expect(body).to include("grant_type" => "client_credentials", "scope" => "accounts", "client_id" => "ob-dummy-tpp")
    end

    it "raises CredentialError when tpp_id (the OBIE client_id) is not configured" do
      a, = adapter(creds: credentials(tpp_id: nil))
      expect { a.app_token }.to raise_error(Navesti::CredentialError, /client_id/)
    end
  end

  describe "#create_consent" do
    it "posts Permissions + Risk with the app token, returning a :received Consent" do
      a, http = adapter(Fixtures.wise_response("consent_awaiting", status: 201))
      consent = a.create_consent(access_token: "app-tok", permissions: %w[ReadAccountsBasic ReadBalances])

      expect(consent).to be_a(Navesti::Consent)
      expect(consent.consent_id).to eq("urn-wise-aac-000111")
      expect(consent.status).to eq(:received)
      expect(consent.interaction).to be_nil
      req = http.last_request
      expect(req[:url]).to end_with("/v3.1.11/aisp/account-access-consents")
      expect(req[:headers]["Authorization"]).to eq("Bearer app-tok")
      body = JSON.parse(req[:body])
      expect(body["Data"]["Permissions"]).to eq(%w[ReadAccountsBasic ReadBalances])
      expect(body["Risk"]).to eq({})
    end

    it "defaults to the balance-reading permission set" do
      a, http = adapter(Fixtures.wise_response("consent_awaiting", status: 201))
      a.create_consent(access_token: "t")
      expect(JSON.parse(http.last_request[:body])["Data"]["Permissions"]).to eq(%w[ReadAccountsBasic ReadBalances])
    end
  end

  describe "#authorize_url (signed Hybrid Flow)" do
    subject(:interaction) do
      a, = adapter
      a.authorize_url(consent_id: "123", redirect_uri: "https://ob-dummy-tpp/redirect", state: "st1", nonce: "n1")
    end

    it "returns a redirect Interaction to the identity authorize endpoint" do
      expect(interaction).to be_a(Navesti::Interaction)
      expect(interaction.type).to eq(:redirect)
      expect(interaction.url).to start_with("https://wise-sandbox.com/openbanking/authorize?")
      expect(interaction.state).to eq("st1")
    end

    it "carries a PS256 Request Object with the OBIE claims (intent = ConsentId)" do
      jwt = URI.decode_www_form(URI.parse(interaction.url).query).to_h.fetch("request")
      header = jwt_part(jwt, 0)
      payload = jwt_part(jwt, 1)

      expect(header).to include("alg" => "PS256", "kid" => "kid-1")
      expect(payload).to include(
        "iss" => "ob-dummy-tpp", "client_id" => "ob-dummy-tpp",
        "aud" => "https://openbanking.wise-sandbox.com",
        "response_type" => "code id_token", "redirect_uri" => "https://ob-dummy-tpp/redirect",
        "scope" => "openid accounts", "state" => "st1", "nonce" => "n1",
        "iat" => FROZEN_NOW, "exp" => FROZEN_NOW + 300
      )
      expect(payload.dig("claims", "id_token", "openbanking_intent_id", "value")).to eq("123")
      expect(payload.dig("claims", "userinfo", "openbanking_intent_id", "value")).to eq("123")
    end

    it "produces a signature the OBSeal public key verifies" do
      jwt = URI.decode_www_form(URI.parse(interaction.url).query).to_h.fetch("request")
      head, pay, sig = jwt.split(".")
      ok = WISE_SIGNING_KEY.verify_pss("SHA256", b64url(sig), "#{head}.#{pay}", salt_length: :digest, mgf1_hash: "SHA256")
      expect(ok).to be(true)
    end

    it "raises CredentialError when no signing key is configured" do
      a, = adapter(creds: credentials(signing: false))
      expect { a.authorize_url(consent_id: "123", redirect_uri: "https://t/cb") }
        .to raise_error(Navesti::CredentialError)
    end
  end

  describe "#exchange_code" do
    it "exchanges the code for the user access + refresh token pair" do
      a, http = adapter(Fixtures.wise_response("token"))
      token = a.exchange_code(code: "authcode", redirect_uri: "https://ob-dummy-tpp/redirect")

      expect(token.refresh_token).to eq("wise-refresh-token-BBBB")
      body = URI.decode_www_form(http.last_request[:body]).to_h
      expect(body).to include(
        "grant_type" => "authorization_code", "code" => "authcode",
        "redirect_uri" => "https://ob-dummy-tpp/redirect", "client_id" => "ob-dummy-tpp"
      )
    end
  end

  describe "AIS reads" do
    it "#accounts lists the consented accounts" do
      a, http = adapter(Fixtures.wise_response("accounts"))
      accounts = a.accounts(access_token: "user-tok")

      expect(accounts.map(&:provider_account_id)).to eq(%w[504 777 888])
      req = http.last_request
      expect(req[:url]).to end_with("/v3.1.11/aisp/accounts")
      expect(req[:headers]["Authorization"]).to eq("Bearer user-tok")
    end

    it "#balances reads per-currency balances for an account" do
      a, http = adapter(Fixtures.wise_response("account_balances"))
      balances = a.balances(access_token: "user-tok", account_id: "504")

      expect(balances.map(&:currency)).to contain_exactly("GBP", "EUR")
      expect(http.last_request[:url]).to end_with("/aisp/accounts/504/balances")
    end

    it "#consent_status polls the consent resource" do
      a, http = adapter(Fixtures.wise_response("consent_awaiting"))
      consent = a.consent_status(access_token: "app-tok", consent_id: "urn-wise-aac-000111")

      expect(consent.status).to eq(:received)
      expect(http.last_request[:url]).to end_with("/account-access-consents/urn-wise-aac-000111")
    end
  end

  describe "error guards" do
    it "raises ConsentError on a 401" do
      a, = adapter(FakeHTTPClient.json_response(status: 401, body: {}))
      expect { a.accounts(access_token: "bad") }.to raise_error(Navesti::ConsentError)
    end

    it "raises a typed ProviderError from an OBIE Errors[] body" do
      body = { "Code" => "400 BadRequest", "Errors" => [{ "ErrorCode" => "UK.OBIE.Field.Invalid", "Message" => "bad" }] }
      a, = adapter(FakeHTTPClient.json_response(status: 400, body: body))
      expect { a.accounts(access_token: "t") }.to raise_error(Navesti::ProviderError) do |e|
        expect(e.provider_code).to eq("UK.OBIE.Field.Invalid")
        expect(e.http_status).to eq(400)
      end
    end

    it "surfaces an OAuth error from the token endpoint" do
      a, = adapter(FakeHTTPClient.json_response(status: 400, body: { "error" => "invalid_client" }))
      expect { a.app_token }.to raise_error(Navesti::ProviderError) do |e|
        expect(e.provider_code).to eq("invalid_client")
      end
    end
  end

  describe "PISP (domestic)" do
    def payment_order(idempotency_key: "webapp-deadbeef", reference: "INV-001")
      Navesti::PaymentOrder.new(
        money: Navesti::Money.from_decimal("10.00", "GBP"),
        debtor: Navesti::AccountRef.iban("GB29NWBK60161331926819"),
        creditor: Navesti::AccountRef.iban("GB94BARC10201530093459"),
        creditor_name: "Acme Ltd",
        remittance_information: "invoice 001",
        end_to_end_reference: reference,
        idempotency_key: idempotency_key
      )
    end

    it "#create_domestic_payment_consent posts the Initiation with an x-idempotency-key" do
      a, http = adapter(Fixtures.wise_response("domestic_payment_consent_awaiting", status: 201))
      consent = a.create_domestic_payment_consent(access_token: "user-tok", order: payment_order)

      expect(consent.consent_id).to eq("urn-wise-dpc-555")
      expect(consent.status).to eq(:received)
      req = http.last_request
      expect(req[:url]).to end_with("/v3.1.11/pisp/domestic-payment-consents")
      expect(req[:headers]["x-idempotency-key"]).to eq("webapp-deadbeef")
      init = JSON.parse(req[:body]).dig("Data", "Initiation")
      expect(init["InstructedAmount"]).to eq("Amount" => "10.00", "Currency" => "GBP")
      expect(init["CreditorAccount"]).to eq(
        "SchemeName" => "UK.OBIE.IBAN", "Identification" => "GB94BARC10201530093459", "Name" => "Acme Ltd"
      )
      expect(init["RemittanceInformation"]).to eq("Reference" => "INV-001", "Unstructured" => "invoice 001")
    end

    it "#create_domestic_payment posts the ConsentId + Initiation and maps the submission" do
      a, http = adapter(Fixtures.wise_response("domestic_payment_accepted", status: 201))
      sub = a.create_domestic_payment(access_token: "user-tok", consent_id: "urn-wise-dpc-555", order: payment_order)

      expect(sub).to be_a(Navesti::PaymentSubmission)
      expect(sub.provider_reference.value).to eq("urn-wise-dp-999")
      expect(sub.status.status).to eq(:pending_execution)
      expect(sub.side_effect_possible).to be(true)
      body = JSON.parse(http.last_request[:body])
      expect(body.dig("Data", "ConsentId")).to eq("urn-wise-dpc-555")
      expect(http.last_request[:url]).to end_with("/v3.1.11/pisp/domestic-payments")
    end

    it "#domestic_payment_status reads the order status" do
      a, http = adapter(Fixtures.wise_response("domestic_payment_accepted"))
      st = a.domestic_payment_status(access_token: "user-tok", payment_id: "urn-wise-dp-999")

      expect(st.status).to eq(:pending_execution)
      expect(http.last_request[:url]).to end_with("/pisp/domestic-payments/urn-wise-dp-999")
    end

    it "validates the order before dialing (rejects an over-length GBP reference)" do
      a, = adapter
      expect { a.create_domestic_payment_consent(access_token: "t", order: payment_order(reference: "X" * 19)) }
        .to raise_error(Navesti::ValidationError, /18-char/)
    end
  end

  it "is constructible via Navesti.adapter(:wise)" do
    a = Navesti.adapter(:wise, credentials: credentials, env: :sandbox)
    expect(a).to be_a(described_class)
  end
end
