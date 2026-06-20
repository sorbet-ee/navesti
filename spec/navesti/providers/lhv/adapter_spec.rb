# frozen_string_literal: true

RSpec.describe Navesti::Providers::LHV::Adapter do
  let(:credentials) do
    Navesti::Credentials.new(
      client_cert_path: "certs/lhv_sandbox.crt",
      client_key_path: "certs/lhv_sandbox.key",
      tpp_id: "PSDEE-LHVTEST-e37b7b"
    )
  end

  def adapter(*responses)
    http = FakeHTTPClient.new(*responses)
    a = described_class.new(
      credentials: credentials,
      env: :sandbox,
      http: http,
      request_id: -> { "fixed-request-id" }
    )
    [a, http]
  end

  let(:order) do
    Navesti::PaymentOrder.new(
      money: Navesti::Money.new(amount_minor: 12_350, currency: "EUR"),
      debtor: Navesti::AccountRef.iban("EE717700771001735865"),
      creditor: Navesti::AccountRef.iban("EE857700771001735904"),
      creditor_name: "Donald Duck",
      remittance_information: "Sample payment 1 to Donald Duck",
      idempotency_key: "connector-key-123"
    )
  end

  # --- TPP verification ---

  describe "#tpp_verification" do
    it "normalizes ENABLED access with roles" do
      a, http = adapter(Fixtures.lhv_response("tpp_enabled"))
      result = a.tpp_verification

      expect(result).to be_a(Navesti::TppVerification)
      expect(result.access).to eq(:enabled)
      expect(result).to be_enabled
      expect(result.tpp_id).to eq("PSDEE-FI-10539549")
      expect(result.roles).to eq(%w[AIS PIS PIIS])
      expect(http.last_request[:headers]).to include("X-Request-ID" => "fixed-request-id")
    end

    it "normalizes BLOCKED access without raising" do
      a, = adapter(Fixtures.lhv_response("tpp_blocked"))
      result = a.tpp_verification
      expect(result.access).to eq(:blocked)
      expect(result).not_to be_enabled
    end

    it "derives :invalid_certificate from tppMessages (no access field)" do
      a, = adapter(Fixtures.lhv_response("tpp_cert_invalid", status: 401))
      expect(a.tpp_verification.access).to eq(:invalid_certificate)
    end

    it "preserves raw evidence" do
      a, = adapter(Fixtures.lhv_response("tpp_enabled"))
      expect(a.tpp_verification.raw[:body]).to include("ENABLED")
    end
  end

  # --- OAuth ---

  describe "#authorize_url" do
    it "builds a redirect interaction with the cert-derived client_id" do
      a, http = adapter
      interaction = a.authorize_url(redirect_uri: "https://host/callback", state: "st1")

      expect(interaction).to be_a(Navesti::Interaction)
      expect(interaction.type).to eq(:redirect)
      expect(interaction.state).to eq("st1")
      expect(interaction.url).to include("https://api.sandbox.lhv.eu/psd2/oauth/authorize")
      expect(interaction.url).to include("client_id=PSDEE-LHVTEST-e37b7b")
      expect(interaction.url).to include("scope=psd2")
      expect(interaction.url).to include("response_type=code")
      expect(interaction.url).to include("state=st1")
      expect(http.requests).to be_empty # URL construction only, no HTTP
    end
  end

  describe "#exchange_code" do
    it "exchanges a code for a token pair" do
      a, http = adapter(Fixtures.lhv_response("token"))
      token = a.exchange_code(code: "auth-code-xyz", redirect_uri: "https://host/callback")

      expect(token).to be_a(Navesti::Token)
      expect(token.access_token).to eq("test-access-token-AAAA")
      expect(token.refresh_token).to eq("test-refresh-token-BBBB")
      expect(token.expires_in).to eq(3599)

      req = http.last_request
      expect(req[:url]).to eq("https://api.sandbox.lhv.eu/psd2/oauth/token")
      expect(req[:headers]["Content-Type"]).to eq("application/x-www-form-urlencoded")
      expect(req[:body]).to include("grant_type=authorization_code")
      expect(req[:body]).to include("client_id=PSDEE-LHVTEST-e37b7b")
    end

    it "redacts token material from #inspect" do
      a, = adapter(Fixtures.lhv_response("token"))
      token = a.exchange_code(code: "c", redirect_uri: "https://host/cb")
      expect(token.inspect).not_to include("test-access-token-AAAA")
      expect(token.inspect).to include("[REDACTED]")
    end

    it "stores redacted raw evidence so Token#raw / #to_h cannot leak the token" do
      a, = adapter(Fixtures.lhv_response("token"))
      token = a.exchange_code(code: "c", redirect_uri: "https://host/cb")

      # The typed field still carries the real value (the host needs it)...
      expect(token.access_token).to eq("test-access-token-AAAA")
      # ...but the raw evidence body — the thing that looks persist-as-evidence
      # safe — does not duplicate the secret.
      expect(token.raw[:body]).not_to include("test-access-token-AAAA")
      expect(token.raw[:body]).not_to include("test-refresh-token-BBBB")
      expect(token.raw[:body]).to include("[REDACTED]")
    end

    it "raises a ProviderError on an OAuth error response" do
      err = FakeHTTPClient.json_response(status: 400, body: { "error" => "invalid_grant" })
      a, = adapter(err)
      expect { a.exchange_code(code: "bad", redirect_uri: "x") }
        .to raise_error(Navesti::ProviderError, /invalid_grant/)
    end
  end

  # --- AIS accounts-list ---

  describe "#accounts_list" do
    it "normalizes accounts, tolerating multi-currency 'XXX'" do
      a, http = adapter(Fixtures.lhv_response("accounts_list"))
      accounts = a.accounts_list(access_token: "test-access-token-AAAA")

      expect(accounts.size).to eq(2)
      first = accounts.first
      expect(first).to be_a(Navesti::Account)
      expect(first.provider_account_id).to eq("f3a1c2d4-0001-4a2b-9c3d-aaaabbbbcccc")
      expect(first.iban).to eq("EE717700771001735865")
      expect(first.owner_name).to eq("Liis-Mari Mannik")
      expect(first.provider_reported_currency).to eq("XXX") # not ISO-validated
      expect(first.cash_account_type).to eq("CACC")
      expect(first.status).to eq(:enabled)
      expect(accounts.last.status).to eq(:blocked)
    end

    it "falls back to IBAN as provider_account_id for the no-consent basic list (no resourceId)" do
      # GET /v1/accounts-list returns the "basic" Account schema, which has no
      # resourceId — only iban (OpenAPI: Account vs AccountResponse). The
      # consent variant carries resourceId; this fixture mirrors the no-consent
      # shape and must not raise "missing required attribute :provider_account_id".
      a, = adapter(Fixtures.lhv_response("accounts_list_no_consent"))
      accounts = a.accounts_list(access_token: "tok")

      expect(accounts.size).to eq(2)
      expect(accounts.first.provider_account_id).to eq("EE717700771001735865")
      expect(accounts.first.iban).to eq("EE717700771001735865")
      # raw preserves exactly what the bank sent — no fabricated resourceId.
      expect(accounts.first.raw[:account]).not_to have_key("resourceId")
    end

    it "sends Bearer auth, onlyActive, and X-Request-ID" do
      a, http = adapter(Fixtures.lhv_response("accounts_list"))
      a.accounts_list(access_token: "tok-123", only_active: true)

      req = http.last_request
      expect(req[:url]).to include("/v1/accounts-list?onlyActive=true")
      expect(req[:headers]["Authorization"]).to eq("Bearer tok-123")
      expect(req[:headers]).to include("X-Request-ID" => "fixed-request-id")
    end

    it "sends PSU-Corporate-ID for owner verification when provided" do
      a, http = adapter(Fixtures.lhv_response("accounts_list"))
      a.accounts_list(access_token: "tok", psu_corporate_id: "EE47101010033")
      expect(http.last_request[:headers]["PSU-Corporate-ID"]).to eq("EE47101010033")
    end

    it "raises ConsentError on 401" do
      a, = adapter(FakeHTTPClient.json_response(status: 401, body: {}))
      expect { a.accounts_list(access_token: "expired") }
        .to raise_error(Navesti::ConsentError)
    end

    it "raises ProviderError with the code on ROLE_INVALID" do
      a, = adapter(Fixtures.lhv_response("role_invalid", status: 400))
      expect { a.accounts_list(access_token: "tok", psu_corporate_id: "EE000") }
        .to raise_error(Navesti::ProviderError) { |e| expect(e.provider_code).to eq("ROLE_INVALID") }
    end

    it "preserves raw evidence per account" do
      a, = adapter(Fixtures.lhv_response("accounts_list"))
      account = a.accounts_list(access_token: "tok").first
      expect(account.raw[:account]["resourceId"]).to eq("f3a1c2d4-0001-4a2b-9c3d-aaaabbbbcccc")
    end
  end

  # --- AIS consent flow ---

  describe "#create_consent" do
    it "posts a consent request and returns a :received Consent with a redirect interaction" do
      a, http = adapter(Fixtures.lhv_response("consent_received", status: 201))
      consent = a.create_consent(
        access_token: "tok", valid_until: "2099-12-31", redirect_uri: "https://host/consent-cb"
      )

      expect(consent).to be_a(Navesti::Consent)
      expect(consent.consent_id).to eq("c0ffee00-0001-4a2b-9c3d-consent0001")
      expect(consent.status).to eq(:received)
      expect(consent.raw_status).to eq("received")
      expect(consent.valid_until).to eq("2099-12-31")
      expect(consent.recurring_indicator).to eq(false)
      expect(consent).to be_requires_authorization
      expect(consent.interaction.type).to eq(:redirect)
      expect(consent.interaction.url).to include("/ui/v2/consent/")
      expect(consent.interaction.provider_reference.kind).to eq(:consent)
    end

    it "sends Bearer, PSU-IP-Address, TPP-Redirect-URI, and a global allAccountsWithBalances JSON body" do
      a, http = adapter(Fixtures.lhv_response("consent_received", status: 201))
      a.create_consent(access_token: "tok-7", valid_until: "2099-12-31",
                       redirect_uri: "https://host/cb", psu_corporate_id: "EE47101010033")

      req = http.last_request
      expect(req[:url]).to eq("https://api.sandbox.lhv.eu/psd2/v1/consents")
      expect(req[:headers]["Authorization"]).to eq("Bearer tok-7")
      expect(req[:headers]["PSU-IP-Address"]).to eq("127.0.0.1")
      expect(req[:headers]["TPP-Redirect-URI"]).to eq("https://host/cb")
      expect(req[:headers]["PSU-Corporate-ID"]).to eq("EE47101010033")
      body = JSON.parse(req[:body])
      expect(body["access"]).to eq("availableAccounts" => "allAccountsWithBalances")
      expect(body["validUntil"]).to eq("2099-12-31")
      expect(body["combinedServiceIndicator"]).to eq(false)
    end

    it "coerces frequencyPerDay to 1 for a non-recurring consent, honoring it when recurring" do
      a, http = adapter(Fixtures.lhv_response("consent_received", status: 201),
                        Fixtures.lhv_response("consent_received", status: 201))
      a.create_consent(access_token: "tok", valid_until: "2099-12-31", redirect_uri: "https://host/cb",
                       recurring_indicator: false, frequency_per_day: 4)
      expect(JSON.parse(http.last_request[:body])["frequencyPerDay"]).to eq(1)

      a.create_consent(access_token: "tok", valid_until: "2099-12-31", redirect_uri: "https://host/cb",
                       recurring_indicator: true, frequency_per_day: 4)
      expect(JSON.parse(http.last_request[:body])["frequencyPerDay"]).to eq(4)
    end

    it "surfaces the available SCA methods" do
      a, = adapter(Fixtures.lhv_response("consent_received", status: 201))
      consent = a.create_consent(access_token: "tok", valid_until: "2099-12-31", redirect_uri: "https://host/cb")
      expect(consent.sca_methods).to all(be_a(Navesti::ScaMethod))
      expect(consent.sca_methods.map(&:method_id)).to contain_exactly("MID", "SID")
    end

    it "raises ConsentError on 401" do
      a, = adapter(FakeHTTPClient.json_response(status: 401, body: {}))
      expect { a.create_consent(access_token: "expired", valid_until: "2099-12-31", redirect_uri: "x") }
        .to raise_error(Navesti::ConsentError)
    end
  end

  describe "#consent_status" do
    it "polls the status endpoint and normalizes valid -> :valid" do
      a, http = adapter(Fixtures.lhv_response("consent_status_valid"))
      consent = a.consent_status(consent_id: "c0ffee00-0001-4a2b-9c3d-consent0001", access_token: "tok")

      expect(consent).to be_a(Navesti::Consent)
      expect(consent.consent_id).to eq("c0ffee00-0001-4a2b-9c3d-consent0001")
      expect(consent.status).to eq(:valid)
      expect(consent.raw_status).to eq("valid")
      expect(consent.interaction).to be_nil
      expect(http.last_request[:url])
        .to eq("https://api.sandbox.lhv.eu/psd2/v1/consents/c0ffee00-0001-4a2b-9c3d-consent0001/status")
    end
  end

  describe "#accounts_list with consent" do
    it "hits /v1/accounts, sends Consent-ID, and returns accounts keyed by resourceId" do
      a, http = adapter(Fixtures.lhv_response("accounts_with_consent"))
      accounts = a.accounts_list(access_token: "tok", consent_id: "consent-1")

      expect(accounts.size).to eq(2)
      expect(accounts.first.provider_account_id).to eq("f3a1c2d4-0001-4a2b-9c3d-aaaabbbbcccc")
      req = http.last_request
      expect(req[:url]).to include("/v1/accounts?onlyActive=true")
      expect(req[:headers]["Consent-ID"]).to eq("consent-1")
      expect(req[:headers]["Authorization"]).to eq("Bearer tok")
    end
  end

  # --- PIS SEPA JSON initiation ---

  describe "#initiate_sepa_payment" do
    it "returns a redirect submission for RCVD (pre-SCA, side_effect false)" do
      a, http = adapter(Fixtures.lhv_response("payment_rcvd", status: 201))
      submission = a.initiate_sepa_payment(
        order: order, access_token: "tok", redirect_uri: "https://host/ok"
      )

      expect(submission).to be_a(Navesti::PaymentSubmission)
      expect(submission.status.status).to eq(:requires_authorization)
      expect(submission.safety_status).to eq(:pending)
      expect(submission.side_effect_possible).to eq(false)
      expect(submission.provider_reference.value).to eq("ac8bab09-fdda-4b6d-8776-3a0583df574a")
      expect(submission.provider_reference.kind).to eq(:payment)
      expect(submission).to be_requires_authorization
      expect(submission.interaction.type).to eq(:redirect)
      expect(submission.interaction.url).to include("/ui/v2/payment/sepa/")
      expect(submission.status_url).to include("/status")
      expect(submission.idempotency_key).to eq("connector-key-123")
    end

    it "returns a confirmed submission with no interaction for an ACSC exemption" do
      a, = adapter(Fixtures.lhv_response("payment_acsc_exempt", status: 201))
      submission = a.initiate_sepa_payment(
        order: order, access_token: "tok", redirect_uri: "https://host/ok"
      )

      expect(submission.status.status).to eq(:confirmed)
      expect(submission.safety_status).to eq(:confirmed)
      expect(submission.side_effect_possible).to eq(true)
      expect(submission.interaction).to be_nil
      expect(submission).not_to be_requires_authorization
    end

    it "maps an explicit RJCT to rejected with side_effect false" do
      a, = adapter(Fixtures.lhv_response("payment_rjct", status: 201))
      submission = a.initiate_sepa_payment(
        order: order, access_token: "tok", redirect_uri: "https://host/ok"
      )
      expect(submission.safety_status).to eq(:rejected)
      expect(submission.side_effect_possible).to eq(false)
      expect(submission.interaction).to be_nil
    end

    it "converts amount_minor to a decimal string and sends redirect headers" do
      a, http = adapter(Fixtures.lhv_response("payment_rcvd", status: 201))
      a.initiate_sepa_payment(
        order: order, access_token: "tok",
        redirect_uri: "https://host/ok", nok_redirect_uri: "https://host/nok"
      )

      req = http.last_request
      body = JSON.parse(req[:body])
      expect(body["instructedAmount"]).to eq("currency" => "EUR", "amount" => "123.50")
      expect(body["debtorAccount"]).to eq("iban" => "EE717700771001735865")
      expect(body["creditorAccount"]).to eq("iban" => "EE857700771001735904")
      expect(body["creditorName"]).to eq("Donald Duck")
      expect(req[:headers]["TPP-Redirect-Preferred"]).to eq("true")
      expect(req[:headers]["TPP-Redirect-URI"]).to eq("https://host/ok")
      expect(req[:headers]["TPP-Nok-Redirect-URI"]).to eq("https://host/nok")
      expect(req[:url]).to eq("https://api.sandbox.lhv.eu/psd2/v1.1/payments/sepa-credit-transfers")
    end

    it "performs exactly one submission attempt (no hidden retry)" do
      a, http = adapter(Fixtures.lhv_response("payment_rcvd", status: 201))
      a.initiate_sepa_payment(order: order, access_token: "tok", redirect_uri: "https://host/ok")
      expect(http.requests.size).to eq(1)
    end
  end

  # --- PIS status polling ---

  describe "#payment_status" do
    it "normalizes ACSP to pending_execution with side_effect true" do
      a, http = adapter(Fixtures.lhv_response("payment_status_acsp"))
      status = a.payment_status(payment_id: "ac8bab09", access_token: "tok")

      expect(status.status).to eq(:pending_execution)
      expect(status.safety_status).to eq(:pending)
      expect(status.side_effect_possible).to eq(true)
      expect(http.last_request[:url]).to include("/ac8bab09/status")
    end
  end

  # --- AIS balances (LHV-2A) ---

  describe "#balances" do
    it "maps available and booked amounts to minor units" do
      a, http = adapter(Fixtures.lhv_response("balances_eur"))
      balances = a.balances(access_token: "tok", account_id: "acc-1")

      expect(balances.size).to eq(1)
      bal = balances.first
      expect(bal).to be_a(Navesti::Balance)
      expect(bal.currency).to eq("EUR")
      expect(bal.available_amount_minor).to eq(12_350)
      expect(bal.booked_amount_minor).to eq(12_000)
      expect(bal.provider_account_id).to eq("acc-1")
      expect(http.last_request[:url]).to include("/v1/accounts/acc-1/balances")
    end

    it "preserves all raw balance entries" do
      a, = adapter(Fixtures.lhv_response("balances_eur"))
      bal = a.balances(access_token: "tok", account_id: "acc-1").first
      types = bal.raw[:entries].map { |e| e["balanceType"] }
      expect(types).to contain_exactly("interimAvailable", "interimBooked")
    end

    it "returns one Balance per currency for multi-currency accounts" do
      a, = adapter(Fixtures.lhv_response("balances_multi"))
      balances = a.balances(access_token: "tok", account_id: "acc-1")

      by_currency = balances.to_h { |b| [b.currency, b] }
      expect(by_currency.keys).to contain_exactly("EUR", "GBP")
      expect(by_currency["EUR"].available_amount_minor).to eq(12_350)
      expect(by_currency["EUR"].booked_amount_minor).to eq(12_000)
      expect(by_currency["GBP"].available_amount_minor).to eq(5_000)
      expect(by_currency["GBP"].booked_amount_minor).to eq(4_910)
    end

    it "returns nil booked (never invents a value) when only available is present" do
      a, = adapter(Fixtures.lhv_response("balances_available_only"))
      bal = a.balances(access_token: "tok", account_id: "acc-1").first
      expect(bal.available_amount_minor).to eq(7_500)
      expect(bal.booked_amount_minor).to be_nil
    end

    it "returns nil available (never invents a value) when only booked is present" do
      a, = adapter(Fixtures.lhv_response("balances_booked_only"))
      bal = a.balances(access_token: "tok", account_id: "acc-1").first
      expect(bal.booked_amount_minor).to eq(20_000)
      expect(bal.available_amount_minor).to be_nil
    end

    it "sends Consent-ID and PSU-Corporate-ID headers when provided" do
      a, http = adapter(Fixtures.lhv_response("balances_eur"))
      a.balances(access_token: "tok", account_id: "acc-1",
                 consent_id: "consent-123", psu_corporate_id: "EE47101010033")
      req = http.last_request
      expect(req[:headers]["Consent-ID"]).to eq("consent-123")
      expect(req[:headers]["PSU-Corporate-ID"]).to eq("EE47101010033")
    end

    it "follows the bank's own balances href when given (no path hardcoding)" do
      a, http = adapter(Fixtures.lhv_response("balances_eur"))
      a.balances(access_token: "tok", account_id: "acc-1",
                 balances_href: "/v1/accounts/acc-1/balances")
      expect(http.last_request[:url]).to eq("https://api.sandbox.lhv.eu/psd2/v1/accounts/acc-1/balances")
    end

    it "raises ConsentError on 401" do
      a, = adapter(FakeHTTPClient.json_response(status: 401, body: {}))
      expect { a.balances(access_token: "expired", account_id: "acc-1") }
        .to raise_error(Navesti::ConsentError)
    end

    it "raises a clean MappingError (not a VO ValidationError) on a currency-less entry" do
      resp = FakeHTTPClient.json_response(body: {
        "balances" => [{ "balanceAmount" => { "amount" => "1.00" }, "balanceType" => "interimAvailable" }]
      })
      a, = adapter(resp)
      expect { a.balances(access_token: "tok", account_id: "acc-1") }
        .to raise_error(Navesti::MappingError, /currency/)
    end

    it "refuses an off-origin balances_href before sending credentials anywhere" do
      a, http = adapter # no responses queued
      expect do
        a.balances(access_token: "tok", account_id: "acc-1",
                   balances_href: "https://evil.com/v1/accounts/acc-1/balances")
      end.to raise_error(Navesti::UnsafeUrlError)
      expect(http.requests).to be_empty # never dialed out
    end
  end

  # --- OAuth token refresh (LHV-2A) ---

  describe "#refresh_token" do
    it "builds a refresh_token form request" do
      a, http = adapter(Fixtures.lhv_response("token_refreshed"))
      a.refresh_token(refresh_token: "test-refresh-token-BBBB")

      req = http.last_request
      expect(req[:url]).to eq("https://api.sandbox.lhv.eu/psd2/oauth/token")
      expect(req[:headers]["Content-Type"]).to eq("application/x-www-form-urlencoded")
      expect(req[:body]).to include("grant_type=refresh_token")
      expect(req[:body]).to include("refresh_token=test-refresh-token-BBBB")
      expect(req[:body]).to include("client_id=PSDEE-LHVTEST-e37b7b")
      expect(req[:body]).not_to include("redirect_uri") # not sent on refresh
    end

    it "returns an OAuthTokenSet with the fresh access token" do
      a, = adapter(Fixtures.lhv_response("token_refreshed"))
      token = a.refresh_token(refresh_token: "test-refresh-token-BBBB")
      expect(token).to be_a(Navesti::OAuthTokenSet)
      expect(token.access_token).to eq("test-access-token-REFRESHED")
    end

    it "redacts refresh_token material from error output" do
      err = Navesti::Error.new("refresh failed for refresh_token=super-secret-rt")
      expect(err.message).not_to include("super-secret-rt")
      expect(err.message).to include("[REDACTED]")
    end

    it "raises a ProviderError on an invalid_grant response" do
      resp = FakeHTTPClient.json_response(status: 400, body: { "error" => "invalid_grant" })
      a, = adapter(resp)
      expect { a.refresh_token(refresh_token: "expired-rt") }
        .to raise_error(Navesti::ProviderError, /invalid_grant/)
    end
  end

  # --- decoupled SCA discovery (LHV-2B) ---

  describe "decoupled SCA discovery on a submission" do
    it "surfaces the available SCA methods and the authorisation endpoint" do
      a, = adapter(Fixtures.lhv_response("payment_rcvd", status: 201))
      submission = a.initiate_sepa_payment(order: order, access_token: "tok", redirect_uri: "https://host/ok")

      expect(submission.sca_methods).to all(be_a(Navesti::ScaMethod))
      expect(submission.sca_method_ids).to contain_exactly("MID", "SID")
      expect(submission.sca_methods.first.authentication_type).to eq("SMS_OTP")
      expect(submission.decoupled_available?).to be(true)
      expect(submission.authorisation_url).to include("/authorisations")
    end

    it "reports no decoupled option for an ACSC exemption (no auth endpoint)" do
      a, = adapter(Fixtures.lhv_response("payment_acsc_exempt", status: 201))
      submission = a.initiate_sepa_payment(order: order, access_token: "tok", redirect_uri: "https://host/ok")
      expect(submission.sca_methods).to be_empty
      expect(submission.decoupled_available?).to be(false)
    end
  end

  # --- payment cancellation (LHV-2B) ---

  describe "#cancel_payment" do
    it "cancels via DELETE and returns a cancelled, no-side-effect status" do
      a, http = adapter(Fixtures.lhv_response("payment_cancelled"))
      status = a.cancel_payment(payment_id: "ac8bab09", access_token: "tok")

      expect(status.status).to eq(:cancelled)
      expect(status.safety_status).to eq(:rejected)
      expect(status.side_effect_possible).to eq(false)
      expect(http.last_request[:method]).to eq(:delete)
      expect(http.last_request[:url]).to include("/ac8bab09/cancel")
    end

    it "synthesizes a cancelled status for an empty 204 response" do
      resp = Navesti::HTTP::Response.new(status: 204, headers: {}, body: "")
      a, = adapter(resp)
      status = a.cancel_payment(payment_id: "p-1", access_token: "tok")
      expect(status.status).to eq(:cancelled)
      expect(status.side_effect_possible).to eq(false)
      expect(status.raw_status).to be_nil
    end

    it "raises (does not assume cancellation) when the bank rejects it post-SCA" do
      resp = FakeHTTPClient.json_response(
        status: 400,
        body: { "tppMessages" => [{ "category" => "ERROR", "code" => "CANCELLATION_INVALID" }] }
      )
      a, = adapter(resp)
      expect { a.cancel_payment(payment_id: "p-1", access_token: "tok") }
        .to raise_error(Navesti::ProviderError) { |e| expect(e.provider_code).to eq("CANCELLATION_INVALID") }
    end
  end

  # --- token revoke (LHV-2B) ---

  describe "#revoke_token" do
    it "revokes a refresh token and returns true" do
      a, http = adapter(Navesti::HTTP::Response.new(status: 200, headers: {}, body: ""))
      result = a.revoke_token(token: "test-refresh-token-BBBB", token_type_hint: "refresh_token")

      expect(result).to be(true)
      req = http.last_request
      expect(req[:url]).to eq("https://api.sandbox.lhv.eu/psd2/oauth/revoke")
      expect(req[:body]).to include("token=test-refresh-token-BBBB")
      expect(req[:body]).to include("token_type_hint=refresh_token")
      expect(req[:body]).to include("client_id=PSDEE-LHVTEST-e37b7b")
    end

    it "treats revoking a nonexistent token (200) as success" do
      a, = adapter(Navesti::HTTP::Response.new(status: 200, headers: {}, body: ""))
      expect(a.revoke_token(token: "already-gone")).to be(true)
    end

    it "surfaces the OAuth error on 401 (not masked as ConsentError)" do
      resp = FakeHTTPClient.json_response(status: 401, body: { "error" => "unauthorized_client" })
      a, = adapter(resp)
      expect { a.revoke_token(token: "x") }
        .to raise_error(Navesti::ProviderError) { |e| expect(e.provider_code).to eq("unauthorized_client") }
    end

    it "raises ProviderError on an invalid request (400)" do
      resp = FakeHTTPClient.json_response(status: 400, body: { "error" => "invalid_request" })
      a, = adapter(resp)
      expect { a.revoke_token(token: "x", token_type_hint: "bogus") }
        .to raise_error(Navesti::ProviderError, /invalid_request/)
    end
  end

  # --- bank link validation (review #1 / #7) ---

  describe "bank link validation" do
    it "drops an off-origin scaRedirect but still returns the initiated submission" do
      resp = FakeHTTPClient.json_response(status: 201, body: {
        "transactionStatus" => "RCVD", "paymentId" => "p-evil",
        "_links" => {
          "scaRedirect" => { "href" => "https://evil.com/phish" },
          "status" => { "href" => "/v1.1/payments/sepa-credit-transfers/p-evil/status" }
        }
      })
      a, = adapter(resp)
      sub = a.initiate_sepa_payment(order: order, access_token: "tok", redirect_uri: "https://host/ok")

      expect(sub.provider_reference.value).to eq("p-evil") # payment not discarded
      expect(sub.interaction).to be_nil                     # phishing redirect not surfaced
      expect(sub.safety_status).to eq(:pending)
    end

    it "absolutizes a safe relative status link to a full on-origin URL" do
      a, = adapter(Fixtures.lhv_response("payment_rcvd", status: 201))
      sub = a.initiate_sepa_payment(order: order, access_token: "tok", redirect_uri: "https://host/ok")
      expect(sub.status_url).to start_with("https://api.sandbox.lhv.eu/psd2/")
      expect(sub.status_url).to include("/status")
    end
  end

  # --- idempotency correlation (review #3) ---

  describe "idempotency correlation" do
    it "derives a stable X-Request-ID from the order idempotency_key" do
      a1, h1 = adapter(Fixtures.lhv_response("payment_rcvd", status: 201))
      a2, h2 = adapter(Fixtures.lhv_response("payment_rcvd", status: 201))
      a1.initiate_sepa_payment(order: order, access_token: "tok", redirect_uri: "https://host/ok")
      a2.initiate_sepa_payment(order: order, access_token: "tok", redirect_uri: "https://host/ok")

      id1 = h1.last_request[:headers]["X-Request-ID"]
      id2 = h2.last_request[:headers]["X-Request-ID"]
      expect(id1).to eq(id2)                    # same key -> same id across calls
      expect(id1).to match(/\A[0-9a-f-]{36}\z/) # UUID shape
      expect(id1).not_to eq("fixed-request-id")
    end

    it "falls back to the random request id when no idempotency_key is present" do
      no_key = Navesti::PaymentOrder.new(
        money: Navesti::Money.new(amount_minor: 100, currency: "EUR"),
        debtor: Navesti::AccountRef.iban("EE717700771001735865"),
        creditor: Navesti::AccountRef.iban("EE857700771001735904"),
        creditor_name: "Donald Duck"
      )
      a, http = adapter(Fixtures.lhv_response("payment_rcvd", status: 201))
      a.initiate_sepa_payment(order: no_key, access_token: "tok", redirect_uri: "https://host/ok")
      expect(http.last_request[:headers]["X-Request-ID"]).to eq("fixed-request-id")
    end
  end

  # --- end-to-end reference is intentionally not transmitted (review #6) ---

  it "does not transmit end_to_end_reference (LHV JSON SEPA has no such field)" do
    o = order.with(end_to_end_reference: "E2E-12345")
    a, http = adapter(Fixtures.lhv_response("payment_rcvd", status: 201))
    a.initiate_sepa_payment(order: o, access_token: "tok", redirect_uri: "https://host/ok")
    body = http.last_request[:body]
    expect(body).not_to include("E2E-12345")
    expect(body).not_to include("endToEnd")
  end

  # --- SEPA validation before dialing (review #8) ---

  describe "SEPA validation" do
    def bad_order(**over)
      base = {
        money: Navesti::Money.new(amount_minor: 100, currency: "EUR"),
        debtor: Navesti::AccountRef.iban("EE717700771001735865"),
        creditor: Navesti::AccountRef.iban("EE857700771001735904"),
        creditor_name: "Donald Duck"
      }
      Navesti::PaymentOrder.new(**base.merge(over))
    end

    it "rejects a non-EUR SEPA payment before sending anything" do
      a, http = adapter
      order = bad_order(money: Navesti::Money.new(amount_minor: 100, currency: "USD"))
      expect { a.initiate_sepa_payment(order: order, access_token: "t", redirect_uri: "x") }
        .to raise_error(Navesti::ValidationError, /EUR/)
      expect(http.requests).to be_empty
    end

    it "rejects an over-long creditor name (SEPA 70)" do
      a, = adapter
      expect do
        a.initiate_sepa_payment(order: bad_order(creditor_name: "x" * 71), access_token: "t", redirect_uri: "x")
      end.to raise_error(Navesti::ValidationError, /creditorName/)
    end

    it "rejects over-long remittance (SEPA 140)" do
      a, = adapter
      expect do
        a.initiate_sepa_payment(order: bad_order(remittance_information: "y" * 141), access_token: "t", redirect_uri: "x")
      end.to raise_error(Navesti::ValidationError, /remittance/)
    end
  end

  # --- transport error propagation ---

  describe "transport failures" do
    it "propagates a timeout as a side-effect-possible TransportError" do
      a, = adapter(Navesti::TransportError.new("timeout", side_effect_possible: true))
      expect { a.payment_status(payment_id: "p", access_token: "t") }
        .to raise_error(Navesti::TransportError) { |e| expect(e.side_effect_possible).to eq(true) }
    end
  end
end
