# frozen_string_literal: true

require "json"
require "uri"
require "securerandom"

module Navesti
  module Providers
    module LHV
      # The LHV adapter: a thin set of explicit, ordered operations over the
      # LHV PSD2 / Berlin Group interface. No flow engine (docs/06, docs/13 Q4)
      # — the "flow" is the documented calling order:
      #
      #   tpp_verification
      #   authorize_url -> (PSU at bank) -> exchange_code
      #   accounts_list
      #   initiate_sepa_payment -> (redirect SCA) -> payment_status
      #
      # Stateless: every call takes what it needs as arguments. Persists
      # nothing; returns normalized facts with raw evidence.
      class Adapter
        attr_reader :config, :credentials

        def initialize(credentials:, env: :sandbox, http: HTTP::Client.new, request_id: nil)
          @credentials = credentials
          @config = Config.new(env: env)
          @http = http
          @request_id = request_id || -> { SecureRandom.uuid }
        end

        # GET /v1/tpp-verification — the first smoke test (mTLS + identity).
        # Returns TppVerification for any recognizable response (ENABLED,
        # BLOCKED, certificate-invalid); does not treat BLOCKED/invalid as an
        # exception — they are facts the caller acts on.
        def tpp_verification
          response = @http.request(
            method: :get,
            url: config.tpp_verification_url,
            headers: base_headers,
            credentials: credentials
          )
          Mappers.tpp_verification(response)
        end

        # Builds the OAuth authorization redirect. URL construction only — no
        # HTTP, no UI. Returns an Interaction descriptor; the host presents it,
        # the bank renders SCA (docs/04).
        def authorize_url(redirect_uri:, state:, scope: "psd2")
          url = config.oauth_authorize_url(
            client_id: client_id,
            redirect_uri: redirect_uri,
            state: state,
            scope: scope
          )
          Interaction.new(type: :redirect, url: url, state: state)
        end

        # POST /oauth/token (authorization_code) — exchanges the code for a
        # token pair. Always mints a new pair. Navesti returns the Token to the
        # host and forgets it; refresh/revoke are deferred (docs/10).
        def exchange_code(code:, redirect_uri:)
          body = URI.encode_www_form(
            client_id: client_id,
            grant_type: "authorization_code",
            code: code,
            redirect_uri: redirect_uri
          )
          response = @http.request(
            method: :post,
            url: config.oauth_token_url,
            headers: base_headers("Content-Type" => "application/x-www-form-urlencoded"),
            body: body,
            credentials: credentials
          )
          guard_response!(response)
          Mappers.token(response)
        end

        # GET /v1/accounts-list (no-consent variant). Returns [Account].
        def accounts_list(access_token:, only_active: true, psu_corporate_id: nil)
          headers = bearer_headers(access_token)
          headers["PSU-Corporate-ID"] = psu_corporate_id if psu_corporate_id
          response = @http.request(
            method: :get,
            url: config.accounts_list_url(only_active: only_active),
            headers: headers,
            credentials: credentials
          )
          guard_response!(response)
          Mappers.accounts(response)
        end

        # POST /v1.1/payments/sepa-credit-transfers (JSON). Returns a
        # PaymentSubmission: a redirect interaction when SCA is required, or a
        # confirmed status when an SCA exemption applied (no scaRedirect).
        def initiate_sepa_payment(order:, access_token:, redirect_uri:, nok_redirect_uri: nil, psu_corporate_id: nil)
          headers = bearer_headers(access_token).merge(
            "Content-Type" => "application/json",
            "TPP-Redirect-Preferred" => "true",
            "TPP-Redirect-URI" => redirect_uri
          )
          headers["TPP-Nok-Redirect-URI"] = nok_redirect_uri if nok_redirect_uri
          headers["PSU-Corporate-ID"] = psu_corporate_id if psu_corporate_id

          response = @http.request(
            method: :post,
            url: config.sepa_payment_url,
            headers: headers,
            body: JSON.generate(payment_body(order)),
            credentials: credentials
          )
          guard_response!(response)
          Mappers.payment_submission(response, idempotency_key: order.idempotency_key)
        end

        # GET /v1.1/payments/sepa-credit-transfers/{paymentId}/status
        def payment_status(payment_id:, access_token:)
          response = @http.request(
            method: :get,
            url: config.payment_status_url(payment_id),
            headers: bearer_headers(access_token),
            credentials: credentials
          )
          guard_response!(response)
          Mappers.payment_status(response, payment_id: payment_id)
        end

        private

        def client_id
          @client_id ||= credentials.resolve_tpp_id
        end

        # The Berlin Group / LHV SEPA JSON body. amount_minor -> decimal string
        # via the currency exponent (never *100); debtorAccount is included
        # (optional at LHV, required by our Phase 1 PaymentOrder).
        def payment_body(order)
          body = {
            "instructedAmount" => {
              "currency" => order.money.currency,
              "amount" => order.money.to_decimal_string
            },
            "debtorAccount" => { "iban" => order.debtor.iban },
            "creditorName" => order.creditor_name,
            "creditorAccount" => { "iban" => order.creditor.iban }
          }
          if order.remittance_information
            body["remittanceInformationUnstructured"] = order.remittance_information
          end
          body
        end

        def base_headers(extra = {})
          { "X-Request-ID" => @request_id.call, "Accept" => "application/json" }.merge(extra)
        end

        def bearer_headers(access_token, extra = {})
          base_headers("Authorization" => "Bearer #{access_token}").merge(extra)
        end

        # Surfaces transport-level HTTP failures as typed, redaction-safe errors.
        # 401 -> ConsentError (host re-supplies credentials, Navesti never
        # refreshes). In-body tppMessages ERROR / OAuth error -> ProviderError.
        def guard_response!(response)
          return if response.success?

          raise ConsentError, "LHV rejected the access token (HTTP #{response.status})" if response.status == 401

          body = safe_json(response)
          if body.is_a?(Hash)
            err = (body["tppMessages"] || []).find { |m| m["category"] == "ERROR" }
            if err
              raise ProviderError.new(
                "LHV error #{err['code']} (HTTP #{response.status})",
                http_status: response.status, provider_code: err["code"]
              )
            end
            if body["error"]
              raise ProviderError.new(
                "LHV OAuth error #{body['error']} (HTTP #{response.status})",
                http_status: response.status, provider_code: body["error"]
              )
            end
          end

          raise ProviderError.new("LHV request failed (HTTP #{response.status})", http_status: response.status)
        end

        def safe_json(response)
          response.json
        rescue MappingError
          nil
        end
      end
    end
  end
end
