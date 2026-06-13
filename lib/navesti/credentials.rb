# frozen_string_literal: true

module Navesti
  # The credential shape Navesti needs to talk to a bank. The HOST stores and
  # supplies these; Navesti holds them in memory only for the duration of a
  # call and persists nothing (docs/10-security-model.md, ADR-0006).
  #
  # For LHV Phase 1 this is mTLS/QWAC only: a client certificate + private key
  # (+ optional CA chain) referenced by local path, plus the TPP id. No QSEAL
  # / request-body signing.
  #
  # #inspect shows only basenames — never the absolute key path, which could
  # reveal workstation structure (docs/10).
  class Credentials < ValueObject
    attribute :client_cert_path
    attribute :client_key_path
    attribute :ca_chain_path, required: false
    attribute :tpp_id, required: false

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

    def inspect
      "#<Navesti::Credentials cert=#{base(client_cert_path)} key=#{base(client_key_path)} " \
        "ca=#{base(ca_chain_path)} tpp_id=#{tpp_id.inspect}>"
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
