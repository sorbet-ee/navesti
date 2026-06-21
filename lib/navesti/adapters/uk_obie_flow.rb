# frozen_string_literal: true

require "json"
require "uri"
require "securerandom"

module Navesti
  module Adapters
    # The UK OBIE Hybrid-Flow adapter mechanics, shared by Wise and Revolut
    # (docs/adr/0007, Stage 2c). The ordered flow is the documented calling order
    # — client_credentials app token -> consent -> signed authorize -> exchange ->
    # AIS/PIS — identical across OBIE banks. The one genuine divergence is HOW a
    # write body is sent, so the including adapter supplies #post_json (Wise:
    # bearer + JSON; Revolut: bearer + JSON + a detached x-jws-signature over the
    # exact body). #post_json guards the response and yields it to a mapper block.
    #
    # The including adapter also supplies: #mappers, #dialect, #base_headers, the
    # ErrorGuard hook #provider_label, and the ivars set in its initialize
    # (@http, @request_id, @clock); plus #bearer_headers (Adapters::Headers) and
    # the guards (Adapters::ErrorGuard). provider_error_code is OBIE-standard and
    # lives here.
    module UkObieFlow
      # The signed Request Object only has to survive the browser redirect.
      REQUEST_OBJECT_TTL = 300 # seconds

      # --- OAuth / token grants ---

      # POST /token (client_credentials) — the app token used to create a consent.
      def app_token(scope: "accounts")
        token_request(grant_type: "client_credentials", scope: scope)
      end

      # POST /token (authorization_code) — exchanges the post-SCA code for the
      # user access + refresh token pair.
      def exchange_code(code:, redirect_uri:)
        token_request(grant_type: "authorization_code", code: code, redirect_uri: redirect_uri)
      end

      # POST /token (refresh_token) — mints a fresh access token. The host owns
      # token lifecycle; Navesti only performs the exchange.
      def refresh_token(refresh_token:)
        token_request(grant_type: "refresh_token", refresh_token: refresh_token)
      end

      # Hybrid-Flow authorize redirect: a PS256-signed Request Object whose
      # openbanking_intent_id binds the authorization to this consent. URL +
      # signing only, no HTTP. Returns an Interaction the host presents.
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

      # --- AISP ---

      # POST /account-access-consents → Consent (AwaitingAuthorisation). No
      # interaction: the authorize URL is built + signed by #authorize_url.
      def create_consent(access_token:, permissions: Navesti::Dialects::UkObie::DEFAULT_PERMISSIONS)
        post_json(config.account_access_consents_url,
                  { "Data" => { "Permissions" => permissions }, "Risk" => {} },
                  access_token: access_token) { |r| mappers.consent(r) }
      end

      # GET /accounts → [Account]. Uses the user access token.
      def accounts(access_token:)
        get(config.accounts_url, access_token) { |r| mappers.accounts(r) }
      end

      # GET /accounts/{id} → Account (or nil if the bank returns none).
      def account(access_token:, account_id:)
        get(config.account_url(account_id), access_token) { |r| mappers.accounts(r).first }
      end

      # GET /accounts/{id}/balances → [Balance], one per currency.
      def balances(access_token:, account_id:)
        get(config.account_balances_url(account_id), access_token) { |r| mappers.balances(r, provider_account_id: account_id) }
      end

      # GET /account-access-consents/{id} → Consent. Poll after the PSU completes
      # SCA; status moves AwaitingAuthorisation → Authorised (:valid).
      def consent_status(access_token:, consent_id:)
        get(config.account_access_consent_url(consent_id), access_token) { |r| mappers.consent_status(r) }
      end

      # --- PISP (domestic) ---

      # POST /domestic-payment-consents — a payment-order consent carrying the
      # Initiation. The host authorizes it via #authorize_url (scope "openid
      # payments"), exchanges the code, then calls #create_domestic_payment.
      def create_domestic_payment_consent(access_token:, order:)
        dialect.validate_payment_order!(order)
        post_json(config.domestic_payment_consents_url,
                  { "Data" => { "Initiation" => payment_initiation(order) }, "Risk" => {} },
                  access_token: access_token, idempotency_key: idempotency_key_for(order)) { |r| mappers.consent(r) }
      end

      # POST /domestic-payments — submits the payment-order against an authorized
      # consent. Post-SCA: the submission carries a status, no interaction. The
      # Initiation must match the consent's.
      def create_domestic_payment(access_token:, consent_id:, order:)
        dialect.validate_payment_order!(order)
        post_json(config.domestic_payments_url,
                  { "Data" => { "ConsentId" => consent_id, "Initiation" => payment_initiation(order) }, "Risk" => {} },
                  access_token: access_token, idempotency_key: idempotency_key_for(order)) do |r|
          mappers.payment_submission(r, idempotency_key: order.idempotency_key)
        end
      end

      # GET /domestic-payments/{id} → PaymentStatus.
      def domestic_payment_status(access_token:, payment_id:)
        get(config.domestic_payment_url(payment_id), access_token) { |r| mappers.payment_status(r, payment_id: payment_id) }
      end

      private

      # The registered OBIE client_id — the host supplies it as credentials.tpp_id
      # (unlike LHV, it is not the cert's organizationIdentifier).
      def client_id
        @client_id ||= credentials.tpp_id ||
          raise(CredentialError, "#{provider_label} requires credentials.tpp_id set to the registered OBIE client_id")
      end

      # Shared token-endpoint call: form-encoded body + client_id, mTLS.
      def token_request(**fields)
        response = @http.request(
          method: :post,
          url: config.token_url,
          headers: base_headers("Content-Type" => "application/x-www-form-urlencoded"),
          body: URI.encode_www_form(fields.merge(client_id: client_id)),
          credentials: credentials
        )
        guard_oauth_response!(response)
        mappers.token(response)
      end

      # Shared GET: bearer + guard, then hand the response to the mapper block.
      def get(url, access_token)
        response = @http.request(method: :get, url: url, headers: bearer_headers(access_token), credentials: credentials)
        guard_response!(response)
        yield response
      end

      # OBIE error envelope: the code lives in Errors[].ErrorCode (the ErrorGuard
      # hook). OBIE-standard, so shared across OBIE banks.
      def provider_error_code(body)
        Array(body["Errors"]).find { |e| e.is_a?(Hash) && e["ErrorCode"] }&.dig("ErrorCode")
      end

      # Builds + PS256-signs the OBIE Request Object. Every URL param is
      # duplicated inside the JWT (OBIE requirement); openbanking_intent_id binds
      # it to this consent. iat/exp come from the injected clock for testability.
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

      # Builds the OBIE domestic Initiation from a Navesti PaymentOrder. The same
      # Initiation is sent on both the consent and the payment-order, so they
      # match. Our AccountRef is IBAN-based -> UK.OBIE.IBAN scheme.
      def payment_initiation(order)
        initiation = {
          "InstructionIdentification" => (order.idempotency_key || SecureRandom.hex(16)).to_s[0, 35],
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

      def idempotency_key_for(order)
        order.idempotency_key || SecureRandom.uuid
      end
    end
  end
end
