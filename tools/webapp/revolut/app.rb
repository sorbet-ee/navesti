# frozen_string_literal: true

# Navesti × Revolut (UK OBIE) sandbox connectivity harness.
#
# A tiny Roda + htmx app that drives the Navesti Revolut adapter against the real
# sandbox, so you can exercise the whole journey in a browser instead of curl.
#
# THIS IS DEVELOPER TOOLING — a separate consumer of the gem, playing the role
# Sorbet-Cockpit will: it renders UX and opens bank URLs; Navesti returns
# normalized facts and interaction descriptors. The gem stays headless.
#
# Revolut is OBIE Hybrid Flow, so the journey differs from LHV's Berlin Group:
#   1. app token   — client_credentials over mTLS (the cert/registration smoke test)
#   2. consent     — POST a signed account-access-consent, get a ConsentId
#   3. authorize   — redirect the PSU to Revolut's UI with a signed Request Object
#                    (response_type=code id_token → params come back in the URL
#                    FRAGMENT, so the callback page bounces them to the server)
#   4. exchange    — authorization_code grant → a user access token
#   5. AIS/PIS     — accounts/balances, or domestic-payment consent → submit → status
#
# Boundaries (mirroring CLAUDE.md / the LHV harness):
#   - sandbox-only; live calls refuse unless REVOLUT_LIVE=1
#   - tokens live in server-side memory only — never in a cookie, never rendered
#   - all bank/user data is HTML-escaped; errors are already redaction-safe
#   - single-user localhost dev tool (global in-memory state, no sessions)

require "navesti"
require "roda"
require "securerandom"
require "cgi"
require "uri"

