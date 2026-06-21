# frozen_string_literal: true

require "json"
require "uri"
require "securerandom"

module Navesti
  module Providers
    module Wise
      # The Wise (UK OBIE 3.1.11) adapter. The Hybrid-Flow mechanics — app token
      # → consent → signed authorize → exchange → AIS/PIS — are shared with
      # Revolut in Navesti::Adapters::UkObieFlow (docs/adr/0007). Wise supplies
      # its mappers/dialect, its correlation headers, and an UNSIGNED JSON write
      # (#post_json): unlike Revolut, Wise does not sign request bodies.
      # Stateless: every call takes what it needs; persists nothing.
      class Adapter
        include Adapters::ErrorGuard # guard_response! / guard_oauth_response! / raise_provider_error!
        include Adapters::Headers    # bearer_headers
        include Adapters::UkObieFlow # app_token, create_consent, authorize_url, accounts, payments, …

        attr_reader :config, :credentials

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

        # Wise writes are plain JSON (no detached body signature). The OBIE
        # payment endpoints take an x-idempotency-key (≤40 chars); the AIS consent
        # does not. Guards the response and yields it to the mapper block.
        def post_json(url, body, access_token:, idempotency_key: nil)
          headers = bearer_headers(access_token, "Content-Type" => "application/json")
          headers["x-idempotency-key"] = idempotency_key if idempotency_key
          response = @http.request(method: :post, url: url, headers: headers, body: JSON.generate(body), credentials: credentials)
          guard_response!(response)
          yield response
        end

        def base_headers(extra = {})
          { "x-fapi-interaction-id" => @request_id.call, "Accept" => "application/json" }.merge(extra)
        end

        # ErrorGuard hook (provider_error_code is OBIE-standard, in UkObieFlow).
        def provider_label = "Wise"
      end
    end
  end
end
