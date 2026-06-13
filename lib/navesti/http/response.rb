# frozen_string_literal: true

require "json"

module Navesti
  module HTTP
    # A minimal, transport-agnostic HTTP response. Carries the raw bytes so
    # callers can preserve evidence; JSON parsing is opt-in via #json.
    class Response
      attr_reader :status, :headers, :body

      def initialize(status:, headers:, body:)
        @status = status
        @headers = normalize_headers(headers)
        @body = body
        # Not frozen: #json memoizes lazily. headers/body are individually
        # frozen below; the response wrapper itself is single-use and internal.
        @body.freeze
      end

      def success? = status.between?(200, 299)

      def header(name)
        headers[name.to_s.downcase]
      end

      # Parses the body as JSON. Raises MappingError (not a generic JSON error)
      # so callers get a typed, redaction-safe failure.
      def json
        @json ||= JSON.parse(body.to_s)
      rescue JSON::ParserError => e
        raise MappingError, "response body is not valid JSON: #{e.message}"
      end

      private

      def normalize_headers(headers)
        (headers || {}).each_with_object({}) do |(k, v), acc|
          acc[k.to_s.downcase] = v.is_a?(Array) ? v.first : v
        end.freeze
      end
    end
  end
end
