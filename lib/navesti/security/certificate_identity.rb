# frozen_string_literal: true

require "openssl"

module Navesti
  module Security
    # Extracts the PSD2 TPP identifier from an eIDAS QWAC certificate.
    #
    # The PSD2 ID lives in the Subject's organizationIdentifier field,
    # OID 2.5.4.97 (e.g. "PSDEE-LHVTEST-e37b7b" in LHV sandbox, "PSDEE-FI-..."
    # in production). It is used as the OAuth client_id and is the key all
    # tokens/consents relate to (docs/10, providers/lhv/swagger-notes.md).
    #
    # This is the first LHV utility — identity before any AIS/PIS call.
    module CertificateIdentity
      ORG_IDENTIFIER_OID = "2.5.4.97"
      # OpenSSL may render the field by short name or by OID, depending on the
      # object table; match either.
      ORG_IDENTIFIER_NAMES = ["organizationIdentifier", ORG_IDENTIFIER_OID].freeze

      module_function

      # Reads the TPP id from a certificate file. Raises CredentialError with a
      # path-free message on a missing/invalid file (docs/10 redaction rule).
      def extract_tpp_id(cert_path)
        cert = load_certificate(cert_path)
        from_certificate(cert)
      end

      # Reads the TPP id from an already-parsed OpenSSL::X509::Certificate.
      def from_certificate(cert)
        entry = cert.subject.to_a.find { |name, _value, _type| ORG_IDENTIFIER_NAMES.include?(name) }
        unless entry
          raise CredentialError, "certificate has no organizationIdentifier (OID #{ORG_IDENTIFIER_OID}); not a PSD2 certificate"
        end

        value = entry[1].to_s
        raise CredentialError, "certificate organizationIdentifier is empty" if value.empty?

        value
      end

      def load_certificate(cert_path)
        unless File.file?(cert_path)
          raise CredentialError, "client certificate file missing"
        end

        OpenSSL::X509::Certificate.new(File.read(cert_path))
      rescue OpenSSL::X509::CertificateError
        # Deliberately path-free: do not echo the filesystem path.
        raise CredentialError, "client certificate invalid"
      end
    end
  end
end
