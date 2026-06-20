# Browser harness (developer tooling)

Human-in-the-loop OAuth/SCA via **official, installed Firefox** (headed). This is
developer tooling for running the real LHV journey by hand — **not** part of the
Navesti gem, never imported by `lib/`, never a runtime dependency.

## Why Selenium + official Firefox

LHV requires official, unmodified browsers for its SCA screens. Selenium drives
the locally installed official Firefox, so the bank UI you authenticate against
is the same one LHV supports. (Playwright Firefox, if ever used, is developer
automation only — not proof of official LHV browser compatibility.)

## Prerequisites (installed manually — deliberately not in the bundle)

```
gem install selenium-webdriver
brew install geckodriver        # or ensure geckodriver is on PATH
# Official Firefox must be installed.
```

If `selenium-webdriver` is missing, the scripts print these instructions and exit.

## Rules (enforced; see ../../CLAUDE.md)

- Sandbox-only by default; live gated behind `LHV_LIVE=1`.
- **Headed only** — never headless for bank OAuth/SCA.
- No iframes; the LHV URL stays visible in the address bar.
- Dedicated temporary Firefox profile per run.
- Never automate production credentials; never store login/PIN/SCA codes.
- Artifacts go only to gitignored `tmp/lhv/`; `token_set.json` is `chmod 600`.

## Scripts

- `lhv_firefox_oauth.rb` — opens LHV OAuth in Firefox, captures the code via the
  local callback server, exchanges it for a token set.
- `lhv_firefox_pis.rb` — initiates a SEPA payment, opens `scaRedirect` for manual
  SCA, polls status to a terminal state, saves the trace.

Run them through the Makefile: `make lhv-oauth-firefox`, `make lhv-sepa-auth-firefox`.
