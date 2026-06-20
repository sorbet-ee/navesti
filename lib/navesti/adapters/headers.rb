# frozen_string_literal: true

module Navesti
  module Adapters
    # Bearer-header assembly shared by every provider adapter. Identical across
    # LHV, Wise, and Revolut (ADR-0004 three-times rule). The bank-specific
    # correlation headers stay in each adapter's own `#base_headers` (LHV's
    # `X-Request-ID`, OBIE's `x-fapi-*`); only the Authorization wrapping is
    # common, so that is what is extracted.
    #
    # `include` it into an adapter that defines #base_headers.
    module Headers
      def bearer_headers(access_token, extra = {})
        base_headers("Authorization" => "Bearer #{access_token}").merge(extra)
      end
    end
  end
end
