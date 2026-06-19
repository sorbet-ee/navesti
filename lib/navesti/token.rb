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

    # Redacted by default: #to_h is exactly what apps log, serialize, and pass
    # to background jobs, so it must never carry token material. The typed
    # #access_token / #refresh_token readers still return the real values for
    # the host that needs them; use #to_secret_h for deliberate secure handling.
    # (Consequence: Token equality compares non-secret metadata only.)
    def to_h
      super.merge(
        access_token: Redaction::MASK,
        refresh_token: refresh_token && Redaction::MASK
      )
    end

    # The real token values — for deliberate, secure persistence only. Never log.
    def to_secret_h
      {
        access_token: access_token, refresh_token: refresh_token,
        token_type: token_type, expires_in: expires_in,
        scope: scope, obtained_at: obtained_at
      }
    end

    private

    def validate
      raise ValidationError, "Token#access_token must be present" if access_token.to_s.empty?
    end
  end

  # Alias for the OAuth token pair. Same object as Token; named for callers who
  # think of it as a set (access + refresh).
  OAuthTokenSet = Token
end

