# frozen_string_literal: true

module Navesti
  # An OAuth token pair returned by token exchange. Credential-bearing:
  # Navesti returns it to the host and forgets it — Navesti never stores or
  # refreshes tokens on its own (docs/03, docs/10). #inspect is redacted so
  # token material cannot leak into logs or error output.
  class Token < ValueObject
    attribute :access_token
    attribute :token_type, default: "bearer"
    attribute :refresh_token, required: false
    attribute :expires_in, required: false
    attribute :scope, required: false
    attribute :obtained_at, required: false
    attribute :raw, required: false

    # Redacted — never print token material.
    def inspect
      "#<Navesti::Token access_token=#{Redaction::MASK} " \
        "refresh_token=#{refresh_token ? Redaction::MASK : 'nil'} " \
        "token_type=#{token_type.inspect} expires_in=#{expires_in.inspect} scope=#{scope.inspect}>"
    end
    alias to_s inspect

    private

    def validate
      raise ValidationError, "Token#access_token must be present" if access_token.to_s.empty?
    end
  end
end
