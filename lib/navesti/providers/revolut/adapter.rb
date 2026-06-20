# frozen_string_literal: true

require "json"
require "uri"
require "securerandom"

module Navesti
  module Providers
    module Revolut
      # The Revolut Open Banking (UK OBIE) adapter. Same ordered Hybrid Flow as
      # Wise — client_credentials → consent → signed authorize → exchange →
      # AIS/PIS — plus two Revolut specifics on every call: an x-fapi-financial-id
      # header, and a detached x-jws-signature (PS256, with the OBIE crit/tan
      # header) over the body of every write, verified by Revolut against the
      # JWKS the host publishes (kid/tan join the signature to that JWKS).
      class Adapter
        include Adapters::ErrorGuard # guard_response! / guard_oauth_response! / raise_provider_error!
        include Adapters::Headers    # bearer_headers

        attr_reader :config, :credentials

        TAN_CLAIM = "http://openbanking.org.uk/tan"
        REQUEST_OBJECT_TTL = 300

        def initialize(credentials:, env: :sandbox, http: HTTP::Client.new, request_id: nil, clock: nil)
          @credentials = credentials
          @config = Config.new(env: env)
          @http = http
          @request_id = request_id || -> { SecureRandom.uuid }
          @clock = clock || -> { Time.now.utc }
        end

        def app_token(scope: "accounts")
          token_request(grant_type: "client_credentials", scope: scope)
        end

        def create_consent(access_token:, permissions: Dialect::DEFAULT_PERMISSIONS)
          post_signed(config.account_access_consents_url, { "Data" => { "Permissions" => permissions }, "Risk" => {} },
                      access_token: access_token) { |r| Mappers.consent(r) }
        end

        # Hybrid Flow authorize URL (signed Request Object). No HTTP.
        def authorize_url(consent_id:, redirect_uri:, scope: "openid accounts", state: nil, nonce: nil)
          jwt = sign_request_object(consent_id: consent_id, redirect_uri: redirect_uri, scope: scope, state: state, nonce: nonce)
          url = config.oauth_authorize_url(client_id: client_id, redirect_uri: redirect_uri, scope: scope,
                                           request_jwt: jwt, state: state, nonce: nonce)
          Interaction.new(type: :redirect, url: url, state: state)
        end

        def exchange_code(code:, redirect_uri:)
          token_request(grant_type: "authorization_code", code: code, redirect_uri: redirect_uri)
        end

        def refresh_token(refresh_token:)
          token_request(grant_type: "refresh_token", refresh_token: refresh_token)
        end

        def accounts(access_token:)
          get(config.accounts_url, access_token) { |r| Mappers.accounts(r) }
        end

        def account(access_token:, account_id:)
          get(config.account_url(account_id), access_token) { |r| Mappers.accounts(r).first }
        end

        def balances(access_token:, account_id:)
          get(config.account_balances_url(account_id), access_token) { |r| Mappers.balances(r, provider_account_id: account_id) }
        end

        def consent_status(access_token:, consent_id:)
          get(config.account_access_consent_url(consent_id), access_token) { |r| Mappers.consent_status(r) }
        end

        # --- PISP (domestic) ---

        def create_domestic_payment_consent(access_token:, order:)
          Dialect.validate_payment_order!(order)
          post_signed(config.domestic_payment_consents_url,
                      { "Data" => { "Initiation" => payment_initiation(order) }, "Risk" => {} },
                      access_token: access_token, idempotency_key: idempotency_key_for(order)) { |r| Mappers.consent(r) }
        end

        def create_domestic_payment(access_token:, consent_id:, order:)
          Dialect.validate_payment_order!(order)
          post_signed(config.domestic_payments_url,
                      { "Data" => { "ConsentId" => consent_id, "Initiation" => payment_initiation(order) }, "Risk" => {} },
                      access_token: access_token, idempotency_key: idempotency_key_for(order)) do |r|
            Mappers.payment_submission(r, idempotency_key: order.idempotency_key)
          end
        end

        def domestic_payment_status(access_token:, payment_id:)
          get(config.domestic_payment_url(payment_id), access_token) { |r| Mappers.payment_status(r, payment_id: payment_id) }
        end

        private

        def client_id
          @client_id ||= credentials.tpp_id ||
            raise(CredentialError, "Revolut requires credentials.tpp_id set to the registered OBIE client_id")
        end

        def token_request(**fields)
          response = @http.request(
            method: :post, url: config.token_url,
            headers: base_headers("Content-Type" => "application/x-www-form-urlencoded"),
            body: URI.encode_www_form(fields.merge(client_id: client_id)), credentials: credentials
          )
          guard_oauth_response!(response)
          Mappers.token(response)
        end

        # POST a JSON body with bearer + the detached x-jws-signature over that body.
        def post_signed(url, body, access_token:, idempotency_key: nil)
          json = JSON.generate(body)
          headers = bearer_headers(access_token, "Content-Type" => "application/json", "x-jws-signature" => jws_signature(json))
          headers["x-idempotency-key"] = idempotency_key if idempotency_key
          response = @http.request(method: :post, url: url, headers: headers, body: json, credentials: credentials)
          guard_response!(response)
          yield response
        end

        def get(url, access_token)
          response = @http.request(method: :get, url: url, headers: bearer_headers(access_token), credentials: credentials)
          guard_response!(response)
          yield response
        end

        # OBIE detached JWS over the request body (PS256, crit + tan header).
        def jws_signature(body_json)
          header = {
            "alg" => "PS256", "kid" => credentials.signing_kid,
            "crit" => [TAN_CLAIM], TAN_CLAIM => credentials.tan
          }
          Security::JWS.sign_ps256_payload(body_json, signing_key_pem: credentials.signing_key_pem, header: header)
        end

        def sign_request_object(consent_id:, redirect_uri:, scope:, state:, nonce:)
          now = @clock.call.to_i
          intent = { "value" => consent_id, "essential" => true }
          claims = {
            "iss" => client_id, "aud" => config.audience, "response_type" => "code id_token",
            "client_id" => client_id, "redirect_uri" => redirect_uri, "scope" => scope,
            "iat" => now, "exp" => now + REQUEST_OBJECT_TTL,
            "claims" => {
              "id_token" => { "openbanking_intent_id" => intent,
                              "acr" => { "essential" => true, "values" => ["urn:openbanking:psd2:sca", "urn:openbanking:psd2:ca"] } },
              "userinfo" => { "openbanking_intent_id" => intent }
            }
          }
          claims["state"] = state if state
          claims["nonce"] = nonce if nonce
          Security::JWS.sign_ps256(claims, signing_key_pem: credentials.signing_key_pem, kid: credentials.signing_kid)
        end

        def payment_initiation(order)
          init = {
            "InstructionIdentification" => (order.idempotency_key || SecureRandom.hex(16)).to_s[0, 35],
            "EndToEndIdentification" => (order.end_to_end_reference || "NOTPROVIDED").to_s[0, 35],
            "InstructedAmount" => { "Amount" => order.money.to_decimal_string, "Currency" => order.money.currency },
            "CreditorAccount" => { "SchemeName" => "UK.OBIE.IBAN", "Identification" => order.creditor.iban, "Name" => order.creditor_name }
          }
          rem = {}
          rem["Reference"] = order.end_to_end_reference if order.end_to_end_reference
          rem["Unstructured"] = order.remittance_information if order.remittance_information
          init["RemittanceInformation"] = rem unless rem.empty?
          init
        end

        def idempotency_key_for(order) = order.idempotency_key || SecureRandom.uuid

        def base_headers(extra = {})
          { "x-fapi-financial-id" => Config::FINANCIAL_ID, "x-fapi-interaction-id" => @request_id.call,
            "Accept" => "application/json" }.merge(extra)
        end

        # Hooks for Adapters::ErrorGuard. Revolut is UK OBIE: the error code
        # lives in Errors[].ErrorCode (same as Wise).
        def provider_label
          "Revolut"
        end

        def provider_error_code(body)
          Array(body["Errors"]).find { |e| e.is_a?(Hash) && e["ErrorCode"] }&.dig("ErrorCode")
        end
      end
    end
  end
end
