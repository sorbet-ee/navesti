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

class NavestiLhvHarness < Roda
  # Single-user, in-memory dev state. Tokens stay in this process and are never
  # serialized to a cookie or rendered to the page.
  STATE = { token: nil, corporate_id: nil, oauth_state: nil, accounts: [], last_payment_id: nil }

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
      env: (ENV["LHV_ENV"] || "sandbox").to_sym
    )
  end

  def live? = ENV["LHV_LIVE"] == "1"

  def redirect_uri
    ENV["LHV_WEBAPP_REDIRECT_URI"] || "http://localhost:9292/oauth/callback"
  end

  def token
    STATE[:token]
  end

  def h(value)
    CGI.escapeHTML(value.to_s)
  end

  # Runs an adapter call, rendering an error fragment on any Navesti error.
  def guarded
    return warn_offline unless live?

    yield
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

    # AIS: accounts
    r.post "accounts" do
      guarded do
        next err("No access token — authenticate or use a preset token first.") unless token

        STATE[:accounts] = self.class.adapter.accounts_list(
          access_token: token, psu_corporate_id: STATE[:corporate_id]
        )
        accounts_table(STATE[:accounts])
      end
    end

    # AIS: balances for an account
    r.post "balances" do
      guarded do
        next err("No access token.") unless token

        account_id = r.params["account_id"].to_s
        next err("Pick an account.") if account_id.empty?

        balances = self.class.adapter.balances(
          access_token: token, account_id: account_id, consent_id: nilify(r.params["consent_id"])
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
        notice("Token revoked.")
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
      "client cert" => cert ? File.basename(cert) : "(LHV_CLIENT_CERT_PATH not set)",
      "TPP id (from cert)" => tpp,
      "redirect_uri" => redirect_uri,
      "token" => token ? "present (server-side, not shown)" : "none"
    }
    "<table class='kv'>" + rows.map { |k, v| "<tr><th>#{h(k)}</th><td>#{h(v)}</td></tr>" }.join + "</table>"
  end

  def auth_status
    if token
      %(<div id="auth-status">#{notice('Authenticated (token held server-side, never shown).')}
        <button hx-post="/revoke" hx-target="#pis-result">Revoke token</button>
        <button hx-post="/forget-token" hx-target="#auth-status" hx-swap="outerHTML">Forget token</button></div>)
    else
      %(<div id="auth-status">#{notice('Not authenticated — sandbox PSU prefilled below.', kind: 'warn')}
        <form hx-post="/use-preset" hx-target="#auth-status" hx-swap="outerHTML">
          <label>PSU username <input name="preset" value="#{h(SANDBOX_PSU)}" size="16"></label>
          <label>PSU-Corporate-ID <input name="corporate_id" value="#{h(SANDBOX_CORPORATE_ID)}" size="15"></label>
          <label title="Entered on LHV's own login page (sandbox PIN calculator) — never sent by this app.">
            SCA PIN <input name="pin" value="0000" size="6" readonly></label>
          <button type="submit">Use sandbox PSU</button>
        </form>
        <p class="muted">The sandbox PSU bearer is documented public test data. There is no API password:
        real login/SCA happens on LHV's page, and the sandbox uses the PIN calculator (any 4 digits).</p>
        <a class="btn" href="/oauth/start">…or Start real OAuth (redirect to LHV)</a></div>)
    end
  end

  def accounts_table(accounts)
    return notice("No accounts returned.", kind: "warn") if accounts.empty?

    rows = accounts.map do |a|
      %(<tr><td><code>#{h(a.provider_account_id)}</code></td><td>#{h(a.iban)}</td>
        <td>#{h(a.owner_name)}</td><td>#{h(a.provider_reported_currency)}</td>
        <td>#{h(a.cash_account_type)}</td><td>#{h(a.status)}</td>
        <td><button hx-post="/balances" hx-target="#balances-result"
              hx-vals='{"account_id":"#{h(a.provider_account_id)}"}'>Balances</button></td></tr>)
    end.join
    <<~HTML
      <table class="grid"><thead><tr><th>resourceId</th><th>IBAN</th><th>owner</th>
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
        link = https ? %(<a class="btn" href="#{h(sca)}" target="_blank" rel="noopener">Open SCA redirect ↗</a>) : ""
        %(<p><b>scaRedirect:</b> <code>#{h(sca)}</code> #{link}</p>
          <p class="muted">Complete SCA in the bank UI (sandbox PIN calculator, e.g. 0000), then poll status.</p>)
      else
        %(<p class="muted">No scaRedirect — SCA exemption likely (already #{h(sub.status.status)}).</p>)
      end
    methods = sub.sca_method_ids.empty? ? "—" : h(sub.sca_method_ids.join(", "))
    <<~HTML
      #{notice("Submitted. paymentId=#{h(sub.provider_reference&.value)}")}
      <table class="kv">
        <tr><th>status</th><td>#{h(sub.status.status)} (#{h(sub.status.raw_status)})</td></tr>
        <tr><th>safety_status</th><td>#{h(sub.safety_status)}</td></tr>
        <tr><th>side_effect_possible</th><td>#{h(sub.side_effect_possible)}</td></tr>
        <tr><th>decoupled SCA methods</th><td>#{methods}</td></tr>
      </table>
      #{sca_html}
      <div class="row">
        <button hx-post="/payments/status" hx-target="#pis-status"
          hx-vals='{"payment_id":"#{h(sub.provider_reference&.value)}"}'>Poll status</button>
        <button hx-post="/payments/cancel" hx-target="#pis-status"
          hx-vals='{"payment_id":"#{h(sub.provider_reference&.value)}"}'>Cancel (pre-SCA)</button>
      </div>
      <div id="pis-status"></div>
    HTML
  end

  def status_panel(payment_id, st)
    <<~HTML
      #{notice("paymentId=#{h(payment_id)}")}
      <table class="kv">
        <tr><th>status</th><td>#{h(st.status)} (#{h(st.raw_status)})</td></tr>
        <tr><th>safety_status</th><td>#{h(st.safety_status)}</td></tr>
        <tr><th>side_effect_possible</th><td>#{h(st.side_effect_possible)}</td></tr>
      </table>
    HTML
  end

  def home_body
    <<~HTML
      <section><h2>1 · Configuration</h2>#{config_status}
        <button hx-post="/tpp" hx-target="#tpp-result">Verify TPP (mTLS smoke test)</button>
        <div id="tpp-result"></div>
      </section>

      <section><h2>2 · Authentication</h2>#{auth_status}</section>

      <section><h2>3 · AIS — accounts &amp; balances</h2>
        <button hx-post="/accounts" hx-target="#accounts-result">List accounts</button>
        <div id="accounts-result"></div>
      </section>

      <section><h2>4 · PIS — SEPA payment</h2>
        <form hx-post="/payments/init" hx-target="#pis-result">
          <label>amount <input name="amount" value="1.00" size="8"></label>
          <label>ccy <input name="currency" value="EUR" size="5"></label><br>
          <label>debtor IBAN <input name="debtor_iban" value="EE717700771001735865" size="28"></label><br>
          <label>creditor IBAN <input name="creditor_iban" value="EE857700771001735904" size="28"></label><br>
          <label>creditor name <input name="creditor_name" value="Donald Duck" size="20"></label><br>
          <label>remittance <input name="remittance" value="navesti harness" size="28"></label><br>
          <button type="submit">Initiate payment</button>
        </form>
        <div id="pis-result"></div>
      </section>
    HTML
  end

  def layout(body)
    <<~HTML
      <!doctype html><html><head><meta charset="utf-8">
      <title>Navesti × LHV sandbox harness</title>
      <script src="https://unpkg.com/htmx.org@1.9.12"></script>
      <style>
        body{font:14px/1.5 system-ui,sans-serif;max-width:880px;margin:2rem auto;padding:0 1rem;color:#1a1a1a}
        h1{font-size:1.3rem} h2{font-size:1.05rem;margin-top:1.6rem;border-bottom:1px solid #eee;padding-bottom:.3rem}
        section{margin-bottom:1rem}
        button,.btn{font:inherit;padding:.35rem .7rem;border:1px solid #bbb;border-radius:6px;background:#f6f6f6;cursor:pointer;text-decoration:none;color:#1a1a1a;display:inline-block;margin:.2rem .2rem .2rem 0}
        button:hover,.btn:hover{background:#ececec}
        input{font:inherit;padding:.2rem .35rem;border:1px solid #ccc;border-radius:4px;margin:.15rem 0}
        label{display:inline-block;margin-right:.6rem}
        table{border-collapse:collapse;margin:.5rem 0}
        .kv th{text-align:left;padding:.2rem .6rem .2rem 0;color:#555;font-weight:600;vertical-align:top}
        .kv td{padding:.2rem 0}
        .grid th,.grid td{border:1px solid #e3e3e3;padding:.3rem .5rem;text-align:left}
        .grid th{background:#fafafa}
        code{background:#f3f3f3;padding:.05rem .3rem;border-radius:3px}
        .notice{padding:.4rem .6rem;border-radius:6px;margin:.4rem 0}
        .ok{background:#eaf6ec;border:1px solid #bfe3c6}
        .warn{background:#fff6e5;border:1px solid #f0d8a8}
        .err{background:#fbe9e9;border:1px solid #f0bcbc}
        .muted{color:#777} .row{margin:.4rem 0}
      </style></head><body>
      <h1>Navesti × LHV sandbox connectivity harness</h1>
      <p class="muted">Developer tool. Navesti is headless; this app renders the UX (the Cockpit's role).
      Sandbox-only — live calls need <code>LHV_LIVE=1</code>. Tokens stay server-side and are never shown.</p>
      #{body}
      </body></html>
    HTML
  end
end
