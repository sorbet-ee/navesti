# frozen_string_literal: true

require "uri"
require "erb"

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

        def oauth_revoke_url
          "#{root}/oauth/revoke"
        end

        # --- AIS (v1) ---

        def tpp_verification_url
          "#{root}/v1/tpp-verification"
        end

        def accounts_list_url(only_active: true)
          query = URI.encode_www_form(onlyActive: only_active)
          "#{root}/v1/accounts-list?#{query}"
        end

        # Consent-gated accounts list (Berlin Group GET /v1/accounts). Unlike
        # /v1/accounts-list, this one requires a Consent-ID header and returns
        # the full AccountResponse schema — which carries the resourceId needed
        # to build a correct Read Balances path.
        def accounts_with_consent_url(only_active: true)
          query = URI.encode_www_form(onlyActive: only_active)
          "#{root}/v1/accounts?#{query}"
        end

        # AIS consent creation + status (Berlin Group GET/POST /v1/consents).
        def consents_url
          "#{root}/v1/consents"
        end

        def consent_status_url(consent_id)
          "#{root}/v1/consents/#{encode_segment(consent_id)}/status"
        end

        # Read Balances (Berlin Group AIS). Consent-gated — the caller supplies
        # a Consent-ID. Prefer the href from accounts-list when available; this
        # builds the canonical path when it is not.
        def account_balances_url(account_id)
          "#{root}/v1/accounts/#{encode_segment(account_id)}/balances"
        end

        # Resolves a HATEOAS href to a full URL, **pinned to the configured
        # origin AND the PSD2 API root path**. A leading-slash path resolves
        # against root; any URL is then allowed only if its scheme/host/port
        # match root and its path is under root's path (e.g. /psd2). Otherwise
        # UnsafeUrlError — so a bank-supplied or tampered link can never redirect
        # a credentialed request off-origin (SSRF / token exfiltration), nor a
        # browser redirect to an arbitrary page. Reuse for every actionable link.
        def absolute(href)
          s = href.to_s.strip
          raise UnsafeUrlError, "empty URL" if s.empty?
          raise UnsafeUrlError, "refusing protocol-relative URL" if s.start_with?("//")
          raise UnsafeUrlError, "refusing path traversal" if s.include?("..")

          url = s.start_with?("/") ? "#{root}#{s}" : s
          uri = parse_uri(url)
          raise UnsafeUrlError, "refusing URL outside the configured API root" unless allowed_root?(uri)

          url
        end

        # --- PIS JSON (v1.1) ---

        def sepa_payment_url
          "#{root}/v1.1/payments/sepa-credit-transfers"
        end

        def payment_status_url(payment_id)
          "#{sepa_payment_url}/#{encode_segment(payment_id)}/status"
        end

        # Cancel a payment — only valid before the PSU completes SCA.
        def payment_cancel_url(payment_id)
          "#{sepa_payment_url}/#{encode_segment(payment_id)}/cancel"
        end

        private

        # Percent-encodes a single path segment (RFC 3986 unreserved), so a
        # caller/provider id containing /, ?, #, or spaces cannot change the
        # addressed path or inject a query. Encoding keeps everything on-origin.
        def encode_segment(value)
          ERB::Util.url_encode(value.to_s)
        end

        def parse_uri(string)
          URI.parse(string)
        rescue URI::InvalidURIError
          raise UnsafeUrlError, "invalid URL"
        end

        # Same origin (scheme/host/port) AND path under the configured root path.
        def allowed_root?(uri)
          root_uri = URI.parse(root)
          return false unless uri.scheme == root_uri.scheme &&
                              uri.host == root_uri.host &&
                              uri.port == root_uri.port

          path = uri.path.to_s
          base = root_uri.path.to_s # e.g. "/psd2"
          base.empty? || path == base || path.start_with?("#{base}/")
        end
      end
    end
  end
end
