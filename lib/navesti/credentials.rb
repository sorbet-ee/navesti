# frozen_string_literal: true

module Navesti
  # The credential shape Navesti needs to talk to a bank. The HOST stores and
  # supplies these; Navesti holds them in memory only for the duration of a
  # call and persists nothing (docs/10-security-model.md, ADR-0006).
  #
  # For LHV this is mTLS/QWAC only: a client certificate + private key (+
  # optional CA chain) referenced by local path, plus the TPP id. No QSEAL /
  # request-body signing.
  #
  # `signing_key_path` + `signing_kid` are OPTIONAL and used only by dialects
  # that sign request objects — Wise (UK OBIE) signs its Hybrid-Flow JWT with a
  # separate OBSeal key (docs/14, security/jws). LHV leaves them nil.
  #
  # #inspect shows only basenames — never the absolute key path, which could
  # reveal workstation structure (docs/10).
  class Credentials < ValueObject
    attribute :client_cert_path
    attribute :client_key_path
    attribute :ca_chain_path, required: false
    attribute :tpp_id, required: false
    attribute :signing_key_path, required: false # OBSeal RSA key (OBIE JWS)
    attribute :signing_kid, required: false       # JWKS key id for the JWS header
    attribute :tan, required: false               # OBIE trusted-anchor (JWKS host domain), e.g. "sorbet.ee"

    # Builds Credentials from environment variables (the documented contract
    # in .env.example). Paths are validated lazily by the HTTP client, not here.
    def self.from_env(env = ENV)
      new(
        client_cert_path: env.fetch("LHV_CLIENT_CERT_PATH"),
        client_key_path: env.fetch("LHV_CLIENT_KEY_PATH"),
        ca_chain_path: env["LHV_CA_CHAIN_PATH"],
        tpp_id: env["LHV_TPP_ID"]
      )
    end

    # Returns the TPP id, deriving it from the certificate if not supplied.
    def resolve_tpp_id
      tpp_id || Security::CertificateIdentity.extract_tpp_id(client_cert_path)
    end

    # The PEM of the request-object signing key, read lazily for dialects that
    # sign (e.g. Wise OBIE). Raises a path-free CredentialError when no signing
    # key was configured or the file cannot be read (docs/10).
    def signing_key_pem
      raise CredentialError, "no signing key configured (signing_key_path is nil)" if signing_key_path.to_s.empty?

      File.read(signing_key_path)
    rescue SystemCallError
      raise CredentialError, "could not read the JWS signing key file"
    end

    def inspect
      "#<Navesti::Credentials cert=#{base(client_cert_path)} key=#{base(client_key_path)} " \
        "ca=#{base(ca_chain_path)} tpp_id=#{tpp_id.inspect} " \
        "signing_key=#{base(signing_key_path)} signing_kid=#{signing_kid.inspect}>"
    end
    alias to_s inspect

    private

    def base(path)
      path ? File.basename(path.to_s) : "nil"
    end

    def validate
      raise ValidationError, "Credentials#client_cert_path must be present" if client_cert_path.to_s.empty?
      raise ValidationError, "Credentials#client_key_path must be present" if client_key_path.to_s.empty?
    end
  end
end
