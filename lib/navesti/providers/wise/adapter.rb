# frozen_string_literal: true

require "json"
require "uri"
require "securerandom"

module Navesti
  module Providers
    module Wise
      # The Wise (UK OBIE 3.1.11) adapter: explicit, ordered operations over the
      # Open Banking AIS interface. Like LHV, there is no flow engine — the
      # "flow" is the documented calling order, which here is OBIE's two-token
      # Hybrid Flow:
      #
      #   app_token (client_credentials)         -> token to create the consent
      #   create_consent (Permissions)           -> ConsentId (AwaitingAuthorisation)
      #   authorize_url (signed JWT Request Obj)  -> (PSU at bank) -> code id_token
      #   exchange_code (authorization_code)      -> user access + refresh tokens
      #   accounts / balances / consent_status    -> normalized facts
      #
      # What differs from LHV (a different PSD2 standard, by design — docs/14):
      #   - a client_credentials app token is needed *before* the consent;
      #   - the authorize step carries a PS256-signed Request Object
      #     (security/jws) with openbanking_intent_id = ConsentId;
      #   - the wire shape is the OBIE { "Data": … } envelope (Mappers).
      #
      # Stateless: every call takes what it needs; persists nothing.
      class Adapter
        include Adapters::ErrorGuard # guard_response! / guard_oauth_response! / raise_provider_error!
        include Adapters::Headers    # bearer_headers

        attr_reader :config, :credentials

        # The signed Request Object is short-lived: it only has to survive the
        # browser redirect to the authorize endpoint.
        REQUEST_OBJECT_TTL = 300 # seconds

        def initialize(credentials:, env: :sandbox, http: HTTP::Client.new, request_id: nil, clock: nil)
          @credentials = credentials
          @config = Config.new(env: env)
          @http = http
          @request_id = request_id || -> { SecureRandom.uuid }
          @clock = clock || -> { Time.now.utc }
        end

        # POST /auth/token (client_credentials) — the app token used to create a
        # consent. mTLS + client_id in the body bind the cert to the client
        # (RFC8705). Default AISP scope is "accounts".
        def app_token(scope: "accounts")
          token_request(grant_type: "client_credentials", scope: scope)
        end

        # POST /aisp/account-access-consents — creates an account-access consent
        # with the requested OBIE permissions, returning a Consent in
        # AwaitingAuthorisation. The host holds the ConsentId and supplies it to
        # #authorize_url. No interaction is returned here — the authorize URL is
        # built + signed by #authorize_url (unlike LHV's _links.scaRedirect).
        def create_consent(access_token:, permissions: Dialect::DEFAULT_PERMISSIONS)
          body = { "Data" => { "Permissions" => permissions }, "Risk" => {} }
          response = @http.request(
            method: :post,
            url: config.account_access_consents_url,
            headers: bearer_headers(access_token, "Content-Type" => "application/json"),
            body: JSON.generate(body),
            credentials: credentials
          )
          guard_response!(response)
          Mappers.consent(response)
        end

        # Builds the Hybrid-Flow authorization redirect. URL construction + JWS
        # signing only — no HTTP. The Request Object (PS256, OBSeal key) carries
        # the duplicated params and openbanking_intent_id = consent_id. Returns
        # an Interaction the host presents; the bank renders login + 2FA + SCA.
        def authorize_url(consent_id:, redirect_uri:, scope: "openid accounts", state: nil, nonce: nil)
          request_jwt = sign_request_object(
            consent_id: consent_id, redirect_uri: redirect_uri, scope: scope, state: state, nonce: nonce
          )
          url = config.oauth_authorize_url(
            client_id: client_id, redirect_uri: redirect_uri, scope: scope,
            request_jwt: request_jwt, state: state, nonce: nonce
          )
          Interaction.new(type: :redirect, url: url, state: state)
        end

        # POST /auth/token (authorization_code) — exchanges the post-SCA code for
        # the user access + refresh token pair (scope carries consent-id:<id>).
        def exchange_code(code:, redirect_uri:)
          token_request(grant_type: "authorization_code", code: code, redirect_uri: redirect_uri)
        end

        # POST /auth/token (refresh_token) — mints a fresh access token. The host
        # owns token lifecycle/storage; Navesti only performs the exchange.
        def refresh_token(refresh_token:)
          token_request(grant_type: "refresh_token", refresh_token: refresh_token)
        end

        # GET /aisp/accounts → [Account]. Uses the user access token.
        def accounts(access_token:)
          response = @http.request(
            method: :get, url: config.accounts_url,
            headers: bearer_headers(access_token), credentials: credentials
          )
          guard_response!(response)
          Mappers.accounts(response)
        end

        # GET /aisp/accounts/{id} → Account (or nil if the bank returns none).
        def account(access_token:, account_id:)
          response = @http.request(
            method: :get, url: config.account_url(account_id),
            headers: bearer_headers(access_token), credentials: credentials
          )
          guard_response!(response)
          Mappers.accounts(response).first
        end

        # GET /aisp/accounts/{id}/balances → [Balance], one per currency.
        def balances(access_token:, account_id:)
          response = @http.request(
            method: :get, url: config.account_balances_url(account_id),
            headers: bearer_headers(access_token), credentials: credentials
          )
          guard_response!(response)
          Mappers.balances(response, provider_account_id: account_id)
        end

        # GET /aisp/account-access-consents/{id} → Consent. Poll after the PSU
        # completes SCA; status moves AwaitingAuthorisation → Authorised (:valid).
        def consent_status(access_token:, consent_id:)
          response = @http.request(
            method: :get, url: config.account_access_consent_url(consent_id),
            headers: bearer_headers(access_token), credentials: credentials
          )
          guard_response!(response)
          Mappers.consent_status(response)
        end

        # --- PISP (domestic, same-currency) ---

        # POST /pisp/domestic-payment-consents — creates a payment-order consent
        # carrying the Initiation, returning a Consent in AwaitingAuthorisation
        # (with a 30-min CutOffDateTime). The host authorizes it via #authorize_url
        # (scope "openid payments"), exchanges the code, then calls
        # #create_domestic_payment with the ConsentId. Validated host-side first.
        def create_domestic_payment_consent(access_token:, order:)
          Dialect.validate_payment_order!(order)
          body = { "Data" => { "Initiation" => payment_initiation(order) }, "Risk" => {} }
          response = @http.request(
            method: :post,
            url: config.domestic_payment_consents_url,
            headers: payment_headers(access_token, order),
            body: JSON.generate(body),
            credentials: credentials
          )
          guard_response!(response)
          Mappers.consent(response)
        end

        # POST /pisp/domestic-payments — submits the payment-order against an
        # authorized consent. Post-SCA: the returned PaymentSubmission carries a
        # status (no interaction). The Initiation must match the consent's.
        def create_domestic_payment(access_token:, consent_id:, order:)
          Dialect.validate_payment_order!(order)
          body = { "Data" => { "ConsentId" => consent_id, "Initiation" => payment_initiation(order) }, "Risk" => {} }
          response = @http.request(
            method: :post,
            url: config.domestic_payments_url,
            headers: payment_headers(access_token, order),
            body: JSON.generate(body),
            credentials: credentials
          )
          guard_response!(response)
          Mappers.payment_submission(response, idempotency_key: order.idempotency_key)
        end

        # GET /pisp/domestic-payments/{id} → PaymentStatus.
        def domestic_payment_status(access_token:, payment_id:)
          response = @http.request(
            method: :get, url: config.domestic_payment_url(payment_id),
            headers: bearer_headers(access_token), credentials: credentials
          )
          guard_response!(response)
          Mappers.payment_status(response, payment_id: payment_id)
        end

        private

        # OBIE payment endpoints require an x-idempotency-key (≤40 chars). Unlike
        # LHV's JSON SEPA (no documented idempotency), this is a real bank-side
        # dedup key — a host idempotency_key flows straight through.
        def payment_headers(access_token, order)
          bearer_headers(
            access_token,
            "Content-Type" => "application/json",
            "x-idempotency-key" => idempotency_key_for(order)
          )
        end

        # Builds the OBIE domestic Initiation from a Navesti PaymentOrder. The
        # same Initiation is sent on both the consent and the payment-order, so
        # they match. Our AccountRef is IBAN-based → UK.OBIE.IBAN scheme.
        def payment_initiation(order)
          initiation = {
            "InstructionIdentification" => instruction_id(order),
            "EndToEndIdentification" => (order.end_to_end_reference || "NOTPROVIDED").to_s[0, 35],
            "InstructedAmount" => { "Amount" => order.money.to_decimal_string, "Currency" => order.money.currency },
            "CreditorAccount" => {
              "SchemeName" => "UK.OBIE.IBAN",
              "Identification" => order.creditor.iban,
              "Name" => order.creditor_name
            }
          }
          remittance = {}
          remittance["Reference"] = order.end_to_end_reference if order.end_to_end_reference
          remittance["Unstructured"] = order.remittance_information if order.remittance_information
          initiation["RemittanceInformation"] = remittance unless remittance.empty?
          initiation
        end

        # InstructionIdentification (≤35): derived from the host idempotency key
        # so a retry reuses it; otherwise a fresh random id.
        def instruction_id(order)
          (order.idempotency_key || SecureRandom.hex(16)).to_s[0, 35]
        end

        def idempotency_key_for(order)
          order.idempotency_key || SecureRandom.uuid
        end

        # The registered OBIE client_id (the cert CN matches it). The host
        # supplies it as credentials.tpp_id — unlike LHV, it is not the cert's
        # organizationIdentifier, so we never derive it from the cert here.
        def client_id
          @client_id ||= credentials.tpp_id ||
            raise(CredentialError, "Wise requires credentials.tpp_id set to the registered OBIE client_id")
        end

        # Shared token-endpoint call: form-encoded body + client_id, mTLS.
        def token_request(**fields)
          body = URI.encode_www_form(fields.merge(client_id: client_id))
          response = @http.request(
            method: :post,
            url: config.token_url,
            headers: base_headers("Content-Type" => "application/x-www-form-urlencoded"),
            body: body,
            credentials: credentials
          )
          guard_oauth_response!(response)
          Mappers.token(response)
        end

        # Builds + PS256-signs the OBIE Request Object. Every URL param is
        # duplicated inside the JWT (OBIE requirement), and openbanking_intent_id
        # binds the authorization to this consent. iat/exp come from the injected
        # clock so the gem stays testable.
        def sign_request_object(consent_id:, redirect_uri:, scope:, state:, nonce:)
          now = @clock.call.to_i
          intent = { "value" => consent_id, "essential" => true }
          claims = {
            "iss" => client_id,
            "aud" => config.audience,
            "response_type" => "code id_token",
            "client_id" => client_id,
            "redirect_uri" => redirect_uri,
            "scope" => scope,
            "iat" => now,
            "exp" => now + REQUEST_OBJECT_TTL,
            "claims" => {
              "id_token" => {
                "openbanking_intent_id" => intent,
                "acr" => { "essential" => true, "values" => ["urn:openbanking:psd2:sca", "urn:openbanking:psd2:ca"] }
              },
              "userinfo" => { "openbanking_intent_id" => intent }
            }
          }
          claims["state"] = state if state
          claims["nonce"] = nonce if nonce

          Security::JWS.sign_ps256(claims, signing_key_pem: credentials.signing_key_pem, kid: credentials.signing_kid)
        end

        def base_headers(extra = {})
          { "x-fapi-interaction-id" => @request_id.call, "Accept" => "application/json" }.merge(extra)
        end

        # Hooks for Adapters::ErrorGuard. Wise is UK OBIE: the error code lives
        # in Errors[].ErrorCode.
        def provider_label
          "Wise"
        end

        def provider_error_code(body)
          Array(body["Errors"]).find { |e| e.is_a?(Hash) && e["ErrorCode"] }&.dig("ErrorCode")
        end
      end
    end
  end
end
