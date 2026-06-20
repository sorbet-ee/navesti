# Navesti × Revolut (UK OBIE) sandbox connectivity harness

A tiny **Roda + htmx** web app that drives the Navesti Revolut adapter against
the real Revolut Open Banking sandbox — so you can click through the whole
journey (app token → signed consent → Hybrid-Flow authorize → accounts →
balances → domestic payment → status) in a browser instead of curl.

## This is not part of the gem

Navesti is **headless — no UI, no Roda** (CLAUDE.md). This app is a *separate
consumer* with its **own Gemfile**; Roda/puma never touch the gem's bundle or
gemspec. It plays exactly the role Sorbet-Cockpit will: it renders the UX and
opens bank URLs, while Navesti returns normalized facts and interaction
descriptors. Building it here demonstrates the boundary; it doesn't cross it.

This is the **Revolut** app. Each connector gets its own sibling app under
`tools/webapp/<connector>/` with its own Gemfile — none of them ship in the gem
(the gemspec packages `lib/**` only; the gem stays a headless SDK).

## How Revolut differs from LHV

LHV is Berlin Group with a preset bearer-token shortcut. Revolut is **UK OBIE
Hybrid Flow**, so every AIS/PIS interaction goes through the full dance and
there is **no preset token**:

1. **App token** — `client_credentials` over mTLS. A successful token is the
   transport-cert + client-registration smoke test.
2. **Consent** — a *signed* POST (`x-jws-signature`, PS256 with the OBIE
   `crit`/`tan` header) creates an account-access-consent (AIS) or
   domestic-payment-consent (PIS), returning a `ConsentId`.
3. **Authorize** — the PSU is redirected to Revolut's UI with a signed Request
   Object (`openbanking_intent_id = ConsentId`). `response_type=code id_token`
   means the result comes back in the **URL fragment**, which a server can't
   read — so `/oauth/callback` serves a tiny JS page that forwards the fragment
   to `/oauth/exchange`.
4. **Exchange** — `authorization_code` grant → a user access token bound to that
   consent.
5. **AIS / PIS** — read accounts/balances, or submit the domestic payment and
   poll its status.

## Server-cert trust (the OBIE pre-prod root)

Revolut's OBIE endpoints present a server certificate that chains to the
**OpenBanking Pre-Production Root CA**, which is *not* in the system trust store.
Navesti's `HTTP::Client` verifies against the system store only (and uses
`credentials.ca_chain_path` solely as the *client* `extra_chain_cert`), so the
**host injects a transport client** configured for the bank's PKI — keeping the
gem headless and transport-agnostic.

The harness does exactly that: `ObieTrustHTTP` (a thin `Navesti::HTTP::Client`
subclass) adds the CA bundle at `REVOLUT_CA_CHAIN_PATH` as a server trust anchor.
It only *adds* trust — it never disables verification. The bundle ships at
`certs/revolut_obie_sandbox_ca.pem` (gitignored); if you need to refresh it,
capture the chain the sandbox presents:

```
echo | openssl s_client -connect sandbox-oba-auth.revolut.com:443 \
  -servername sandbox-oba-auth.revolut.com -showcerts 2>/dev/null \
  | awk '/BEGIN CERTIFICATE/{c++} c>=2{print}' > certs/revolut_obie_sandbox_ca.pem
```

## Run

One command from the repo root — `make` already sets `REVOLUT_LIVE=1`, the
sandbox `REVOLUT_CLIENT_ID`, the cert/signing paths, and the OBIE CA bundle, then
installs the webapp's deps on first run and opens the browser:

```
make revolut-webapp
```

Override the port or any path by exporting it, e.g.
`REVOLUT_WEBAPP_PORT=9300 make revolut-webapp`, or your own `REVOLUT_CLIENT_ID`.

Or run it directly:

