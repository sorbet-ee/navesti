# frozen_string_literal: true

# Navesti × LHV sandbox connectivity harness.
#
# A tiny Roda + htmx app that drives the Navesti LHV adapter against the real
# sandbox, so you can exercise the whole journey in a browser instead of curl.
#
# THIS IS DEVELOPER TOOLING — a separate consumer of the gem, playing the role
# Sorbet-Cockpit will: it renders UX and opens bank URLs; Navesti returns
# normalized facts and interaction descriptors. The gem stays headless.
#
# Boundaries (mirroring CLAUDE.md / the browser harness):
#   - sandbox-only; live calls refuse unless LHV_LIVE=1
#   - tokens live in server-side memory only — never in a cookie, never rendered
#   - all bank/user data is HTML-escaped; errors are already redaction-safe
#   - single-user localhost dev tool (global in-memory state, no sessions)

require "navesti"
require "roda"
require "securerandom"
require "cgi"
require "date"

# A redaction-safe HTTP trace for the terminal. Wraps the gem's real client so
# we can see exactly what went to LHV and what came back — which headers were
# present (Consent-ID? PSU-Corporate-ID?), the status, and the raw error body
# LHV returned (e.g. the full tppMessages behind a FORMAT_ERROR). Every line is
# scrubbed through Navesti::Redaction (Bearer tokens, PEM, secret fields) before
# it is printed, and the Authorization value is masked outright. DEVELOPER
# TOOLING ONLY — the gem itself never logs (its HTTP client is silent by design).
#
# Enabled by default for the harness; set LHV_DEBUG=0 to silence it.
class DebugHTTP
  BODY_LIMIT = 1200
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

  # Surfaces LHV's own error codes plainly. The scrubbed body line masks the
  # `code` value (Redaction guards OAuth authorization codes by that key), but a
  # tppMessages error code (FORMAT_ERROR, CONSENT_INVALID, …) is not a secret and
  # is the single most useful thing to see — so pull it from the parsed JSON and
  # print it. The accompanying text is still scrubbed for Bearer/PEM material.
  def error_summary(seq, response)
    body = response.json_or_nil
    return unless body.is_a?(Hash)

    messages = body["tppMessages"]
    return unless messages.is_a?(Array) && messages.any?

    messages.each do |m|
      next unless m.is_a?(Hash)

      label = [m["code"], m["category"]].compact.join(" / ")
      text = m["text"] || m["path"]
      log(seq, "  lhv error: #{label}#{text ? " — #{scrub(text.to_s)}" : ''}")
    end
  end

  # Show every header so it's obvious which were sent (Consent-ID presence is the
  # whole point when diagnosing FORMAT_ERROR), but never reveal the bearer token.
  def header_summary(headers)
    return "(none)" if headers.nil? || headers.empty?

    pairs = headers.map do |k, v|
      value = k.to_s.casecmp("authorization").zero? ? "Bearer [REDACTED]" : v
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
  # flush immediately, so the trace shows up live alongside the request log
  # instead of being buffered or routed to a handler's own stderr logger.
  def log(seq, message)
    $stdout.puts "[lhv ##{seq}] #{message}"
    $stdout.flush
  end
end

class NavestiLhvHarness < Roda
  # Single-user, in-memory dev state. Tokens stay in this process and are never
  # serialized to a cookie or rendered to the page.
  STATE = { token: nil, corporate_id: nil, oauth_state: nil, accounts: [], last_payment_id: nil, consent_id: nil }

  # Documented LHV sandbox test data (public — not secrets). Prefilled in the
  # form so connectivity can be tried with one click.
  SANDBOX_PSU = "Liis-MariMnnik"
  SANDBOX_CORPORATE_ID = "EE47101010033"

  # Fragments are built as plain strings (htmx swaps HTML), so no render/asset
  # plugins are needed — keeps the harness tiny.

  # --- helpers ---------------------------------------------------------------

  def self.adapter
    Navesti.adapter(
      :lhv,
      credentials: Navesti::Credentials.from_env,
      env: (ENV["LHV_ENV"] || "sandbox").to_sym,
      http: debug? ? DebugHTTP.new : Navesti::HTTP::Client.new
    )
  end

  # Terminal HTTP trace is on by default for this dev harness; LHV_DEBUG=0 mutes.
  def self.debug? = ENV["LHV_DEBUG"] != "0"

  def live? = ENV["LHV_LIVE"] == "1"

  def redirect_uri
    ENV["LHV_WEBAPP_REDIRECT_URI"] || "http://localhost:9292/oauth/callback"
  end

  # Where LHV sends the PSU after completing the consent SCA. Separate from the
  # OAuth callback (which expects an authorization code) — the consent redirect
  # carries no code; it just signals "done, poll status".
  def consent_redirect_uri
    ENV["LHV_WEBAPP_CONSENT_REDIRECT_URI"] || "http://localhost:9292/consent-callback"
  end

  def token
    STATE[:token]
  end

  def consent_id
    STATE[:consent_id]
  end

  def h(value)
    CGI.escapeHTML(value.to_s)
  end

  # Runs an adapter call, rendering an error fragment on any Navesti error.
  def guarded
    return warn_offline unless live?

    yield
  rescue Navesti::ConsentError => e
    # 401 — most commonly the preset token not matching our TPP. Point to OAuth.
    err("#{e.message}. Preset sandbox tokens are bound to LHV's built-in Swagger " \
        "certificate, so they return TOKEN_UNKNOWN for your own TPP. Authenticate " \
        "with 'Start OAuth' above to get a token tied to your certificate.")
  rescue Navesti::Error => e
    err(e.message) # already redaction-safe via Navesti::Error
  end

  def warn_offline
    notice("Refusing live LHV call. Start the server with LHV_LIVE=1.", kind: "warn")
  end

  def notice(msg, kind: "ok")
    %(<div class="notice #{kind}">#{h(msg)}</div>)
  end

  def err(msg)
    notice("Error: #{msg}", kind: "err")
  end

  # --- routes ----------------------------------------------------------------

  route do |r|
    r.root { layout(home_body) }

    # AIS: TPP verification
    r.post "tpp" do
      guarded do
        v = self.class.adapter.tpp_verification
        <<~HTML
          #{notice("access=#{v.access}  tpp_id=#{h(v.tpp_id)}  roles=#{h(v.roles.join(', '))}",
                   kind: v.enabled? ? 'ok' : 'warn')}
        HTML
      end
    end

    # Auth: use the prefilled sandbox PSU (bearer token), no OAuth dance
    r.post "use-preset" do
      STATE[:token] = nilify(r.params["preset"]) || SANDBOX_PSU
      STATE[:corporate_id] = nilify(r.params["corporate_id"])
      auth_status
    end

    r.post "forget-token" do
      STATE[:token] = nil
      auth_status
    end

    # OAuth (redirect) — start + callback
    r.on "oauth" do
      r.get "start" do
        STATE[:oauth_state] = "navesti-#{SecureRandom.hex(8)}"
        interaction = self.class.adapter.authorize_url(redirect_uri: redirect_uri, state: STATE[:oauth_state])
        r.redirect interaction.url
      end

      r.get "callback" do
        if r.params["state"] != STATE[:oauth_state]
          next layout(notice("OAuth state mismatch — aborted.", kind: "err"))
        end
        if r.params["code"].to_s.empty?
          next layout(notice("No authorization code returned.", kind: "err"))
        end

        begin
          tok = self.class.adapter.exchange_code(code: r.params["code"], redirect_uri: redirect_uri)
          STATE[:token] = tok.access_token
          layout(notice("Authenticated. token_type=#{h(tok.token_type)} scope=#{h(tok.scope)} " \
                        "expires_in=#{h(tok.expires_in)}s") + home_body)
        rescue Navesti::Error => e
          layout(notice("Token exchange failed: #{e.message}", kind: "err"))
        end
      end
    end

    # AIS: create consent + poll its status
    r.post "consents" do
      guarded do
        next err("No access token — authenticate first.") unless token

        valid_until = nilify(r.params["valid_until"]) || (Date.today + 90).iso8601
        recurring = r.params["recurring"] == "1"
        consent = self.class.adapter.create_consent(
          access_token: token, valid_until: valid_until, redirect_uri: consent_redirect_uri,
          recurring_indicator: recurring, psu_corporate_id: STATE[:corporate_id]
        )
        STATE[:consent_id] = consent.consent_id
        consent_panel(consent)
      end
    end

    r.post "consents/status" do
      guarded do
        next err("No access token.") unless token
        cid = nilify(r.params["consent_id"]) || STATE[:consent_id]
        next err("No consent id — create a consent first (step 3).") unless cid

        consent = self.class.adapter.consent_status(consent_id: cid, access_token: token)
        consent_status_panel(consent)
      end
    end

    r.get "consent-callback" do
      layout(notice("Consent SCA complete. Go back and poll consent status (step 3).", kind: "note") + home_body)
    end

    # AIS: accounts
    r.post "accounts" do
      guarded do
        next err("No access token — authenticate or use a preset token first.") unless token

        with_consent = r.params["with_consent"] == "1"
        used_consent_id = with_consent ? STATE[:consent_id] : nil
        if with_consent && used_consent_id.nil?
          next err("No consent_id — create a consent first (step 3) and poll until valid.")
        end

        STATE[:accounts] = self.class.adapter.accounts_list(
          access_token: token, psu_corporate_id: STATE[:corporate_id], consent_id: used_consent_id
        )
        accounts_table(STATE[:accounts], consent_id: used_consent_id)
      end
    end

    # AIS: balances for an account
    r.post "balances" do
      guarded do
        next err("No access token.") unless token

        account_id = r.params["account_id"].to_s
        next err("Pick an account.") if account_id.empty?

        balances = self.class.adapter.balances(
          access_token: token, account_id: account_id,
          balances_href: nilify(r.params["balances_href"]),
          consent_id: nilify(r.params["consent_id"]),
          psu_corporate_id: STATE[:corporate_id]
        )
        balances_table(account_id, balances)
      end
    end

    # PIS: initiate SEPA payment
    r.post "payments" do
      r.post "init" do
        guarded do
          next err("No access token.") unless token

          order = build_order(r.params)
          sub = self.class.adapter.initiate_sepa_payment(
            order: order, access_token: token, redirect_uri: redirect_uri,
            psu_corporate_id: STATE[:corporate_id]
          )
          STATE[:last_payment_id] = sub.provider_reference&.value
          submission_panel(sub)
        end
      end

      r.post "status" do
        guarded do
          next err("No access token.") unless token

          pid = nilify(r.params["payment_id"]) || STATE[:last_payment_id]
          next err("No payment id.") unless pid

          st = self.class.adapter.payment_status(payment_id: pid, access_token: token)
          status_panel(pid, st)
        end
      end

      r.post "cancel" do
        guarded do
          next err("No access token.") unless token

          pid = nilify(r.params["payment_id"]) || STATE[:last_payment_id]
          next err("No payment id.") unless pid

          st = self.class.adapter.cancel_payment(payment_id: pid, access_token: token)
          status_panel(pid, st)
        end
      end
    end

    # OAuth: revoke current token
    r.post "revoke" do
      guarded do
        next err("No token to revoke.") unless token

        self.class.adapter.revoke_token(token: token, token_type_hint: "access_token")
        STATE[:token] = nil
        notice("Token revoked.", kind: "note")
      end
    end
  end

  # --- view fragments --------------------------------------------------------

  def nilify(value)
    s = value.to_s.strip
    s.empty? ? nil : s
  end

  def build_order(params)
    Navesti::PaymentOrder.new(
      money: Navesti::Money.from_decimal(nilify(params["amount"]) || "1.00", nilify(params["currency"]) || "EUR"),
      debtor: Navesti::AccountRef.iban(nilify(params["debtor_iban"]) || "EE717700771001735865"),
      creditor: Navesti::AccountRef.iban(nilify(params["creditor_iban"]) || "EE857700771001735904"),
      creditor_name: nilify(params["creditor_name"]) || "Donald Duck",
      remittance_information: nilify(params["remittance"]) || "navesti harness",
      idempotency_key: "webapp-#{SecureRandom.hex(6)}"
    )
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
    cert = ENV["LHV_CLIENT_CERT_PATH"]
    tpp =
      begin
        cert ? Navesti::Security::CertificateIdentity.extract_tpp_id(cert) : "(no cert)"
      rescue Navesti::Error => e
        "(#{e.message})"
      end
    rows = {
      "LHV_ENV" => ENV["LHV_ENV"] || "sandbox",
      "LHV_LIVE" => live? ? "1 (live calls enabled)" : "unset (live calls refused)",
      "LHV_DEBUG" => self.class.debug? ? "on (HTTP trace → terminal)" : "0 (silent)",
      "client cert" => cert ? File.basename(cert) : "(LHV_CLIENT_CERT_PATH not set)",
      "TPP id (from cert)" => tpp,
      "redirect_uri" => redirect_uri,
      "token" => token ? "present (server-side, not shown)" : "none",
      "consent_id" => consent_id ? "present (server-side)" : "none"
    }
    table = "<table class='kv'>" + rows.map { |k, v| "<tr><th>#{h(k)}</th><td>#{h(v)}</td></tr>" }.join + "</table>"
    <<~HTML
      <div class="card">#{table}</div>
      <div class="row">
        <button class="btn btn-primary" hx-post="/tpp" hx-target="#tpp-result">Verify TPP</button>
        <span class="muted step__hint" style="margin:0">mTLS smoke test</span>
      </div>
      <div id="tpp-result"></div>
    HTML
  end

  def auth_status
    if token
      %(<div id="auth-status">#{notice('Authenticated (token held server-side, never shown).')}
        <div class="row">
          <button class="btn btn-danger" hx-post="/revoke" hx-target="#pis-result">Revoke token</button>
          <button class="btn btn-blue" hx-post="/forget-token" hx-target="#auth-status" hx-swap="outerHTML">Forget token</button>
        </div></div>)
    else
      %(<div id="auth-status">#{notice('Not authenticated.', kind: 'warn')}
        <p><b>With your own TPP certificate, authenticate via OAuth.</b> At LHV's login use the
        PSU <code>#{h(SANDBOX_PSU)}</code> and the sandbox PIN calculator (any 4 digits, e.g. 0000).</p>
        <div class="row"><a class="btn btn-primary" href="/oauth/start">Start OAuth ↗</a></div>
        <details class="disclosure"><summary class="muted">…or use a preset bearer token (only works with LHV's built-in Swagger certificate — returns TOKEN_UNKNOWN for your own TPP)</summary>
          <form hx-post="/use-preset" hx-target="#auth-status" hx-swap="outerHTML" style="margin-top:.6rem">
            <label>PSU bearer <input name="preset" value="#{h(SANDBOX_PSU)}" size="16"></label>
            <label>PSU-Corporate-ID <input name="corporate_id" value="#{h(SANDBOX_CORPORATE_ID)}" size="15"></label>
            <button class="btn btn-blue" type="submit">Use preset</button>
          </form>
        </details></div>)
    end
  end

  # The bank's own balances href for an account, carried in its raw evidence
  # (accounts-list _links.balances.href). Preferred over building the path from
  # provider_account_id — the no-consent basic list has no resourceId, so the
  # bank's link is the only correct URL to Read Balances in that case. nil when
  # the account carries no balances link.
  def balances_href(account)
    account.raw&.dig(:account, "_links", "balances", "href")
  end

  def accounts_table(accounts, consent_id: nil)
    return notice("No accounts returned.", kind: "warn") if accounts.empty?

    rows = accounts.map do |a|
      vals = { "account_id" => a.provider_account_id }
      vals["balances_href"] = balances_href(a) if balances_href(a)
      vals["consent_id"] = consent_id if consent_id
      %(<tr><td><code>#{h(a.provider_account_id)}</code></td><td>#{h(a.iban)}</td>
        <td>#{h(a.owner_name)}</td><td>#{h(a.provider_reported_currency)}</td>
        <td>#{h(a.cash_account_type)}</td><td>#{h(a.status)}</td>
        <td><button class="btn btn-blue" hx-post="/balances" hx-target="#balances-result"
              hx-vals='#{h(vals.to_json)}'>Balances</button></td></tr>)
    end.join
    <<~HTML
      <table class="grid"><thead><tr><th>account id</th><th>IBAN</th><th>owner</th>
      <th>ccy</th><th>type</th><th>status</th><th></th></tr></thead><tbody>#{rows}</tbody></table>
      <div id="balances-result"></div>
    HTML
  end

  def balances_table(account_id, balances)
    return notice("No balances for #{h(account_id)} (consent-gated — may need a Consent-ID).", kind: "warn") if balances.empty?

    rows = balances.map do |b|
      %(<tr><td>#{h(b.currency)}</td><td>#{h(b.available_amount_minor.inspect)}</td>
        <td>#{h(b.booked_amount_minor.inspect)}</td><td>#{h(b.captured_at)}</td></tr>)
    end.join
    "<h4>Balances for <code>#{h(account_id)}</code> (minor units)</h4>" \
      "<table class='grid'><thead><tr><th>ccy</th><th>available</th><th>booked</th><th>captured_at</th></tr></thead>" \
      "<tbody>#{rows}</tbody></table>"
  end

  def submission_panel(sub)
    sca = sub.interaction&.url
    sca_html =
      if sca
        https = sca.start_with?("https://")
        link = https ? %(<a class="btn btn-primary" href="#{h(sca)}" target="_blank" rel="noopener">Open SCA redirect ↗</a>) : ""
        %(<p><b>scaRedirect:</b> <code>#{h(sca)}</code></p>
          <div class="row">#{link}</div>
          <p class="muted">Complete SCA in the bank UI (sandbox PIN calculator, e.g. 0000), then poll status.</p>)
      else
        %(<p class="muted">No scaRedirect — SCA exemption likely (already #{h(sub.status.status)}).</p>)
      end
    methods = sub.sca_method_ids.empty? ? "—" : h(sub.sca_method_ids.join(", "))
    <<~HTML
      #{notice("Submitted. paymentId=#{h(sub.provider_reference&.value)}", kind: "note")}
      <table class="kv">
        <tr><th>status</th><td>#{h(sub.status.status)} (#{h(sub.status.raw_status)})</td></tr>
        <tr><th>safety_status</th><td>#{h(sub.safety_status)}</td></tr>
        <tr><th>side_effect_possible</th><td>#{h(sub.side_effect_possible)}</td></tr>
        <tr><th>decoupled SCA methods</th><td>#{methods}</td></tr>
      </table>
      #{sca_html}
      <div class="row">
        <button class="btn btn-blue" hx-post="/payments/status" hx-target="#pis-status"
          hx-vals='{"payment_id":"#{h(sub.provider_reference&.value)}"}'>Poll status</button>
        <button class="btn btn-danger" hx-post="/payments/cancel" hx-target="#pis-status"
          hx-vals='{"payment_id":"#{h(sub.provider_reference&.value)}"}'>Cancel (pre-SCA)</button>
      </div>
      <div id="pis-status"></div>
    HTML
  end

  def status_panel(payment_id, st)
    <<~HTML
      #{notice("paymentId=#{h(payment_id)}", kind: "note")}
      <table class="kv">
        <tr><th>status</th><td>#{h(st.status)} (#{h(st.raw_status)})</td></tr>
        <tr><th>safety_status</th><td>#{h(st.safety_status)}</td></tr>
        <tr><th>side_effect_possible</th><td>#{h(st.side_effect_possible)}</td></tr>
      </table>
    HTML
  end

  # AIS consent form: a near-future validUntil (default 90 days out) + a
  # recurring-access checkbox (off = short-term access). valid_until is computed
  # here in the harness, never in the gem (the gem stays deterministic).
  def consent_form
    default_valid_until = (Date.today + 90).iso8601
    <<~HTML
      <form class="pis-form" hx-post="/consents" hx-target="#consent-result">
        <label class="field">valid until <input name="valid_until" value="#{h(default_valid_until)}" size="12"></label>
        <label class="field"><input type="checkbox" name="recurring" value="1"> recurring access</label>
        <button class="btn btn-primary" type="submit">Create consent</button>
      </form>
      <div id="consent-result"></div>
    HTML
  end

  def consent_panel(consent)
    sca = consent.interaction&.url
    sca_html =
      if sca
        https = sca.start_with?("https://")
        link = https ? %(<a class="btn btn-primary" href="#{h(sca)}" target="_blank" rel="noopener">Open consent SCA ↗</a>) : ""
        %(<p><b>scaRedirect:</b> <code>#{h(sca)}</code></p>
          <div class="row">#{link}</div>
          <p class="muted">Complete SCA in the bank UI (sandbox PIN calculator, e.g. 0000),
          then poll consent status until it reads <code>valid</code>.</p>)
      else
        %(<p class="muted">No scaRedirect — the consent may already be in a terminal state.</p>)
      end
    methods = consent.sca_methods.empty? ? "—" : h(consent.sca_methods.map(&:method_id).join(", "))
    <<~HTML
      #{notice("Consent created. consentId=#{h(consent.consent_id)} (held server-side, not shown again).", kind: "note")}
      <table class="kv">
        <tr><th>status</th><td>#{h(consent.status)} (#{h(consent.raw_status)})</td></tr>
        <tr><th>valid until</th><td>#{h(consent.valid_until)}</td></tr>
        <tr><th>recurring</th><td>#{h(consent.recurring_indicator)}</td></tr>
        <tr><th>SCA methods</th><td>#{methods}</td></tr>
      </table>
      #{sca_html}
      <div class="row">
        <button class="btn btn-blue" hx-post="/consents/status" hx-target="#consent-status"
          hx-vals='{"consent_id":"#{h(consent.consent_id)}"}'>Poll consent status</button>
      </div>
      <div id="consent-status"></div>
    HTML
  end

  def consent_status_panel(consent)
    valid = consent.status == :valid
    list_btn = if valid
                 %(<div class="row">
                    <button class="btn btn-primary" hx-post="/accounts" hx-target="#accounts-result"
                      hx-vals='{"with_consent":"1"}'>List accounts (with consent)</button>
                  </div>)
               else
                 ""
               end
    <<~HTML
      #{notice("consentId=#{h(consent.consent_id)}  status=#{h(consent.status)} (#{h(consent.raw_status)})",
               kind: valid ? "ok" : "note")}
      <table class="kv">
        <tr><th>status</th><td>#{h(consent.status)} (#{h(consent.raw_status)})</td></tr>
      </table>
      #{"<p>Consent valid — list accounts with consent, then Balances resolves to the real resourceId.</p>" if valid}
      #{list_btn}
    HTML
  end

  def pis_form
    <<~HTML
      <form class="pis-form" hx-post="/payments/init" hx-target="#pis-result">
        <div class="field"><label>amount <input name="amount" value="1.00" size="8"></label>
          <label>ccy <input name="currency" value="EUR" size="5"></label></div>
        <label class="field">debtor IBAN <input name="debtor_iban" value="EE717700771001735865" size="28"></label>
        <label class="field">creditor IBAN <input name="creditor_iban" value="EE857700771001735904" size="28"></label>
        <label class="field">creditor name <input name="creditor_name" value="Donald Duck" size="20"></label>
        <label class="field">remittance <input name="remittance" value="navesti harness" size="28"></label>
        <button class="btn btn-primary" type="submit">Initiate payment</button>
      </form>
    HTML
  end

  def home_body
    config = step(1, "Configure & verify your TPP",
                  "The mTLS smoke test. Your client certificate identifies you to LHV before anything else.",
                  config_status)
    auth = step(2, "Authenticate",
                "OAuth redirects you to LHV's login; you come back with a token tied to your certificate.",
                auth_status)
    consent = step(3, "Authorize account access (AIS consent)",
                   "Create an AIS consent so the PSU grants balance access. The PSU completes SCA on LHV's page; " \
                   "the consent moves received → valid. Without a valid consent, Balances fails (FORMAT_ERROR).",
                   consent_form)
    ais = step(4, "Read accounts & balances (AIS)",
               "List the PSU's accounts, then fetch balances for one. The no-consent list has no resourceId; " \
               "with a valid consent (step 3) you get the real resourceId that Balances needs.",
               %(<div class="row">
                 <button class="btn btn-primary" hx-post="/accounts" hx-target="#accounts-result">List accounts</button>
                 <button class="btn btn-blue" hx-post="/accounts" hx-target="#accounts-result"
                   hx-vals='{"with_consent":"1"}'>List accounts (with consent)</button>
               </div>
                 <div id="accounts-result"></div>))
    pis_body = <<~HTML
      <div class="pis-grid">
        <div>#{pis_form}</div>
        <div id="pis-result" class="pis-result-slot"></div>
      </div>
    HTML
    pis = step(5, "Initiate a SEPA payment (PIS)",
               "Create the payment, complete SCA on LHV's page, then poll status or cancel (pre-SCA).",
               pis_body)
    config + auth + consent + ais + pis
  end

  def layout(body)
    <<~HTML
      <!doctype html><html><head><meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>Navesti × LHV sandbox harness</title>
      <script src="https://unpkg.com/htmx.org@1.9.12"></script>
      <style>
        :root{
          --phi:1.618;
          /* golden-ratio spacing scale: each step ~φ× the previous */
          --s-2:.25rem; --s-1:.4rem; --s0:.65rem; --s1:1.06rem; --s2:1.71rem; --s3:2.76rem; --s4:4.47rem;
          /* royal blue — notes, journey spine, secondary actions */
          --royal:#2548d9; --royal-deep:#1b3a9e; --royal-soft:#eef2fd; --royal-line:#c9d6f7;
          /* forest green — success, primary "go" actions */
          --green:#2f7d46; --green-deep:#1f5e33; --green-soft:#e9f5ee; --green-line:#bfe3c8;
          /* amber / red */
          --amber:#9a6c16; --amber-soft:#fff6e5; --amber-line:#f0d8a8;
          --red:#b3261e; --red-soft:#fbe9e9; --red-line:#f0bcbc;
          /* neutrals */
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

        /* numbered journey: royal-blue badges on a connecting rail */
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

        /* buttons: forest-green primary (advance the journey), royal-blue secondary, red danger */
        button,.btn{font:inherit;font-size:var(--fs-1);padding:var(--s-1) var(--s0);border:1px solid transparent;
          border-radius:8px;cursor:pointer;text-decoration:none;display:inline-flex;align-items:center;
          gap:.4rem;line-height:1.3;color:#1a1a1a}
        .btn-primary{background:var(--green);color:#fff;border-color:var(--green)}
        .btn-primary:hover{background:var(--green-deep)}
        .btn-blue{background:var(--royal-soft);color:var(--royal-deep);border-color:var(--royal-line)}
        .btn-blue:hover{background:#e1e9fb}
        .btn-danger{background:var(--surface);color:var(--red);border-color:var(--red-line)}
        .btn-danger:hover{background:var(--red-soft)}

        /* notices: royal-blue notes, forest-green success, amber warn, red error */
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
        .disclosure{margin-top:var(--s0);padding:var(--s0) var(--s1);border:1px solid var(--line);
          border-radius:8px;background:var(--surface-2)}
        .disclosure summary{cursor:pointer;color:var(--muted)}

        table{border-collapse:collapse;margin:var(--s0) 0}
        .kv th{text-align:left;padding:.2rem .7rem .2rem 0;color:var(--muted);font-weight:600;vertical-align:top;white-space:nowrap}
        .kv td{padding:.2rem 0}
        .grid{width:100%}
        .grid th,.grid td{border:1px solid var(--line);padding:.35rem .55rem;text-align:left}
        .grid th{background:var(--surface-2);color:var(--royal-deep);font-weight:600;font-size:var(--fs-1)}
        .grid tbody tr:nth-child(even){background:var(--surface-2)}

        /* PIS: golden-ratio split — form (φ) : live result (1) */
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
        <h1>Navesti × LHV sandbox</h1>
        <p class="lede">A click-through journey for the LHV connector: verify your TPP, authenticate, read
        accounts, and initiate a SEPA payment — all against the sandbox. Navesti stays headless; this app
        renders the UX (the Cockpit's role). Sandbox-only — live calls need <code>LHV_LIVE=1</code>;
        tokens stay server-side and are never shown.</p>
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