# A redaction-safe HTTP trace for the terminal. Wraps the gem's real client so
# we can see exactly what went to Revolut and what came back — which headers were
# present (x-jws-signature? x-idempotency-key?), the status, and the raw error
# body Revolut returned (the full Errors[].ErrorCode behind a 400/403). Every
# line is scrubbed through Navesti::Redaction (Bearer tokens, PEM, secret fields)
# before printing, and Authorization/x-jws-signature are masked outright.
# DEVELOPER TOOLING ONLY — the gem itself never logs (its client is silent).
#
# Enabled by default for the harness; set REVOLUT_DEBUG=0 to silence it.
class DebugHTTP
  BODY_LIMIT = 1200
  MASK_HEADERS = ["authorization", "x-jws-signature"].freeze
  $stdout.sync = true # unbuffered: trace lines reach the server terminal live
  @seq = 0

  class << self
    attr_accessor :seq
  end

  def initialize(inner = Navesti::HTTP::Client.new)
    @inner = inner
  end

  def request(method:, url:, headers: {}, body: nil, credentials: nil)
    n = (self.class.seq += 1)
    log(n, "→ #{method.to_s.upcase} #{scrub(url)}")
    log(n, "  headers: #{header_summary(headers)}")
    log(n, "  request body: #{snippet(body)}") if body

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    response = @inner.request(method: method, url: url, headers: headers, body: body, credentials: credentials)
    ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round

    marker = response.success? ? "←" : "← ⚠"
    log(n, "#{marker} HTTP #{response.status} (#{ms}ms)")
    error_summary(n, response) unless response.success?
    log(n, "  response body: #{snippet(response.body)}")
    response
  rescue Navesti::Error => e
    log(n, "✗ transport error: #{e.class} #{e.message}")
    raise
  end

  private

  # Surfaces Revolut's own error codes plainly. The OBIE error envelope is
  # { "Code", "Message", "Errors": [{ "ErrorCode", "Message", "Path" }] }; the
  # OAuth/OIDC envelope is { "error", "error_description" }. Neither is a secret
  # and both are the single most useful thing to see when a call is rejected.
  def error_summary(seq, response)
    body = response.json_or_nil
    return unless body.is_a?(Hash)

    Array(body["Errors"]).each do |e|
      next unless e.is_a?(Hash)

      label = [e["ErrorCode"], e["Path"]].compact.join(" @ ")
      text = e["Message"]
      log(seq, "  revolut error: #{label}#{text ? " — #{scrub(text.to_s)}" : ''}")
    end
    if body["error"]
      log(seq, "  revolut oauth error: #{body['error']}" \
               "#{body['error_description'] ? " — #{scrub(body['error_description'].to_s)}" : ''}")
    end
  end

  # Show every header so it's obvious which were sent, but never reveal the
  # bearer token or the detached JWS signature material.
  def header_summary(headers)
    return "(none)" if headers.nil? || headers.empty?

    pairs = headers.map do |k, v|
      value = MASK_HEADERS.include?(k.to_s.downcase) ? "[REDACTED]" : v
      "#{k}=#{value}"
    end
    scrub(pairs.join("  "))
  end

  def snippet(string)
    s = scrub(string.to_s)
    s.length > BODY_LIMIT ? "#{s[0, BODY_LIMIT]}… (#{s.length} bytes)" : s
  end

  def scrub(string)
    Navesti::Redaction.scrub(string.to_s)
  end

  # Write to the server process's stdout (the terminal running `rackup`) and
  # flush immediately, so the trace shows up live alongside the request log.
  def log(seq, message)
    $stdout.puts "[revolut ##{seq}] #{message}"
    $stdout.flush
  end
end

# A dev-tooling HTTP client that trusts a private CA bundle for SERVER-cert
# verification — the OpenBanking pre-production root that Revolut's OBIE
# endpoints chain to, which is not in the system trust store. The gem's client
# verifies against the system store only (and uses credentials.ca_chain_path
# solely as the *client* extra_chain_cert), so the HOST is expected to inject a
# transport client configured for the bank's PKI. That's exactly what this is —
# Navesti stays headless and transport-agnostic; trust config lives here.
#
# It only ADDS trust anchors; it never disables verification (no VERIFY_NONE).
class ObieTrustHTTP < Navesti::HTTP::Client
  def initialize(ca_bundle_path:, **kwargs)
    @ca_bundle_path = ca_bundle_path
    super(**kwargs)
  end

  private

  def default_cert_store
    store = super
    File.read(@ca_bundle_path).scan(/-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----/m).each do |pem|
      store.add_cert(OpenSSL::X509::Certificate.new(pem))
    rescue OpenSSL::X509::StoreError
      # already present — ignore
    end
    store
  end
end

class NavestiRevolutHarness < Roda
  # Single-user, in-memory dev state. Tokens stay in this process and are never
  # serialized to a cookie or rendered to the page. Revolut needs more moving
  # parts than LHV: a per-scope app token (client_credentials), a user token
  # (authorization_code), and two consent ids (AIS + PIS).
  STATE = {
    app_token: {},        # { "accounts" => "…", "payments" => "…" } — client_credentials, per scope
    user_token: nil,      # authorization_code token (after the Hybrid-Flow exchange)
    refresh_token: nil,
    user_scope: nil,      # what the current user token was authorized for
    oauth_state: nil,     # CSRF nonce echoed through the redirect
    oauth_nonce: nil,     # OIDC nonce, bound into the signed Request Object
    flow: nil,            # :accounts | :payments — what the pending authorize is for
    ais_consent_id: nil,
    pis_consent_id: nil,
    pending_order: nil,   # the payment params awaiting authorization + submit
    accounts: [],
    last_payment_id: nil
  }

  # Documented Revolut sandbox test data (public — not secrets). Prefilled so a
  # domestic payment can be tried with one click. Revolut sandbox seeds GBP
  # accounts; the UK.OBIE.IBAN scheme is what the adapter sends.
  SANDBOX_CREDITOR_IBAN = "GB29NWBK60161331926819"
  SANDBOX_CREDITOR_NAME = "Acme Receivables Ltd"

  # Fragments are built as plain strings (htmx swaps HTML), so no render/asset
  # plugins are needed — keeps the harness tiny.

  # --- helpers ---------------------------------------------------------------

  # The HOST builds Credentials; here we assemble them from REVOLUT_* env. Unlike
  # LHV's Credentials.from_env (which reads LHV_* and needs no signing material),
  # Revolut needs the OBSeal signing key + kid + tan and the OBIE client_id.
  def self.credentials
    # NB: credentials.ca_chain_path is the gem's *client* extra_chain_cert, not a
    # server trust anchor. Revolut's transport cert is Revolut-rooted and needs no
    # extra chain, so we leave it nil; the OBIE server-root trust is handled by the
    # injected ObieTrustHTTP (REVOLUT_CA_CHAIN_PATH), not here.
    Navesti::Credentials.new(
      client_cert_path: ENV.fetch("REVOLUT_CLIENT_CERT_PATH"),
      client_key_path: ENV.fetch("REVOLUT_CLIENT_KEY_PATH"),
      signing_key_path: ENV["REVOLUT_SIGNING_KEY_PATH"],
      signing_kid: ENV["REVOLUT_SIGNING_KID"],
      tan: ENV["REVOLUT_TAN"],
      tpp_id: ENV["REVOLUT_CLIENT_ID"] # OBIE client_id — the adapter's client_id
    )
  end

  # The transport client the host injects. When REVOLUT_CA_CHAIN_PATH points to a
  # CA bundle (the OBIE pre-prod root), trust it for server verification; the
  # DebugHTTP trace wraps whichever client we end up with.
  def self.http_client
    ca = ENV["REVOLUT_CA_CHAIN_PATH"]
    base = ca && File.file?(ca) ? ObieTrustHTTP.new(ca_bundle_path: ca) : Navesti::HTTP::Client.new
    debug? ? DebugHTTP.new(base) : base
  end

  def self.adapter
    Navesti.adapter(
      :revolut,
      credentials: credentials,
      env: (ENV["REVOLUT_ENV"] || "sandbox").to_sym,
      http: http_client
    )
  end

  # Terminal HTTP trace is on by default for this dev harness; REVOLUT_DEBUG=0 mutes.
  def self.debug? = ENV["REVOLUT_DEBUG"] != "0"

  def live? = ENV["REVOLUT_LIVE"] == "1"

  # Revolut returns the Hybrid-Flow params in the URL fragment, so the callback
  # is a JS bounce; the redirect_uri must match what's registered for the client.
  def redirect_uri
    ENV["REVOLUT_WEBAPP_REDIRECT_URI"] || "http://localhost:#{port}/oauth/callback"
  end

  def port = ENV["REVOLUT_WEBAPP_PORT"] || "9293"

  # True when the redirect lands back on this server (the automatic JS-bounce
  # callback works). False for an off-host registered URI → manual paste-back.
  def local_callback?
    host = URI.parse(redirect_uri).host.to_s
    host == "localhost" || host == "127.0.0.1"
  rescue URI::InvalidURIError
    false
  end

  # Parse a pasted post-SCA callback URL into the OAuth fields. The Hybrid Flow
  # returns them in the fragment; fall back to the query string.
  def parse_callback_url(raw)
    u = URI.parse(raw.to_s.strip)
    src = u.fragment.to_s.empty? ? u.query.to_s : u.fragment.to_s
    p = (URI.decode_www_form(src).to_h if !src.empty?) || {}
    { code: p["code"], state: p["state"], error: p["error"], error_description: p["error_description"] }
  rescue URI::InvalidURIError, ArgumentError
    { code: nil, state: nil, error: "invalid_url", error_description: "Could not parse the pasted callback URL." }
  end

  # Shared authorization-code → token exchange, used by both the automatic
  # callback (/oauth/exchange) and the manual paste-back (/oauth/paste).
  def complete_authorization(code:, state:, error: nil, error_description: nil)
    if nilify(error)
      return layout(notice("Authorization failed: #{h(error)} #{h(error_description)}", kind: "err") + home_body)
    end
    return layout(notice("OAuth state mismatch — aborted.", kind: "err") + home_body) if state != STATE[:oauth_state]
    return layout(notice("No authorization code found in the callback.", kind: "err") + home_body) if nilify(code).nil?

    tok = self.class.adapter.exchange_code(code: code, redirect_uri: redirect_uri)
    STATE[:user_token] = tok.access_token
    STATE[:refresh_token] = tok.refresh_token
    STATE[:user_scope] = tok.scope || (STATE[:flow] == :payments ? "payments" : "accounts")
    next_hint =
      if STATE[:flow] == :payments
        "Payment authorized — go to step 5 and submit the domestic payment."
      else
        "Account access authorized — go to step 4 and list accounts."
      end
    layout(notice("Authenticated. token_type=#{h(tok.token_type)} scope=#{h(tok.scope)} " \
                  "expires_in=#{h(tok.expires_in)}s. #{next_hint}", kind: "ok") + home_body)
  rescue Navesti::Error => e
    layout(notice("Token exchange failed: #{e.message}", kind: "err") + home_body)
  end

  def user_token = STATE[:user_token]

  def app_token(scope) = STATE[:app_token][scope]

  def h(value)
    CGI.escapeHTML(value.to_s)
  end

  # Runs an adapter call, rendering an error fragment on any Navesti error.
  def guarded
    return warn_offline unless live?

    yield
  rescue Navesti::CredentialError => e
    err("#{e.message}. Check the REVOLUT_SIGNING_KEY_PATH / REVOLUT_SIGNING_KID / REVOLUT_TAN " \
        "and REVOLUT_CLIENT_ID env vars — Revolut signs every write and needs the OBSeal key.")
  rescue Navesti::ConsentError => e
    err("#{e.message}. The access token was rejected — for AIS/PIS calls you need a USER token " \
        "from the authorize → exchange step, not the client_credentials app token.")
  rescue Navesti::Error => e
    err(e.message) # already redaction-safe via Navesti::Error
  end

  def warn_offline
    notice("Refusing live Revolut call. Start the server with REVOLUT_LIVE=1.", kind: "warn")
  end

  def notice(msg, kind: "ok")
    %(<div class="notice #{kind}">#{h(msg)}</div>)
  end

  def err(msg)
    notice("Error: #{msg}", kind: "err")
  end

  def nilify(value)
    s = value.to_s.strip
    s.empty? ? nil : s
  end

  # --- routes ----------------------------------------------------------------

  route do |r|
    r.root { layout(home_body) }

    # Step 1 — client_credentials app token (the mTLS + registration smoke test)
    r.post "app-token" do
      guarded do
        scope = nilify(r.params["scope"]) || "accounts"
        tok = self.class.adapter.app_token(scope: scope)
        STATE[:app_token][scope] = tok.access_token
        notice("App token acquired (scope=#{h(scope)}). token_type=#{h(tok.token_type)} " \
               "expires_in=#{h(tok.expires_in)}s — held server-side, not shown.", kind: "ok")
      end
    end

    # Step 2 — create the AIS account-access-consent (signed POST)
    r.post "consents" do
      guarded do
        next err("No accounts app token — run step 1 first.") unless app_token("accounts")

        permissions = Array(r.params["permissions"]).map { |p| nilify(p) }.compact
        permissions = Navesti::Providers::Revolut::Dialect::DEFAULT_PERMISSIONS if permissions.empty?
        consent = self.class.adapter.create_consent(access_token: app_token("accounts"), permissions: permissions)
        STATE[:ais_consent_id] = consent.consent_id
        consent_panel(consent, flow: :accounts)
      end
    end

    # Step 3 — Hybrid Flow authorize (signed Request Object) + fragment callback
    r.on "oauth" do
      r.get "start" do
        flow = r.params["flow"] == "payments" ? :payments : :accounts
        consent_id = flow == :payments ? STATE[:pis_consent_id] : STATE[:ais_consent_id]
        unless consent_id
          next layout(notice("No #{flow} consent yet — create one first.", kind: "err") + home_body)
        end

        STATE[:flow] = flow
        STATE[:oauth_state] = "navesti-#{SecureRandom.hex(8)}"
        STATE[:oauth_nonce] = SecureRandom.hex(8)
        interaction = self.class.adapter.authorize_url(
          consent_id: consent_id, redirect_uri: redirect_uri,
          scope: flow == :payments ? "openid payments" : "openid accounts",
          state: STATE[:oauth_state], nonce: STATE[:oauth_nonce]
        )
        r.redirect interaction.url
      end

      # Revolut returns response_type=code id_token in the URL FRAGMENT, which the
      # server cannot see. Serve a tiny page that reads location.hash (falling back
      # to the query string) and POSTs the code/state back to /oauth/exchange.
      r.get "callback" do
        callback_bounce
      end

      # The fragment-bounce page (local callback) lands here with the code/state
      # as form fields.
      r.post "exchange" do
        complete_authorization(code: r.params["code"], state: r.params["state"],
                               error: r.params["error"], error_description: r.params["error_description"])
      end

      # Manual paste-back: when the registered redirect_uri is off-host (e.g.
      # https://www.sorbet.ee, the only URI registered for this OBIE client), the
      # browser lands there with #code=…&state=… in the address bar — the server
      # never sees it. Paste the whole URL here; we parse the fragment/query and
      # run the same exchange. The redirect_uri sent to /token still matches the
      # one used at authorize, so the code binds correctly.
      r.post "paste" do
        complete_authorization(**parse_callback_url(r.params["callback_url"]))
      end
    end

    # Step 4 — accounts & balances (AIS, user token)
    r.post "accounts" do
      guarded do
        next err("No user token — authorize account access first (steps 2–3).") unless user_token

        STATE[:accounts] = self.class.adapter.accounts(access_token: user_token)
        accounts_table(STATE[:accounts])
      end
    end

    r.post "balances" do
      guarded do
        next err("No user token.") unless user_token

        account_id = nilify(r.params["account_id"])
        next err("Pick an account.") unless account_id

        balances = self.class.adapter.balances(access_token: user_token, account_id: account_id)
        balances_table(account_id, balances)
      end
    end

    # Step 5 — PIS (domestic payment): consent → authorize → submit → status
    r.on "payments" do
      r.post "consent" do
        guarded do
          # Payments need their own client_credentials app token (payments scope).
          unless app_token("payments")
            tok = self.class.adapter.app_token(scope: "payments")
            STATE[:app_token]["payments"] = tok.access_token
          end

          STATE[:pending_order] = order_params(r.params)
          consent = self.class.adapter.create_domestic_payment_consent(
            access_token: app_token("payments"), order: build_order(STATE[:pending_order])
          )
          STATE[:pis_consent_id] = consent.consent_id
          consent_panel(consent, flow: :payments)
        end
      end

      r.post "submit" do
        guarded do
          next err("No user token — authorize the payment first (step 5b).") unless user_token
          next err("No payment consent — create one first (step 5a).") unless STATE[:pis_consent_id]
          next err("No pending order.") unless STATE[:pending_order]

          sub = self.class.adapter.create_domestic_payment(
            access_token: user_token, consent_id: STATE[:pis_consent_id],
            order: build_order(STATE[:pending_order])
          )
          STATE[:last_payment_id] = sub.provider_reference&.value
          submission_panel(sub)
        end
      end

      r.post "status" do
        guarded do
          next err("No user token.") unless user_token

          pid = nilify(r.params["payment_id"]) || STATE[:last_payment_id]
          next err("No payment id.") unless pid

          st = self.class.adapter.domestic_payment_status(access_token: user_token, payment_id: pid)
          status_panel(pid, st)
        end
      end
    end

    r.post "forget" do
      STATE[:user_token] = nil
      STATE[:refresh_token] = nil
      STATE[:user_scope] = nil
      auth_status
    end
  end

  # --- view fragments --------------------------------------------------------

  def build_order(params)
    Navesti::PaymentOrder.new(
      money: Navesti::Money.from_decimal(params["amount"] || "1.00", params["currency"] || "GBP"),
      debtor: Navesti::AccountRef.iban(params["debtor_iban"] || SANDBOX_CREDITOR_IBAN),
      creditor: Navesti::AccountRef.iban(params["creditor_iban"] || SANDBOX_CREDITOR_IBAN),
      creditor_name: params["creditor_name"] || SANDBOX_CREDITOR_NAME,
      remittance_information: params["remittance"] || "navesti harness",
      end_to_end_reference: params["reference"] || "navesti-#{SecureRandom.hex(4)}",
      idempotency_key: params["idempotency_key"] || "webapp-#{SecureRandom.hex(6)}"
    )
  end

  # Snapshot the form into a plain hash so the order survives the authorize
  # redirect (the gem never holds packet state — the harness owns this).
  def order_params(params)
    {
      "amount" => nilify(params["amount"]) || "1.00",
      "currency" => nilify(params["currency"]) || "GBP",
      "debtor_iban" => nilify(params["debtor_iban"]) || SANDBOX_CREDITOR_IBAN,
      "creditor_iban" => nilify(params["creditor_iban"]) || SANDBOX_CREDITOR_IBAN,
      "creditor_name" => nilify(params["creditor_name"]) || SANDBOX_CREDITOR_NAME,
      "remittance" => nilify(params["remittance"]) || "navesti harness",
      "reference" => nilify(params["reference"]) || "navesti-#{SecureRandom.hex(4)}",
      "idempotency_key" => "webapp-#{SecureRandom.hex(6)}"
    }
  end

  # A numbered journey step: a royal-blue badge on a vertical rail (the
  # "user journey" spine), with the step body to the right.
  def step(number, title, hint = nil, body = "")
    hint_html = hint ? %(<p class="step__hint">#{h(hint)}</p>) : ""
    <<~HTML
      <section class="step">
        <div class="step__rail"><span class="step__badge">#{number}</span></div>
        <div class="step__body">
          <header class="step__head"><h2>#{h(title)}</h2>#{hint_html}</header>
          #{body}
        </div>
      </section>
    HTML
  end

  def config_status
    cert = ENV["REVOLUT_CLIENT_CERT_PATH"]
    rows = {
      "REVOLUT_ENV" => ENV["REVOLUT_ENV"] || "sandbox",
      "REVOLUT_LIVE" => live? ? "1 (live calls enabled)" : "unset (live calls refused)",
      "REVOLUT_DEBUG" => self.class.debug? ? "on (HTTP trace → terminal)" : "0 (silent)",
      "transport cert" => cert ? File.basename(cert) : "(REVOLUT_CLIENT_CERT_PATH not set)",
      "CA trust (server)" => server_ca_status,
      "signing key (OBSeal)" => base_env("REVOLUT_SIGNING_KEY_PATH"),
      "signing kid" => ENV["REVOLUT_SIGNING_KID"] || "(REVOLUT_SIGNING_KID not set)",
      "tan (JWKS host)" => ENV["REVOLUT_TAN"] || "(REVOLUT_TAN not set)",
      "client_id" => ENV["REVOLUT_CLIENT_ID"] || "(REVOLUT_CLIENT_ID not set)",
      "redirect_uri" => redirect_uri,
      "callback mode" => local_callback? ? "automatic (localhost bounce)" : "manual paste-back (off-host redirect)",
      "user token" => user_token ? "present (server-side, scope=#{STATE[:user_scope]})" : "none"
    }
    table = "<table class='kv'>" + rows.map { |k, v| "<tr><th>#{h(k)}</th><td>#{h(v)}</td></tr>" }.join + "</table>"
    <<~HTML
      <div class="card">#{table}</div>
      <div class="row">
        <button class="btn btn-primary" hx-post="/app-token" hx-vals='{"scope":"accounts"}'
          hx-target="#apptoken-result">Get app token (accounts)</button>
        <span class="muted step__hint" style="margin:0">client_credentials over mTLS — the cert/registration smoke test</span>
      </div>
      <div id="apptoken-result"></div>
    HTML
  end

  def base_env(key)
    path = ENV[key]
    path ? File.basename(path) : "(#{key} not set)"
  end

  def server_ca_status
    ca = ENV["REVOLUT_CA_CHAIN_PATH"]
    if ca && File.file?(ca)
      "#{File.basename(ca)} (OBIE root trusted)"
    elsif ca
      "(REVOLUT_CA_CHAIN_PATH set but file missing — server verify will fail)"
    else
      "system store only (OBIE server certs will fail to verify)"
    end
  end

  def auth_status
    if user_token
      %(<div id="auth-status">#{notice("Authorized (user token held server-side, scope=#{h(STATE[:user_scope])}).")}
        <div class="row">
          <button class="btn btn-blue" hx-post="/forget" hx-target="#auth-status" hx-swap="outerHTML">Forget user token</button>
        </div></div>)
    else
      %(<div id="auth-status">#{notice('No user token yet.', kind: 'warn')}
        <p>Revolut uses the OBIE <b>Hybrid Flow</b>: create a consent (step 2 for AIS, step 5a for PIS),
        then <b>Authorize</b> — you're redirected to Revolut, complete SCA, and land back here where the
        code is exchanged for a user token tied to that consent.</p></div>)
    end
  end

  def permissions_form
    perms = Navesti::Providers::Revolut::Dialect::DEFAULT_PERMISSIONS
    checks = perms.map do |p|
      %(<label class="field"><input type="checkbox" name="permissions[]" value="#{h(p)}" checked> #{h(p)}</label>)
    end.join
    <<~HTML
      <form class="pis-form" hx-post="/consents" hx-target="#consent-result">
        #{checks}
        <button class="btn btn-primary" type="submit">Create AIS consent</button>
      </form>
      <div id="consent-result"></div>
    HTML
  end

  def consent_panel(consent, flow:)
    target = local_callback? ? "" : ' target="_blank" rel="noopener"'
    authorize_btn = %(<a class="btn btn-primary" href="/oauth/start?flow=#{flow}"#{target}>Authorize #{flow} ↗</a>)
    after =
      if local_callback?
        "Complete SCA there; you'll return here automatically and the code is exchanged for a user token."
      else
        "Opens in a new tab. Complete SCA; your browser lands on " \
          "<code>#{h(URI.parse(redirect_uri).host)}</code> — copy that full URL and paste it into the " \
          "<b>Complete authorization</b> box in step 2."
      end
    <<~HTML
      #{notice("Consent created. consentId=#{h(consent.consent_id)} (held server-side, not shown again).", kind: "note")}
      <table class="kv">
        <tr><th>status</th><td>#{h(consent.status)} (#{h(consent.raw_status)})</td></tr>
        <tr><th>valid until</th><td>#{h(consent.valid_until)}</td></tr>
      </table>
      <p class="muted">Authorize redirects you to Revolut's UI. #{after} The signed Request Object pins this
      consentId (openbanking_intent_id).</p>
      <div class="row">#{authorize_btn}</div>
    HTML
  end

  # Manual paste-back for an off-host registered redirect_uri (the only path when
  # the client's registered URI isn't a localhost callback). Empty for the
  # automatic localhost flow. A plain POST (not htmx) so the returned full page
  # replaces this one. `flow` only labels the hint — the exchange keys off the
  # pending authorize state, not this box, so either box completes either flow.
  def manual_paste_box_for(flow)
    return "" if local_callback?

    host = (URI.parse(redirect_uri).host rescue redirect_uri)
    <<~HTML
      <form method="post" action="/oauth/paste" class="pis-form" style="margin-top:var(--s1)">
        <label class="field">After the <b>#{h(flow)}</b> SCA your browser lands on <code>#{h(host)}</code> with
          <code>?code=…&amp;state=…</code> in the address bar (never sent to that site). Paste the whole URL here:
          <input name="callback_url" size="58" placeholder="#{h(redirect_uri)}?code=...&amp;state=..."></label>
        <button class="btn btn-primary" type="submit">Complete authorization</button>
      </form>
    HTML
  end

  def accounts_table(accounts)
    return notice("No accounts returned.", kind: "warn") if accounts.empty?

    rows = accounts.map do |a|
      %(<tr><td><code>#{h(a.provider_account_id)}</code></td><td>#{h(a.iban)}</td>
        <td>#{h(a.owner_name)}</td><td>#{h(a.provider_reported_currency)}</td>
        <td>#{h(a.cash_account_type)}</td><td>#{h(a.status)}</td>
        <td><button class="btn btn-blue" hx-post="/balances" hx-target="#balances-result"
              hx-vals='#{h({ account_id: a.provider_account_id }.to_json)}'>Balances</button></td></tr>)
    end.join
    <<~HTML
      <table class="grid"><thead><tr><th>account id</th><th>IBAN</th><th>owner</th>
      <th>ccy</th><th>type</th><th>status</th><th></th></tr></thead><tbody>#{rows}</tbody></table>
      <div id="balances-result"></div>
    HTML
  end

  def balances_table(account_id, balances)
    return notice("No balances for #{h(account_id)}.", kind: "warn") if balances.empty?

    rows = balances.map do |b|
      %(<tr><td>#{h(b.currency)}</td><td>#{h(b.available_amount_minor.inspect)}</td>
        <td>#{h(b.booked_amount_minor.inspect)}</td><td>#{h(b.captured_at)}</td></tr>)
    end.join
    "<h4>Balances for <code>#{h(account_id)}</code> (minor units)</h4>" \
      "<table class='grid'><thead><tr><th>ccy</th><th>available</th><th>booked</th><th>captured_at</th></tr></thead>" \
      "<tbody>#{rows}</tbody></table>"
  end

  def pis_form
    <<~HTML
      <form class="pis-form" hx-post="/payments/consent" hx-target="#pis-result">
        <div class="field"><label>amount <input name="amount" value="1.00" size="8"></label>
          <label>ccy <input name="currency" value="GBP" size="5"></label></div>
        <label class="field">creditor IBAN <input name="creditor_iban" value="#{h(SANDBOX_CREDITOR_IBAN)}" size="30"></label>
        <label class="field">creditor name <input name="creditor_name" value="#{h(SANDBOX_CREDITOR_NAME)}" size="24"></label>
        <label class="field">reference <input name="reference" value="navesti-ref" size="20"></label>
        <label class="field">remittance <input name="remittance" value="navesti harness" size="28"></label>
        <button class="btn btn-primary" type="submit">Create payment consent</button>
      </form>
    HTML
  end

  def submission_panel(sub)
    <<~HTML
      #{notice("Submitted. domesticPaymentId=#{h(sub.provider_reference&.value)}", kind: "note")}
      <table class="kv">
        <tr><th>status</th><td>#{h(sub.status.status)} (#{h(sub.status.raw_status)})</td></tr>
        <tr><th>safety_status</th><td>#{h(sub.safety_status)}</td></tr>
        <tr><th>side_effect_possible</th><td>#{h(sub.side_effect_possible)}</td></tr>
      </table>
      <div class="row">
        <button class="btn btn-blue" hx-post="/payments/status" hx-target="#pis-status"
          hx-vals='#{h({ payment_id: sub.provider_reference&.value }.to_json)}'>Poll status</button>
      </div>
      <div id="pis-status"></div>
    HTML
  end

  def status_panel(payment_id, st)
    <<~HTML
      #{notice("domesticPaymentId=#{h(payment_id)}", kind: "note")}
      <table class="kv">
        <tr><th>status</th><td>#{h(st.status)} (#{h(st.raw_status)})</td></tr>
        <tr><th>safety_status</th><td>#{h(st.safety_status)}</td></tr>
        <tr><th>side_effect_possible</th><td>#{h(st.side_effect_possible)}</td></tr>
      </table>
    HTML
  end

  def home_body
    config = step(1, "Configure & get an app token",
                  "client_credentials over mTLS. A successful app token proves your transport cert and " \
                  "client registration work before any consent or signing is exercised.",
                  config_status)
    auth = step(2, "Authorize account access (AIS consent + Hybrid Flow)",
                "Create a signed account-access-consent, then Authorize — Revolut redirects the PSU for SCA " \
                "and returns a code, which we exchange for a user token bound to the consent.",
                permissions_form + auth_status + manual_paste_box_for(:accounts))
    ais = step(3, "Read accounts & balances (AIS)",
               "With the user token, list the PSU's accounts and fetch balances for one.",
               %(<div class="row">
                 <button class="btn btn-primary" hx-post="/accounts" hx-target="#accounts-result">List accounts</button>
               </div>
                 <div id="accounts-result"></div>))
    pis_body = <<~HTML
      <p class="muted"><b>5a.</b> Create a domestic-payment consent (signed). <b>5b.</b> Authorize it
      (Hybrid Flow, payments scope). <b>5c.</b> Submit the payment with the user token, then poll status.</p>
      <div class="pis-grid">
        <div>#{pis_form}</div>
        <div id="pis-result" class="pis-result-slot"></div>
      </div>
      #{manual_paste_box_for(:payments)}
      <div class="row" style="margin-top:var(--s1)">
        <button class="btn btn-primary" hx-post="/payments/submit" hx-target="#pis-submit">Submit payment (5c)</button>
        <span class="muted step__hint" style="margin:0">after authorizing the payment consent</span>
      </div>
      <div id="pis-submit"></div>
    HTML
    pis = step(4, "Initiate a domestic payment (PIS)", nil, pis_body)
    config + auth + ais + pis
  end

  # The Hybrid-Flow callback can't be read server-side (params are in the URL
  # fragment), so this page parses location.hash (or the query string as a
  # fallback) and re-POSTs the fields to /oauth/exchange. No secrets are logged
  # or persisted; the page just forwards the code to the server it came from.
  def callback_bounce
    <<~HTML
      <!doctype html><html><head><meta charset="utf-8"><title>Completing authorization…</title></head>
      <body style="font:1rem system-ui;margin:3rem auto;max-width:32rem;color:#16202e">
        <p>Completing authorization…</p>
        <noscript>JavaScript is required to complete the OBIE Hybrid Flow callback.</noscript>
        <form id="cb" method="post" action="/oauth/exchange"></form>
        <script>
          (function () {
            var raw = (location.hash && location.hash.length > 1) ? location.hash.substring(1) : location.search.substring(1);
            var p = new URLSearchParams(raw);
            var f = document.getElementById('cb');
            ['code', 'id_token', 'state', 'error', 'error_description'].forEach(function (k) {
              if (p.get(k)) {
                var i = document.createElement('input');
                i.type = 'hidden'; i.name = k; i.value = p.get(k);
                f.appendChild(i);
              }
            });
            f.submit();
          })();
        </script>
      </body></html>
    HTML
  end

  def layout(body)
    <<~HTML
      <!doctype html><html><head><meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>Navesti × Revolut sandbox harness</title>
      <script src="https://unpkg.com/htmx.org@1.9.12"></script>
      <style>
        :root{
          --phi:1.618;
          --s-2:.25rem; --s-1:.4rem; --s0:.65rem; --s1:1.06rem; --s2:1.71rem; --s3:2.76rem; --s4:4.47rem;
          --royal:#2548d9; --royal-deep:#1b3a9e; --royal-soft:#eef2fd; --royal-line:#c9d6f7;
          --green:#2f7d46; --green-deep:#1f5e33; --green-soft:#e9f5ee; --green-line:#bfe3c8;
          --amber:#9a6c16; --amber-soft:#fff6e5; --amber-line:#f0d8a8;
          --red:#b3261e; --red-soft:#fbe9e9; --red-line:#f0bcbc;
          --ink:#16202e; --muted:#647088; --line:#e3e8f0; --bg:#f5f7fc;
          --surface:#fff; --surface-2:#f9fafc;
          --fs-1:.875rem; --fs0:1rem; --fs1:1.18rem; --fs2:1.35rem; --fs3:1.9rem;
        }
        *{box-sizing:border-box}
        html{background:var(--bg)}
        body{font:var(--fs0)/1.6 system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;
          max-width:56rem;margin:0 auto;padding:var(--s3) var(--s2) var(--s4);color:var(--ink)}
        h1{font-size:var(--fs3);margin:0 0 var(--s-1);color:var(--royal-deep);letter-spacing:-.01em}
        h2{font-size:var(--fs2);margin:0}
        h4{font-size:var(--fs1);margin:var(--s1) 0 var(--s-1)}
        p{margin:var(--s0) 0}
        a{color:var(--royal)}

        .masthead{margin-bottom:var(--s3)}
        .masthead .lede{color:var(--muted);max-width:34.6rem;border-left:3px solid var(--royal-line);
          padding-left:var(--s0)}
        .legend{display:flex;gap:var(--s1);flex-wrap:wrap;margin-top:var(--s1)}
        .legend span{display:inline-flex;align-items:center;gap:.4rem;font-size:var(--fs-1);color:var(--muted)}
        .legend i{width:.7rem;height:.7rem;border-radius:50%;display:inline-block}

        .step{display:grid;grid-template-columns:2.5rem 1fr;margin-bottom:var(--s3)}
        .step__rail{position:relative;display:flex;justify-content:center}
        .step__badge{width:2rem;height:2rem;border-radius:50%;background:var(--royal);
          color:#fff;font-weight:600;font-size:.9rem;display:flex;align-items:center;justify-content:center;
          flex:none;z-index:1;box-shadow:0 0 0 4px var(--bg)}
        .step__rail::after{content:"";position:absolute;top:2rem;left:50%;width:2px;
          height:calc(100% + var(--s3));background:var(--royal-line);transform:translateX(-50%)}
        .step:last-of-type .step__rail::after{display:none}
        .step__body{padding-bottom:var(--s2)}
        .step__head{margin-bottom:var(--s1)}
        .step__hint{margin:.15rem 0 0;color:var(--muted);font-size:var(--fs-1)}

        .card{background:var(--surface);border:1px solid var(--line);border-radius:10px;padding:var(--s1)}
        .row{display:flex;gap:var(--s0);flex-wrap:wrap;align-items:center;margin:var(--s0) 0}
        .muted{color:var(--muted)}
        code{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;background:var(--surface-2);
          padding:.04rem .32rem;border-radius:4px;font-size:.85em;border:1px solid var(--line)}

        button,.btn{font:inherit;font-size:var(--fs-1);padding:var(--s-1) var(--s0);border:1px solid transparent;
          border-radius:8px;cursor:pointer;text-decoration:none;display:inline-flex;align-items:center;
          gap:.4rem;line-height:1.3;color:#1a1a1a}
        .btn-primary{background:var(--green);color:#fff;border-color:var(--green)}
        .btn-primary:hover{background:var(--green-deep)}
        .btn-blue{background:var(--royal-soft);color:var(--royal-deep);border-color:var(--royal-line)}
        .btn-blue:hover{background:#e1e9fb}
        .btn-danger{background:var(--surface);color:var(--red);border-color:var(--red-line)}
        .btn-danger:hover{background:var(--red-soft)}

        .notice{padding:var(--s0) var(--s1);border-radius:8px;margin:0 0 var(--s1);font-size:var(--fs-1);
          border:1px solid var(--line);background:var(--surface)}
        .note{background:var(--royal-soft);border-color:var(--royal-line);color:var(--royal-deep)}
        .ok{background:var(--green-soft);border-color:var(--green-line);color:var(--green-deep)}
        .warn{background:var(--amber-soft);border-color:var(--amber-line);color:var(--amber)}
        .err{background:var(--red-soft);border-color:var(--red-line);color:var(--red)}

        label{display:inline-block;margin-right:var(--s1);margin-bottom:var(--s0);
          font-size:var(--fs-1);color:var(--muted)}
        label>input{margin-left:.35rem}
        .field{display:block;margin-bottom:var(--s0)}
        input{font:inherit;font-size:var(--fs-1);padding:.3rem .45rem;border:1px solid var(--line);
          border-radius:6px;background:var(--surface);color:var(--ink)}
        input:focus{outline:2px solid var(--royal-line);border-color:var(--royal)}

        table{border-collapse:collapse;margin:var(--s0) 0}
        .kv th{text-align:left;padding:.2rem .7rem .2rem 0;color:var(--muted);font-weight:600;vertical-align:top;white-space:nowrap}
        .kv td{padding:.2rem 0}
        .grid{width:100%}
        .grid th,.grid td{border:1px solid var(--line);padding:.35rem .55rem;text-align:left}
        .grid th{background:var(--surface-2);color:var(--royal-deep);font-weight:600;font-size:var(--fs-1)}
        .grid tbody tr:nth-child(even){background:var(--surface-2)}

        .pis-grid{display:grid;grid-template-columns:1.618fr 1fr;gap:var(--s2);align-items:start}
        .pis-form{display:flex;flex-direction:column;gap:.1rem}
        .pis-result-slot{min-height:2rem}

        footer{margin-top:var(--s3);padding-top:var(--s1);border-top:1px solid var(--line);
          color:var(--muted);font-size:var(--fs-1)}

        @media(max-width:42rem){
          .pis-grid{grid-template-columns:1fr}
          .step{grid-template-columns:2rem 1fr}
        }
      </style></head><body>
      <header class="masthead">
        <h1>Navesti × Revolut sandbox</h1>
        <p class="lede">A click-through journey for the Revolut (UK OBIE) connector: get an app token, create a
        signed consent, complete the Hybrid-Flow authorization, read accounts, and initiate a domestic payment —
        all against the sandbox. Navesti stays headless; this app renders the UX (the Cockpit's role). Sandbox-only —
        live calls need <code>REVOLUT_LIVE=1</code>; tokens stay server-side and are never shown.</p>
        <div class="legend">
          <span><i style="background:var(--royal)"></i> note</span>
          <span><i style="background:var(--green)"></i> success</span>
          <span><i style="background:var(--amber-line)"></i> warn</span>
          <span><i style="background:var(--red)"></i> error</span>
        </div>
      </header>
      #{body}
      <footer>Developer tool — single-user, localhost, no persistence. Don't expose it.</footer>
      </body></html>
    HTML
  end
end
