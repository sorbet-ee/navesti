# frozen_string_literal: true

require "uri"
require "erb"

module Navesti
  module Providers
    module Wise
      # Wise Open Banking (UK OBIE 3.1.11) environment roots and endpoint
      # builders. Two hosts, deliberately distinct (see the Wise docs):
      #
      #   API host       openbanking.wise-sandbox.com   (consents, accounts, …)
      #   identity host  wise-sandbox.com               (authorize, well-known)
      #
      # `root` is the API host plus the `/open-banking` base path, so the
      # origin-pinned `absolute` guard mirrors LHV's `/psd2` pinning. The
      # auth token endpoint is unversioned; AIS/PIS are under `/v3.1.11`.
      #
      # This is the UK OBIE standard, NOT Berlin Group — a deliberate second
      # dialect to separate "PSD2-family mechanics" from "LHV quirks"
      # (docs/14-semantic-compression-and-the-connector-layer.md).
      class Config
        include Navesti::Http::OriginGuard # provides #absolute (origin-pinned), validated against #root

        PROVIDER = "wise"
        API_VERSION = "v3.1.11"

        ROOTS = {
          sandbox:    { api: "https://openbanking.wise-sandbox.com",  identity: "https://wise-sandbox.com" },
          production: { api: "https://openbanking.transferwise.com",  identity: "https://wise.com" }
        }.freeze

        attr_reader :env, :root, :identity

        def initialize(env: :sandbox)
          @env = env.to_sym
          hosts = ROOTS.fetch(@env) do
            raise ArgumentError, "unknown Wise env #{env.inspect}; expected :sandbox or :production"
          end
          @root = "#{hosts[:api]}/open-banking"
          @identity = hosts[:identity]
        end

        # --- OAuth / OIDC (unversioned, on their respective hosts) ---

        # The token endpoint serves all three grants: client_credentials (app
        # token to create a consent), authorization_code (post-SCA user token),
        # and refresh_token. RFC8705: client_id binds the mTLS cert to the client.
        def token_url
          "#{root}/auth/token"
        end

        # OIDC discovery document (algorithms, JWKS, endpoints) on the identity
        # host. Read-only metadata; not credentialed.
        def well_known_url
          "#{identity}/openbanking/.well-known/openid-configuration"
        end

        # The `aud` claim for the signed Request Object: the API host origin
        # (scheme://host, without the /open-banking path), e.g.
        # https://openbanking.wise-sandbox.com — per the Wise authorize example.
        def audience
          api_origin
        end

        # Hybrid Flow authorization endpoint (identity host). `request_jwt` is the
        # signed Request Object carrying the openbanking_intent_id (ConsentId) and
        # the duplicated params; every URL param must also appear inside the JWT.
        # state/nonce are optional but, when present, must match the JWT.
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
          "#{identity}/openbanking/authorize?#{URI.encode_www_form(params)}"
        end

        # --- AISP (v3.1.11) ---

        def account_access_consents_url
          "#{aisp_base}/account-access-consents"
        end

        def account_access_consent_url(consent_id)
          "#{aisp_base}/account-access-consents/#{encode_segment(consent_id)}"
        end

        def accounts_url
          "#{aisp_base}/accounts"
        end

        def account_url(account_id)
          "#{aisp_base}/accounts/#{encode_segment(account_id)}"
        end

        def account_balances_url(account_id)
          "#{aisp_base}/accounts/#{encode_segment(account_id)}/balances"
        end

        def account_transactions_url(account_id)
          "#{aisp_base}/accounts/#{encode_segment(account_id)}/transactions"
        end

        # --- PISP (v3.1.11) ---
        #
        # OBIE payment initiation is a two-resource flow: a payment-order
        # *consent* (authorized via the same Hybrid Flow as AIS) and then the
        # payment-order itself, which references the ConsentId.

        def domestic_payment_consents_url
          "#{pisp_base}/domestic-payment-consents"
        end

        def domestic_payment_consent_url(consent_id)
          "#{pisp_base}/domestic-payment-consents/#{encode_segment(consent_id)}"
        end

        def domestic_payments_url
          "#{pisp_base}/domestic-payments"
        end

        def domestic_payment_url(payment_id)
          "#{pisp_base}/domestic-payments/#{encode_segment(payment_id)}"
        end

        private

        # Wise emits host-absolute hrefs that already carry the `/open-banking`
        # base path, so a leading-slash href resolves against the host-only
        # origin (not `root`, which would double the base path). OriginGuard
        # still validates the result against `root` (origin + `/open-banking`).
        def link_origin
          api_origin
        end

        def aisp_base
          "#{root}/#{API_VERSION}/aisp"
        end

        def pisp_base
          "#{root}/#{API_VERSION}/pisp"
        end

        # The scheme://host[:port] of the API root, without the /open-banking
        # path — used to resolve leading-slash hrefs before re-pinning.
        def api_origin
          u = URI.parse(root)
          port = u.port && u.port != u.default_port ? ":#{u.port}" : ""
          "#{u.scheme}://#{u.host}#{port}"
        end

        def encode_segment(value)
          ERB::Util.url_encode(value.to_s)
        end
      end
    end
  end
end
