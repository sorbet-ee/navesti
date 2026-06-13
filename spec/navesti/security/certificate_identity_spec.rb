# frozen_string_literal: true

require "openssl"
require "tmpdir"

RSpec.describe Navesti::Security::CertificateIdentity do
  # Builds a throwaway self-signed cert carrying organizationIdentifier
  # (OID 2.5.4.97). No real certificate or key is committed (docs/10).
  def build_cert(org_identifier:)
    key = OpenSSL::PKey::RSA.new(2048)
    name_entries = []
    name_entries << ["organizationIdentifier", org_identifier] if org_identifier
    name_entries << ["CN", "PSD2 test certificate"]
    subject = OpenSSL::X509::Name.new(name_entries)

    cert = OpenSSL::X509::Certificate.new
    cert.version = 2
    cert.serial = 1
    cert.subject = subject
    cert.issuer = subject
    cert.public_key = key.public_key
    cert.not_before = Time.now - 3600
    cert.not_after = Time.now + 3600
    cert.sign(key, OpenSSL::Digest.new("SHA256"))
    cert
  end

  describe ".from_certificate" do
    it "extracts the TPP id from organizationIdentifier" do
      cert = build_cert(org_identifier: "PSDEE-LHVTEST-e37b7b")
      expect(described_class.from_certificate(cert)).to eq("PSDEE-LHVTEST-e37b7b")
    end

    it "raises a path-free CredentialError when the OID is absent" do
      cert = build_cert(org_identifier: nil)
      expect { described_class.from_certificate(cert) }
        .to raise_error(Navesti::CredentialError, /no organizationIdentifier/)
    end
  end

  describe ".extract_tpp_id" do
    it "reads from a file on disk" do
      cert = build_cert(org_identifier: "PSDEE-TEST-abc123")
      Dir.mktmpdir do |dir|
        path = File.join(dir, "test.crt")
        File.write(path, cert.to_pem)
        expect(described_class.extract_tpp_id(path)).to eq("PSDEE-TEST-abc123")
      end
    end

    it "raises a path-free CredentialError for a missing file" do
      expect { described_class.extract_tpp_id("/no/such/cert.crt") }
        .to raise_error(Navesti::CredentialError, "client certificate file missing")
    end

    it "raises a path-free CredentialError for an invalid certificate" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "bad.crt")
        File.write(path, "not a certificate")
        expect { described_class.extract_tpp_id(path) }
          .to raise_error(Navesti::CredentialError, "client certificate invalid")
      end
    end

    it "never leaks the file path in the error" do
      secret_path = "/Users/angelos/secret-workstation/private.crt"
      expect { described_class.extract_tpp_id(secret_path) }
        .to(raise_error { |e| expect(e.message).not_to include(secret_path) })
    end
  end

  describe "against the real sandbox cert", :live do
    it "extracts the known sandbox TPP id" do
      path = ENV.fetch("LHV_CLIENT_CERT_PATH")
      expect(described_class.extract_tpp_id(path)).to match(/\APSDEE-LHVTEST-/)
    end
  end
end
