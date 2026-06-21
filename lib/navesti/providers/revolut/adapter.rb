# frozen_string_literal: true

require "json"
require "uri"
require "securerandom"

module Navesti
  module Providers
    module Revolut
      # The Revolut (UK OBIE) adapter. The Hybrid-Flow mechanics are shared with
      # Wise in Navesti::Adapters::UkObieFlow (docs/adr/0007). Revolut's two
      # specifics live here: an x-fapi-financial-id header, and a detached
      # x-jws-signature (PS256, OBIE crit/tan header) over the body of every
      # write (#post_json), verified by Revolut against the JWKS the host
      # publishes (kid/tan join the signature to that JWKS).
      class Adapter
        include Adapters::ErrorGuard # guard_response! / guard_oauth_response! / raise_provider_error!
        include Adapters::Headers    # bearer_headers
        include Adapters::UkObieFlow # app_token, create_consent, authorize_url, accounts, payments, …

        attr_reader :config, :credentials

        TAN_CLAIM = "http://openbanking.org.uk/tan"

        def initialize(credentials:, env: :sandbox, http: HTTP::Client.new, request_id: nil, clock: nil)
          @credentials = credentials
          @config = Config.new(env: env)
          @http = http
          @request_id = request_id || -> { SecureRandom.uuid }
          @clock = clock || -> { Time.now.utc }
        end

        private

        def mappers = Mappers
        def dialect = Dialect

        # Revolut signs every write: bearer + a detached x-jws-signature over the
        # exact JSON body. Payments also carry an x-idempotency-key. Guards the
        # response and yields it to the mapper block.
        def post_json(url, body, access_token:, idempotency_key: nil)
          json = JSON.generate(body)
          headers = bearer_headers(access_token, "Content-Type" => "application/json", "x-jws-signature" => jws_signature(json))
          headers["x-idempotency-key"] = idempotency_key if idempotency_key
          response = @http.request(method: :post, url: url, headers: headers, body: json, credentials: credentials)
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

        def base_headers(extra = {})
          { "x-fapi-financial-id" => Config::FINANCIAL_ID, "x-fapi-interaction-id" => @request_id.call,
            "Accept" => "application/json" }.merge(extra)
        end

        # ErrorGuard hook (provider_error_code is OBIE-standard, in UkObieFlow).
        def provider_label = "Revolut"
      end
    end
  end
end
