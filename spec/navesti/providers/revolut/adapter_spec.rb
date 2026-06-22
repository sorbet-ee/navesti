# frozen_string_literal: true

require "base64"
require "tempfile"
require "openssl"

RSpec.describe Navesti::Providers::Revolut::Adapter do
  REV_KEY = OpenSSL::PKey::RSA.new(2048)
  _kf = Tempfile.create(["rev", ".pem"]); _kf.write(REV_KEY.to_pem); _kf.flush
  REV_KEY_PATH = _kf.path

  def credentials(tpp_id: "a22b9251")
    Navesti::Credentials.new(
      client_cert_path: "c", client_key_path: "k", tpp_id: tpp_id,
      signing_key_path: REV_KEY_PATH, signing_kid: "navesti-revolut-sbx-1", tan: "sorbet.ee"
    )
  end

  def adapter(*responses, creds: credentials)
    http = FakeHTTPClient.new(*responses)
    [described_class.new(credentials: creds, http: http, request_id: -> { "rid" }, clock: -> { Time.at(1_700_000_000).utc }), http]
  end

  def b64url(s) = Base64.urlsafe_decode64(s + ("=" * ((4 - s.length % 4) % 4)))

  it "is constructible via Navesti.adapter(:revolut)" do
    expect(Navesti.adapter(:revolut, credentials: credentials)).to be_a(described_class)
  end

  it "#app_token does client_credentials over the token host" do
    a, http = adapter(Fixtures.revolut_response("token"))
    expect(a.app_token.access_token).to eq("rev-access-AAAA")
    req = http.last_request
    expect(req[:url]).to eq("https://sandbox-oba-auth.revolut.com/token")
    expect(URI.decode_www_form(req[:body]).to_h).to include("grant_type" => "client_credentials", "client_id" => "a22b9251")
  end

  describe "#create_consent" do
    subject(:run) { adapter(Fixtures.revolut_response("consent_awaiting", status: 201)) }

    it "returns a :received Consent and signs the body + sends financial-id" do
      a, http = run
      consent = a.create_consent(access_token: "app")
      expect(consent.status).to eq(:received)
      expect(consent.consent_id).to eq("rev-aac-111")
      req = http.last_request
      expect(req[:headers]["x-fapi-financial-id"]).to eq("001580000103UAvAAM")
      expect(req[:headers]["Authorization"]).to eq("Bearer app")
      expect(req[:headers]["x-jws-signature"]).to be_a(String)
    end

    it "the x-jws-signature is a valid PS256 JWS over the body, with the tan header" do
      a, http = run
      a.create_consent(access_token: "app")
      jws = http.last_request[:headers]["x-jws-signature"]
      head_b64, pay_b64, sig_b64 = jws.split(".")
      header = JSON.parse(b64url(head_b64))
      expect(header).to include("alg" => "PS256", "kid" => "navesti-revolut-sbx-1",
                                "http://openbanking.org.uk/tan" => "sorbet.ee")
      expect(header["crit"]).to eq(["http://openbanking.org.uk/tan"])
      # payload is the exact request body; signature verifies against our key
      expect(b64url(pay_b64)).to eq(http.last_request[:body])
      ok = REV_KEY.verify_pss("SHA256", b64url(sig_b64), "#{head_b64}.#{pay_b64}", salt_length: :digest, mgf1_hash: "SHA256")
      expect(ok).to be(true)
    end
  end

  it "#authorize_url builds a signed Hybrid Flow URL to the browser authorize host /ui" do
    a, = adapter
    i = a.authorize_url(consent_id: "rev-aac-111", redirect_uri: "https://tpp/cb", state: "s1")
    expect(i.type).to eq(:redirect)
    expect(i.url).to start_with("https://sandbox-oba.revolut.com/ui/index.html?")
    jwt = URI.decode_www_form(URI.parse(i.url).query).to_h.fetch("request")
    payload = JSON.parse(b64url(jwt.split(".")[1]))
    expect(payload.dig("claims", "id_token", "openbanking_intent_id", "value")).to eq("rev-aac-111")
    expect(payload["aud"]).to eq("https://sandbox-oba-auth.revolut.com")
  end

  it "#accounts and #balances map the OBIE envelope" do
    a, = adapter(Fixtures.revolut_response("accounts"))
    accs = a.accounts(access_token: "u")
    expect(accs.map(&:provider_account_id)).to eq(%w[rev-acc-1 rev-acc-2])
    expect(accs.first.iban).to eq("GB33REVO00996912345678")

    a2, http = adapter(Fixtures.revolut_response("account_balances"))
    bals = a2.balances(access_token: "u", account_id: "rev-acc-1")
    gbp = bals.first
    expect(gbp.available_amount_minor).to eq(25_000)
    expect(gbp.booked_amount_minor).to eq(-550)
    expect(http.last_request[:url]).to end_with("/accounts/rev-acc-1/balances")
  end

  it "#create_domestic_payment signs, sends x-idempotency-key, maps the submission" do
    order = Navesti::PaymentOrder.new(
      money: Navesti::Money.from_decimal("10.00", "GBP"),
      debtor: Navesti::AccountRef.iban("GB29NWBK60161331926819"),
      creditor: Navesti::AccountRef.iban("GB94BARC10201530093459"),
      creditor_name: "Acme Ltd", end_to_end_reference: "INV-1", idempotency_key: "rev-idem-1"
    )
    a, http = adapter(Fixtures.revolut_response("domestic_payment_accepted", status: 201))
    sub = a.create_domestic_payment(access_token: "u", consent_id: "rev-dpc-555", order: order)
    expect(sub.provider_reference.value).to eq("rev-dp-999")
    expect(sub.status.status).to eq(:pending_execution)
    expect(http.last_request[:headers]["x-idempotency-key"]).to eq("rev-idem-1")
    expect(http.last_request[:headers]["x-jws-signature"]).to be_a(String)
  end

  it "raises ConsentError on 401 and CredentialError without a client_id" do
    a, = adapter(FakeHTTPClient.json_response(status: 401, body: {}))
    expect { a.accounts(access_token: "bad") }.to raise_error(Navesti::ConsentError)
    a2, = adapter(creds: credentials(tpp_id: nil))
    expect { a2.app_token }.to raise_error(Navesti::CredentialError, /client_id/)
  end
end
