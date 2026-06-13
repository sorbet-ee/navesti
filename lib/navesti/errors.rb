# frozen_string_literal: true

module Navesti
  # Base for every error Navesti raises. Catch this to catch anything Navesti.
  #
  # All Navesti errors run their message through Redaction so that secrets
  # (bearer tokens, auth codes, PEM material, absolute key paths) can never
  # leak through exception text. See docs/10-security-model.md.
  class Error < StandardError
    def initialize(message = nil)
      super(message && Redaction.scrub(message.to_s))
    end
  end

  # A value object was constructed with invalid/missing fields.
  class ValidationError < Error; end

  # A provider response could not be read into a canonical value object.
  # Note: a mapping error on a 2xx PIS response is NOT an explicit rejection;
  # callers translate it to an ambiguous/unknown outcome (docs/07, docs/08).
  class MappingError < Error
    attr_reader :field, :path

    def initialize(message, field: nil, path: nil)
      @field = field
      @path = path
      super(message)
    end
  end

  # Transport-level failure (timeout, connection error, TLS failure). Carries
  # whether the request may already have reached the bank.
  class TransportError < Error
    # side_effect_possible: true unless we can prove the request never left.
    attr_reader :side_effect_possible

    def initialize(message, side_effect_possible: true)
      @side_effect_possible = side_effect_possible
      super(message)
    end
  end

  # Credential/certificate problems detected locally, before or during a call.
  # Messages must stay path-free outside debug mode (docs/10).
  class CredentialError < Error; end

  # An access token / consent was rejected by the bank as expired or invalid.
  # The host re-supplies credentials; Navesti never refreshes on its own.
  class ConsentError < Error; end

  # The bank returned a recognizable error response (4xx/5xx with a body we
  # could read). Carries the HTTP status and any provider error code.
  class ProviderError < Error
    attr_reader :http_status, :provider_code

    def initialize(message, http_status: nil, provider_code: nil)
      @http_status = http_status
      @provider_code = provider_code
      super(message)
    end
  end
end