```
cd tools/webapp/revolut && bundle install
REVOLUT_LIVE=1 \
REVOLUT_CLIENT_CERT_PATH=../../../certs/revolut_sandbox_transport.pem \
REVOLUT_CLIENT_KEY_PATH=../../../certs/revolut_sandbox.key \
REVOLUT_CA_CHAIN_PATH=../../../certs/revolut_obie_sandbox_ca.pem \
REVOLUT_SIGNING_KEY_PATH=../../../certs/revolut_sandbox_signing.pem \
REVOLUT_SIGNING_KID=navesti-revolut-sbx-1 \
REVOLUT_TAN=sorbet.ee \
REVOLUT_CLIENT_ID=a22b9251-3e9a-4a98-8a98-fdfe4a17f956 \
bundle exec rackup -p 9293
```

Then open <http://localhost:9293>.

## Redirect URI: registered allow-list & manual paste-back

The authorization server only accepts a `redirect_uri` that is in the client's
**registered** `redirect_uris` — any other value is rejected with *"Redirect URI
not permitted."* You can read what's registered over mTLS:

```
GET https://sandbox-oba-auth.revolut.com/register/<client_id>   # Bearer app token
```

This sandbox client has only `https://www.sorbet.ee` registered, so the harness
defaults `REVOLUT_WEBAPP_REDIRECT_URI=https://www.sorbet.ee` and uses
**manual paste-back**:

1. Step 1 → get an app token. Step 2 → create the AIS consent → **Authorize**
   (opens Revolut's SCA in a new tab).
2. Complete SCA. Your browser lands on
   `https://www.sorbet.ee/#code=…&id_token=…&state=…`. The fragment stays in the
   address bar — it is never sent to that site, so the page content is
   irrelevant.
3. Copy the whole URL, paste it into **Complete authorization** (step 2). The
   harness parses the fragment and exchanges the code for a user token
   server-side over mTLS (the `redirect_uri` sent to `/token` matches the one
   used at authorize, so the code binds correctly).

Adding a `localhost` (or ngrok) callback for the **automatic** JS-bounce flow
requires registering that URI via OBIE dynamic client registration, which needs
the OB **software statement (SSA)**. If you register one, point
`REVOLUT_WEBAPP_REDIRECT_URI` at it (e.g.
`http://localhost:9293/oauth/callback`) and the harness switches to the
automatic callback automatically (the config panel shows which mode is active).

## Configuration

| Env var | Meaning |
| --- | --- |
| `REVOLUT_LIVE` | `1` enables live sandbox calls; anything else refuses them |
| `REVOLUT_ENV` | `sandbox` (default) or `production` |
| `REVOLUT_CLIENT_CERT_PATH` | mTLS (OBWAC) transport certificate |
| `REVOLUT_CLIENT_KEY_PATH` | mTLS private key |
| `REVOLUT_CA_CHAIN_PATH` | OBIE pre-prod root bundle, trusted for server-cert verification |
| `REVOLUT_SIGNING_KEY_PATH` | OBSeal key used for the detached JWS + Request Object |
| `REVOLUT_SIGNING_KID` | JWKS key id stamped into the JWS header |
| `REVOLUT_TAN` | OBIE trusted-anchor (your JWKS host domain, e.g. `sorbet.ee`) |
| `REVOLUT_CLIENT_ID` | the registered OBIE `client_id` (the adapter's `tpp_id`) |
| `REVOLUT_DEBUG` | `0` mutes the terminal HTTP trace (on by default) |
| `REVOLUT_WEBAPP_PORT` | server port (default `9293`) |
| `REVOLUT_WEBAPP_REDIRECT_URI` | OAuth redirect (default `http://localhost:9293/oauth/callback`) |

## Safety

- **Sandbox-only**; every live action refuses unless `REVOLUT_LIVE=1`.
- **Tokens stay in server-side memory** (a single-user in-process store) — never
  written to a cookie, never rendered to the page; only `token_type`/`scope`/
  `expires_in` metadata is shown. The signing key and JWS signature are never
  logged (the terminal trace masks `Authorization` and `x-jws-signature`).
- All bank/user data is HTML-escaped; Navesti errors are already redaction-safe.
- Single-user localhost dev tool — no sessions, no persistence. Don't expose it.
