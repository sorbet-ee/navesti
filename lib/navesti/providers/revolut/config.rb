# frozen_string_literal: true

require "uri"
require "erb"

module Navesti
  module Providers
    module Revolut
      # Revolut Open Banking (UK OBIE 3.1.x) environment roots and endpoint
      # builders. Per Revolut's FAPI 1 Advanced migration (developer.revolut.com
      # update 2025-03-04, "new subdomains and mandatory mTLS"), the token and all
      # RESOURCE endpoints moved to a new mTLS host (-auth) per env; the old hosts'
      # resource paths now return 403 "Deprecated domain" (and auth.revolut.com no
      # longer resolves). But the browser-facing AUTHORIZE UI cannot use mTLS, so
      # it STAYS on the old host. Confirmed from the live OIDC discovery document
      # (GET /.well-known/openid-configuration on the -auth host, over mTLS):
      #
      #   host (mTLS)   sandbox-oba-auth.revolut.com   issuer + /token + consents/accounts/payments
      #   authorize     sandbox-oba.revolut.com        /ui/index.html (Hybrid Flow UI, browser, no mTLS)
      #   production →   oba-auth.revolut.com (mTLS)  +  oba.revolut.com (authorize)
      #
      # Endpoints sit at the host root (no /open-banking/v3.1 prefix — confirmed
      # against the live sandbox: client_credentials token + a signed PS256
      # account-access-consent both succeed on sandbox-oba-auth.revolut.com). This
      # is the THIRD OBIE dialect (LHV is Berlin Group; Wise + Revolut are UK
      # OBIE) — the duplication with providers/wise is the extraction signal
      # (docs/14, ADR-0004).
      class Config
        PROVIDER = "revolut"

        # Revolut's ASPSP id, sent as x-fapi-financial-id on every call. Fixed.
        FINANCIAL_ID = "001580000103UAvAAM"

        # Two hosts per env: the mTLS API/token host (-auth), and the browser
        # authorize host (the old domain, which can't require a client cert). The
        # request-object `aud` is the issuer, which is the API host.
        ROOTS = {
          sandbox:    { api: "https://sandbox-oba-auth.revolut.com", token: "https://sandbox-oba-auth.revolut.com",
                        authorize: "https://sandbox-oba.revolut.com" },
          production: { api: "https://oba-auth.revolut.com",         token: "https://oba-auth.revolut.com",
                        authorize: "https://oba.revolut.com" }
        }.freeze

        attr_reader :env, :root, :token_host, :authorize_host

        def initialize(env: :sandbox)
          @env = env.to_sym
          hosts = ROOTS.fetch(@env) do
            raise ArgumentError, "unknown Revolut env #{env.inspect}; expected :sandbox or :production"
          end
          @root = hosts[:api]
          @token_host = hosts[:token]
          @authorize_host = hosts[:authorize]
        end

        # --- OAuth / OIDC ---

        # All three grants (client_credentials, authorization_code, refresh_token)
        # over mTLS on the token host.
        def token_url
          "#{token_host}/token"
        end

        # The `aud` claim for the signed Request Object — the API host origin.
        def audience
          root
        end

        # Hybrid Flow authorize UI. `request_jwt` is the PS256-signed Request
        # Object (openbanking_intent_id = ConsentId); every URL param is also in
        # the JWT. response_type is "code id_token". Built on the browser-facing
        # authorize host (NOT the mTLS API host — a browser has no client cert).
        def oauth_authorize_url(client_id:, redirect_uri:, scope:, request_jwt:, state: nil, nonce: nil)
          params = {
            response_type: "code id_token",
            client_id: client_id,
            redirect_uri: redirect_uri,
            scope: scope,
            request: request_jwt
          }
          params[:state] = state if state
          params[:nonce] = nonce if nonce
          "#{authorize_host}/ui/index.html?#{URI.encode_www_form(params)}"
        end

        # --- AISP ---

        def account_access_consents_url
          "#{root}/account-access-consents"
        end

        def account_access_consent_url(consent_id)
          "#{root}/account-access-consents/#{encode_segment(consent_id)}"
        end

        def accounts_url
          "#{root}/accounts"
        end

        def account_url(account_id)
          "#{root}/accounts/#{encode_segment(account_id)}"
        end

        def account_balances_url(account_id)
          "#{root}/accounts/#{encode_segment(account_id)}/balances"
        end

        def account_transactions_url(account_id)
          "#{root}/accounts/#{encode_segment(account_id)}/transactions"
        end

        # --- PISP (domestic) ---

        def domestic_payment_consents_url
          "#{root}/domestic-payment-consents"
        end

        def domestic_payment_consent_url(consent_id)
          "#{root}/domestic-payment-consents/#{encode_segment(consent_id)}"
        end

        def domestic_payments_url
          "#{root}/domestic-payments"
        end

        def domestic_payment_url(payment_id)
          "#{root}/domestic-payments/#{encode_segment(payment_id)}"
        end

        # Resolves a HATEOAS href, pinned to the API origin (same SSRF guard as
        # LHV/Wise). Revolut endpoints sit at the root, so the base path is "/".
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

        private

        def encode_segment(value)
          ERB::Util.url_encode(value.to_s)
        end

        def parse_uri(string)
          URI.parse(string)
        rescue URI::InvalidURIError
          raise UnsafeUrlError, "invalid URL"
        end

        # Same origin (scheme/host/port) as the API root. Revolut's API root has
        # no base path, so any path on the origin is in-scope.
        def allowed_root?(uri)
          root_uri = URI.parse(root)
          uri.scheme == root_uri.scheme && uri.host == root_uri.host && uri.port == root_uri.port
        end
      end
    end
  end
end
