# Navesti developer command surface.
#
# Real logic lives in Ruby (bin/navesti-lhv-*, tools/browser/*); this Makefile
# is the human surface. Live LHV calls are gated behind LHV_LIVE=1. The browser
# harness is human-in-the-loop, headed, sandbox-only — never a gem dependency.

RUBY    ?= ruby
BUNDLE  ?= bundle
VERSION := $(shell $(RUBY) -Ilib -e 'require "navesti/version"; print Navesti::VERSION' 2>/dev/null)
SWAGGER_URL := https://api.sandbox.lhv.eu/psd2/swagger-ui/index.html?configUrl=/psd2/documentation/api-docs/swagger-config

# Refuse live network calls unless explicitly enabled.
require_live = test "$(LHV_LIVE)" = "1" || { echo "Refusing live LHV call. Set LHV_LIVE=1."; exit 1; }
# Cross-platform "open URL".
OPEN := $(shell command -v open >/dev/null 2>&1 && echo open || echo xdg-open)

.PHONY: help setup test test-unit test-lhv test-live-lhv build install-local console clean \
        cert-check swagger-open lhv-tpp lhv-oauth-url lhv-oauth-manual lhv-oauth-firefox \
        lhv-token-exchange lhv-token-revoke lhv-accounts lhv-balances lhv-sepa-init \
        lhv-sepa-auth-firefox lhv-sepa-status lhv-sepa-cancel lhv-flow-ais lhv-flow-pis webapp

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

webapp: ## Run the LHV connectivity web app (tools/webapp; Roda+htmx, sandbox-only)
	@$(require_live)
	cd tools/webapp && (bundle check >/dev/null 2>&1 || bundle install) && bundle exec rackup -p $${PORT:-9292}

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
