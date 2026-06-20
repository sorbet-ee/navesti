# frozen_string_literal: true

module Navesti
  module Adapters
    # The failed-response guard shared by every provider adapter (docs/08,
    # CLAUDE.md). 401 on an AIS/PIS call → ConsentError (the host re-supplies
    # credentials; Navesti never refreshes). Any other failure → a typed,
    # redaction-safe ProviderError, preferring an in-body provider error code,
    # then an OAuth `error`, then a generic failure. Extracted under the
    # three-times rule (ADR-0004): the control flow was identical across LHV,
    # Wise, and Revolut — only the provider label and the place the error code
    # lives differ (Berlin Group `tppMessages` vs OBIE `Errors[]`).
    #
    # `include` it into an adapter that defines:
    #   - #provider_label        → e.g. "LHV" (used in messages)
    #   - #provider_error_code(body) → the provider error code, or nil
    module ErrorGuard
      # AIS/PIS guard: 401 -> ConsentError; other failures -> ProviderError.
      def guard_response!(response)
        return if response.success?

        raise ConsentError, "#{provider_label} rejected the access token (HTTP #{response.status})" if response.status == 401

        raise_provider_error!(response)
      end

      # OAuth guard: OAuth errors carry an `error` field on both 400 and 401, so
      # surface it rather than masking 401 as a ConsentError.
      def guard_oauth_response!(response)
        return if response.success?

        raise_provider_error!(response)
      end

      def raise_provider_error!(response)
        body = response.json_or_nil
        if body.is_a?(Hash)
          code = provider_error_code(body)
          if code
            raise ProviderError.new(
              "#{provider_label} error #{code} (HTTP #{response.status})",
              http_status: response.status, provider_code: code
            )
          end
          if body["error"]
            raise ProviderError.new(
              "#{provider_label} OAuth error #{body['error']} (HTTP #{response.status})",
              http_status: response.status, provider_code: body["error"]
            )
          end
        end

        raise ProviderError.new("#{provider_label} request failed (HTTP #{response.status})", http_status: response.status)
      end
    end
  end
end
