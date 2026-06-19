# Navesti × LHV sandbox connectivity harness

A tiny **Roda + htmx** web app that drives the Navesti LHV adapter against the
real LHV sandbox — so you can click through the whole journey (TPP check →
OAuth → accounts → balances → SEPA init → SCA → status/cancel) in a browser
instead of curl.

## This is not part of the gem

Navesti is **headless — no UI, no Roda** (CLAUDE.md). This app is a *separate
consumer* with its **own Gemfile**; Roda/puma never touch the gem's bundle or
gemspec. It plays exactly the role Sorbet-Cockpit will: it renders the UX and
opens bank URLs, while Navesti returns normalized facts and interaction
descriptors. Building it here demonstrates the boundary; it doesn't cross it.

## Run

One command from the repo root — installs the webapp's deps on first run, opens
the browser, and defaults the cert paths to `certs/lhv_sandbox.*`:

```
LHV_LIVE=1 make webapp
```

Override the port or cert paths if needed: `LHV_LIVE=1 WEBAPP_PORT=9300 make webapp`,
or export your own `LHV_CLIENT_CERT_PATH` etc.

Or run it directly:

```
cd tools/webapp && bundle install
LHV_LIVE=1 LHV_CLIENT_CERT_PATH=../../certs/lhv_sandbox.crt \
LHV_CLIENT_KEY_PATH=../../certs/lhv_sandbox.key \
LHV_CA_CHAIN_PATH=../../certs/lhv_sandbox_chain.pem bundle exec rackup -p 9292
```

Then open <http://localhost:9292>. The default `redirect_uri` is
`http://localhost:9292/oauth/callback` (override with `LHV_WEBAPP_REDIRECT_URI`).

**Authenticate via OAuth** (the primary button): you're redirected to LHV's
login, sign in as PSU `Liis-MariMnnik` with the sandbox PIN calculator (any 4
digits, e.g. `0000`), and the callback exchanges the code for a token tied to
**your** TPP certificate. There is no API password — login/SCA happens on LHV's
page, not in this app.

> The documented preset bearer tokens (`Liis-MariMnnik`, `Donaldduck`) are bound
> to LHV's *built-in Swagger certificate* (`PSDEE-LHVTEST-01AAA`), so they return
> `TOKEN_UNKNOWN` with your own registered cert. They're tucked behind a
> "…or use a preset" disclosure for completeness, but OAuth is the real path.

## Flow

1. **Configuration** — shows env, cert basename, TPP id extracted from the cert,
   and whether live calls are enabled. *Verify TPP* is the mTLS smoke test.
2. **Authentication** — either *Start OAuth* (redirects to LHV, completes SCA,
   exchanges the code back at `/oauth/callback`) or *Use sandbox preset* to grab
   the documented `Liis-MariMnnik` bearer token without the OAuth dance.
3. **AIS** — list accounts; *Balances* per account (consent-gated — may need a
   Consent-ID the preset token lacks).
4. **PIS** — initiate a SEPA payment (defaults: Liis-Mari → Donald), open the
   `scaRedirect`, then poll status or cancel (pre-SCA).

## Safety

- **Sandbox-only**; every live action refuses unless `LHV_LIVE=1`.
- **Tokens stay in server-side memory** (a single-user in-process store) — never
  written to a cookie, never rendered to the page; only `token_type`/`scope`/
  `expires_in` metadata is shown.
- All bank/user data is HTML-escaped; Navesti errors are already redaction-safe.
- Single-user localhost dev tool — no sessions, no persistence. Don't expose it.
