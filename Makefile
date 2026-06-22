# Navesti developer command surface.
#
# Real logic lives in Ruby (bin/navesti-lhv-*, tools/browser/*); this Makefile
# is the human surface. Live LHV calls are gated behind LHV_LIVE=1. The browser
# harness is human-in-the-loop, headed, sandbox-only — never a gem dependency.

RUBY    ?= ruby
BUNDLE  ?= bundle
VERSION := $(shell $(RUBY) -Ilib -e 'require "navesti/version"; print Navesti::VERSION' 2>/dev/null)
SWAGGER_URL := https://api.sandbox.lhv.eu/psd2/swagger-ui/index.html?configUrl=/psd2/documentation/api-docs/swagger-config
WEBAPP_PORT ?= 9292

# LHV sandbox defaults — used by every lhv-* target and the webapp, so you don't
# have to pass the long env line. Override by exporting your own values. Paths
# are absolute ($(CURDIR)) so they resolve regardless of a subprocess's CWD.
LHV_ENV              ?= sandbox
LHV_CLIENT_CERT_PATH ?= $(CURDIR)/certs/lhv_sandbox.crt
LHV_CLIENT_KEY_PATH  ?= $(CURDIR)/certs/lhv_sandbox.key
LHV_CA_CHAIN_PATH    ?= $(CURDIR)/certs/lhv_sandbox_chain.pem
export LHV_ENV LHV_CLIENT_CERT_PATH LHV_CLIENT_KEY_PATH LHV_CA_CHAIN_PATH

# Revolut (UK OBIE) sandbox defaults — used by the revolut-* targets and webapp.
# Unlike LHV, Revolut signs every write, so it also needs an OBSeal key + kid +
# tan and the registered OBIE client_id. Override by exporting your own values.
REVOLUT_ENV              ?= sandbox
REVOLUT_CLIENT_CERT_PATH ?= $(CURDIR)/certs/revolut_sandbox_transport.pem
REVOLUT_CLIENT_KEY_PATH  ?= $(CURDIR)/certs/revolut_sandbox.key
# OBSeal signing PRIVATE key. In this sandbox it is the same RSA key as transport
# (revolut_sandbox.key); revolut_sandbox_signing.pem is the signing CERTIFICATE
# (public) and will fail to load as a key ("invalid PEM or not RSA").
REVOLUT_SIGNING_KEY_PATH ?= $(CURDIR)/certs/revolut_sandbox.key
REVOLUT_SIGNING_KID      ?= navesti-revolut-sbx-1
REVOLUT_TAN              ?= sorbet.ee
# Registered OBIE client_id (a sandbox identifier, not secret material — the
# real secrets are the gitignored cert/key). Override by exporting your own.
REVOLUT_CLIENT_ID        ?= a22b9251-3e9a-4a98-8a98-fdfe4a17f956
# OBIE pre-production root the Revolut sandbox server certs chain to. Trusted for
# SERVER verification by the webapp's injected client (the system store lacks it).
REVOLUT_CA_CHAIN_PATH    ?= $(CURDIR)/certs/revolut_obie_sandbox_ca.pem
REVOLUT_WEBAPP_PORT      ?= 9293
# The browser redirect after SCA. It must be one of the client's REGISTERED
# redirect_uris (the AS rejects any other with "Redirect URI not permitted").
# This sandbox client only has https://www.sorbet.ee registered, so the harness
# uses manual paste-back. Override with a localhost callback only if you register
# one via OBIE dynamic client registration (needs the OB software statement).
REVOLUT_WEBAPP_REDIRECT_URI ?= https://www.sorbet.ee
export REVOLUT_ENV REVOLUT_CLIENT_CERT_PATH REVOLUT_CLIENT_KEY_PATH REVOLUT_SIGNING_KEY_PATH \
       REVOLUT_SIGNING_KID REVOLUT_TAN REVOLUT_CLIENT_ID REVOLUT_CA_CHAIN_PATH REVOLUT_WEBAPP_PORT \
       REVOLUT_WEBAPP_REDIRECT_URI

# Refuse live network calls unless explicitly enabled.
require_live = test "$(LHV_LIVE)" = "1" || { echo "Refusing live LHV call. Set LHV_LIVE=1."; exit 1; }
# Cross-platform "open URL".
OPEN := $(shell command -v open >/dev/null 2>&1 && echo open || echo xdg-open)

.PHONY: help setup test test-unit test-lhv test-live-lhv build install-local console clean \
        cert-check swagger-open lhv-tpp lhv-oauth-url lhv-oauth-manual lhv-oauth-firefox \
        lhv-token-exchange lhv-token-revoke lhv-accounts lhv-balances lhv-sepa-init \
        lhv-sepa-auth-firefox lhv-sepa-status lhv-sepa-cancel lhv-flow-ais lhv-flow-pis \
        lhv-webapp lhv-demo lhv_demo \
        test-revolut revolut-webapp revolut-demo revolut_demo

help: ## Show this help
	@echo "Navesti developer commands:"
	@grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-22s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "Live LHV targets require LHV_LIVE=1 and the LHV_* env vars (see .env.example)."

# --- project ---

setup: ## bundle install and prepare tmp directories
	$(BUNDLE) install
	mkdir -p tmp/lhv

test: ## Run all non-live tests
	$(BUNDLE) exec rspec

test-unit: ## Run fast unit tests only (value objects, money, redaction, security)
	$(BUNDLE) exec rspec spec/navesti/money_spec.rb spec/navesti/value_object_spec.rb \
		spec/navesti/redaction_spec.rb spec/navesti/balance_spec.rb spec/navesti/security

