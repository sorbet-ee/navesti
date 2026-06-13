# frozen_string_literal: true

module Navesti
  # Scrubs secrets from any string that might be logged or raised.
  #
  # Navesti never logs credentials (CLAUDE.md rule 18) and routes every error
  # message through here (see Navesti::Error). This is defence-in-depth: the
  # design avoids putting secrets in messages at all, and this guarantees that
  # if one slips through, it is masked.
  #
  # Redaction applies to LOGS and ERROR SURFACES only — never to the raw
  # evidence returned to the host, which lives in the host's trust domain
  # (docs/10-security-model.md).
  module Redaction
    MASK = "[REDACTED]"

    # Sensitive JSON/keyword fields, masked by value. (Authorization headers
    # are handled by the Bearer rule, not here, so the word "Bearer" survives.)
    SENSITIVE_KEYS = %w[
      access_token refresh_token client_secret code password secret
    ].freeze

    # Order matters: PEM blocks first (multiline), then header/field forms.
    PATTERNS = [
      # Whole PEM blocks (private keys, certs) — collapse to a label.
      /-----BEGIN [A-Z0-9 ]+-----.*?-----END [A-Z0-9 ]+-----/m,
      # Authorization: Bearer <token> / "Bearer <token>"
      /Bearer\s+[A-Za-z0-9._\-+\/=]+/,
      # key=value, key: value, and quoted JSON "key":"value" for sensitive keys.
      # Groups: 1=key 2=key-closing-quote 3=separator 4=value-quote.
      /\b(#{SENSITIVE_KEYS.join('|')})\b("?)(\s*[:=]\s*)("?)[^"&\s,}]+\4/i,
    ].freeze

    module_function

    # Returns a copy of +string+ with known secrets masked.
    def scrub(string)
      return string unless string.is_a?(String)

      out = string.dup
      out.gsub!(PATTERNS[0], "#{MASK} (PEM)")
      out.gsub!(PATTERNS[1], "Bearer #{MASK}")
      out.gsub!(PATTERNS[2]) do
        key = Regexp.last_match(1)
        key_quote = Regexp.last_match(2)
        sep = Regexp.last_match(3)
        value_quote = Regexp.last_match(4)
        "#{key}#{key_quote}#{sep}#{value_quote}#{MASK}#{value_quote}"
      end
      out
    end

    # Returns a shallow copy of +hash+ with sensitive keys masked. Used by
    # #inspect on credential-bearing objects.
    def redacted_hash(hash)
      hash.each_with_object({}) do |(k, v), acc|
        acc[k] = sensitive_key?(k) ? MASK : v
      end
    end

    def sensitive_key?(key)
      name = key.to_s.downcase
      SENSITIVE_KEYS.any? { |s| name == s.downcase } ||
        name.include?("secret") || name.include?("token") ||
        name.include?("password") || name.end_with?("_key")
    end
  end
end
