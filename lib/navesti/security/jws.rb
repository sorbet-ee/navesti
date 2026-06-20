# frozen_string_literal: true

require "openssl"
require "json"
require "base64"

module Navesti
  module Security
    # Minimal JWS (compact serialization) signer for the algorithm UK Open
    # Banking requires: RSASSA-PSS with SHA-256 (PS256). Used to sign the OBIE
    # Request Object handed to the authorize endpoint. Stdlib OpenSSL only —
    # Navesti adds no `jwt` gem (the gem stays dependency-free; docs/10, docs/14).
    #
    # LHV never needed this: QWAC transport cert only, no request-body / QSEAL
    # signing. Wise OBIE requires a separate OBSeal signing key, so this lives in
    # shared `security/` (sibling to CertificateIdentity), not in the Wise dialect.
    module JWS
      module_function

      # Signs a claims Hash as a compact PS256 JWS. `signing_key_pem` is the
      # PEM-encoded RSA private key (OBSeal); `kid` is the JWKS key id the bank
      # uses to select the verification key. Returns "header.payload.signature".
      def sign_ps256(claims, signing_key_pem:, kid: nil, typ: "JWT")
        header = { "alg" => "PS256", "typ" => typ }
        header["kid"] = kid if kid

        signing_input = "#{encode(header)}.#{encode(claims)}"
        signature = rsa_private_key(signing_key_pem).sign_pss(
          "SHA256", signing_input, salt_length: :digest, mgf1_hash: "SHA256"
        )
        "#{signing_input}.#{base64url(signature)}"
      end

      # Loads the RSA private key, raising a path-free CredentialError on a bad
      # PEM or a non-private key (docs/10 redaction rule — never echo key material).
      def rsa_private_key(pem)
        key = OpenSSL::PKey::RSA.new(pem.to_s)
        raise CredentialError, "JWS signing key must be an RSA private key" unless key.private?

        key
      rescue OpenSSL::PKey::RSAError, OpenSSL::PKey::PKeyError
        raise CredentialError, "could not load the JWS signing key (invalid PEM or not RSA)"
      end

      def encode(hash)
        base64url(JSON.generate(hash))
      end

      # JWS uses base64url WITHOUT padding (RFC 7515 §2).
      def base64url(bytes)
        Base64.urlsafe_encode64(bytes, padding: false)
      end
    end
  end
end