test-lhv: ## Run LHV fixture/stub tests only
	$(BUNDLE) exec rspec spec/navesti/providers/lhv

test-revolut: ## Run Revolut fixture/stub tests only
	$(BUNDLE) exec rspec spec/navesti/providers/revolut

test-live-lhv: ## Run live sandbox specs (requires LHV_LIVE=1)
	@$(require_live)
	LHV_LIVE=1 $(BUNDLE) exec rspec spec/live

build: ## Build the gem
	gem build navesti.gemspec

install-local: build ## Build and install the gem locally (no push)
	gem install ./navesti-$(VERSION).gem

console: ## Open an IRB console with Navesti loaded
	irb -Ilib -r navesti

clean: ## Remove tmp artifacts, gems, logs, browser state
	rm -rf tmp *.gem coverage .geckodriver.log firefox-profile tools/browser/.state

# --- diagnostics ---

cert-check: ## Verify cert/key modulus match, extract TPP id, verify chain
	$(RUBY) bin/navesti-lhv-cert-check

swagger-open: ## Open LHV sandbox Swagger in the browser
	$(OPEN) "$(SWAGGER_URL)"

lhv-webapp: ## Run the LHV connectivity web app and open it in the browser (needs LHV_LIVE=1)
	@$(require_live)
	@echo "Launching LHV connectivity harness on http://localhost:$(WEBAPP_PORT) (LHV_ENV=$(LHV_ENV))"
	@( sleep 2 && $(OPEN) "http://localhost:$(WEBAPP_PORT)" >/dev/null 2>&1 ) &
	cd tools/webapp/lhv && (bundle check >/dev/null 2>&1 || bundle install) && bundle exec rackup -p $(WEBAPP_PORT)

lhv-demo: ## Connectivity demo: launch the web app with LHV_LIVE=1 preset (sandbox)
	@$(MAKE) --no-print-directory lhv-webapp LHV_LIVE=1

lhv_demo: lhv-demo ## Alias for lhv-demo

# --- Revolut (UK OBIE) connectivity web app (REVOLUT_LIVE=1) ---

revolut-webapp: ## Run the Revolut connectivity web app against the live sandbox and open it in the browser
	@echo "Launching Revolut connectivity harness on http://localhost:$(REVOLUT_WEBAPP_PORT) (REVOLUT_ENV=$(REVOLUT_ENV), REVOLUT_LIVE=1)"
	@( sleep 2 && $(OPEN) "http://localhost:$(REVOLUT_WEBAPP_PORT)" >/dev/null 2>&1 ) &
	cd tools/webapp/revolut && (bundle check >/dev/null 2>&1 || bundle install) && REVOLUT_LIVE=1 bundle exec rackup -p $(REVOLUT_WEBAPP_PORT)

revolut-demo: revolut-webapp ## Alias for revolut-webapp (live sandbox)

revolut_demo: revolut-webapp ## Alias for revolut-webapp

# --- LHV live calls (LHV_LIVE=1) ---

lhv-tpp: ## Call GET /v1/tpp-verification over mTLS
	@$(require_live)
	$(RUBY) bin/navesti-lhv-tpp

lhv-oauth-url: ## Build and print the OAuth redirect URL (no network)
	$(RUBY) bin/navesti-lhv-oauth-url

lhv-oauth-manual: ## Start local callback server; print URL for manual browser use
	@$(require_live)
	$(RUBY) bin/navesti-lhv-oauth-callback

lhv-oauth-firefox: ## Start callback server and open official Firefox to LHV OAuth
	@$(require_live)
	$(RUBY) tools/browser/lhv_firefox_oauth.rb

lhv-token-exchange: ## Exchange captured code for a token set
	@$(require_live)
	$(RUBY) bin/navesti-lhv-token-exchange

lhv-accounts: ## Use token to list accounts
	@$(require_live)
	$(RUBY) bin/navesti-lhv-accounts

lhv-balances: ## Use token/account to fetch balances (consent-gated)
	@$(require_live)
	$(RUBY) bin/navesti-lhv-balances

lhv-sepa-init: ## Initiate SEPA JSON payment and print scaRedirect
	@$(require_live)
	$(RUBY) bin/navesti-lhv-sepa-init

lhv-sepa-auth-firefox: ## Open scaRedirect in Firefox for manual sandbox SCA + poll
	@$(require_live)
	$(RUBY) tools/browser/lhv_firefox_pis.rb

lhv-sepa-status: ## Poll payment status once
	@$(require_live)
	$(RUBY) bin/navesti-lhv-sepa-status

lhv-sepa-cancel: ## Cancel a payment (pre-SCA only)
	@$(require_live)
	$(RUBY) bin/navesti-lhv-sepa-cancel

lhv-token-revoke: ## Revoke a token (default: saved refresh token)
	@$(require_live)
	$(RUBY) bin/navesti-lhv-token-revoke

lhv-flow-ais: ## Full OAuth -> token -> accounts -> balances developer flow
	@$(require_live)
	$(RUBY) tools/browser/lhv_firefox_oauth.rb
	$(RUBY) bin/navesti-lhv-accounts
	$(RUBY) bin/navesti-lhv-balances

lhv-flow-pis: ## Full initiate -> browser SCA -> status developer flow
	@$(require_live)
	$(RUBY) tools/browser/lhv_firefox_pis.rb
