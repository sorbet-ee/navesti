# frozen_string_literal: true

require "uri"

module Navesti
  module Providers
    module LHV
      # LHV environment roots and endpoint builders. The version is per-service
      # (OAuth has none, AIS is v1, PIS JSON is v1.1) — see
      # docs/providers/lhv/swagger-notes.md. This is the Estonian LHV Pank
      # PSD2 / Berlin Group interface, NOT the UK LHV Bank Limited product.
      class Config
        PROVIDER = "lhv"

        ROOTS = {
          sandbox: "https://api.sandbox.lhv.eu/psd2",
          live: "https://api.lhv.eu/psd2"
        }.freeze

        attr_reader :env, :root

        def initialize(env: :sandbox)
          @env = env.to_sym
          @root = ROOTS.fetch(@env) do
            raise ArgumentError, "unknown LHV env #{env.inspect}; expected :sandbox or :live"
          end
        end

        # --- OAuth (no version segment) ---

        def oauth_authorize_url(client_id:, redirect_uri:, state:, scope: "psd2")
          query = URI.encode_www_form(
            scope: scope,
            response_type: "code",
            client_id: client_id,
            redirect_uri: redirect_uri,
            state: state
          )
          "#{root}/oauth/authorize?#{query}"
        end

        def oauth_token_url
          "#{root}/oauth/token"
        end

        # --- AIS (v1) ---

        def tpp_verification_url
          "#{root}/v1/tpp-verification"
        end

        def accounts_list_url(only_active: true)
          query = URI.encode_www_form(onlyActive: only_active)
          "#{root}/v1/accounts-list?#{query}"
        end

        # Read Balances (Berlin Group AIS). Consent-gated — the caller supplies
        # a Consent-ID. Prefer the href from accounts-list when available; this
        # builds the canonical path when it is not.
        def account_balances_url(account_id)
          "#{root}/v1/accounts/#{account_id}/balances"
        end

        # Resolves a (possibly relative) HATEOAS href against the root, so links
        # returned by the bank can be followed without re-hardcoding paths.
        def absolute(href)
          return href if href.to_s.start_with?("http")

          "#{root}#{href}"
        end

        # --- PIS JSON (v1.1) ---

        def sepa_payment_url
          "#{root}/v1.1/payments/sepa-credit-transfers"
        end

        def payment_status_url(payment_id)
          "#{sepa_payment_url}/#{payment_id}/status"
        end
      end
    end
  end
end
