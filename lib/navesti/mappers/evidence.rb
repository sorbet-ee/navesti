# frozen_string_literal: true

require "time"

module Navesti
  module Mappers
    # The raw-evidence wrapper every provider mapper attaches to the value
    # objects it builds (docs/01, docs/07, CLAUDE.md rule 9). Identical across
    # every dialect — extracted under the three-times rule (ADR-0004) once LHV,
    # Wise, and Revolut all carried byte-for-byte the same `evidence`.
    #
    # `extend` it into a provider's `Mappers` module so module-level calls
    # (`evidence(response)`) resolve to it unchanged.
    #
    #   module Mappers
    #     extend Navesti::Mappers::Evidence
    #     module_function
    #     def accounts(response) = ... raw: evidence(response) ...
    #   end
    module Evidence
      # redact: true scrubs secrets from the body and headers before storing —
      # used for OAuth token responses, whose body *is* the secret. Other
      # responses keep verbatim evidence (their bodies are not secrets), so
      # auditability is preserved where it is safe.
      def evidence(response, redact: false)
        body = response.body
        headers = response.headers
        if redact
          body = Navesti::Redaction.scrub(body.to_s)
          headers = headers.transform_values { |v| Navesti::Redaction.scrub(v.to_s) }
        end
        { status: response.status, headers: headers, body: body, captured_at: Time.now.utc.iso8601 }
      end
    end
  end
end
