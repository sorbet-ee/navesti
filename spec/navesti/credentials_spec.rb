# frozen_string_literal: true

require "tempfile"

RSpec.describe Navesti::Credentials do
  let(:base) do
    described_class.new(client_cert_path: "/abs/path/client.crt", client_key_path: "/abs/path/client.key")
  end

  it "treats the signing key/kid as optional (LHV leaves them nil)" do
    expect(base.signing_key_path).to be_nil
    expect(base.signing_kid).to be_nil
  end

  describe "#inspect" do
    subject(:creds) do
      described_class.new(
        client_cert_path: "/secret/home/obwac.crt", client_key_path: "/secret/home/obwac.key",
        signing_key_path: "/secret/home/obseal.key", signing_kid: "kid-9"
      )
    end

    it "shows basenames and the kid, never absolute paths" do
      expect(creds.inspect).to include("obwac.crt", "obseal.key", "kid-9")
      expect(creds.inspect).not_to include("/secret/home")
    end
  end

  describe "#signing_key_pem" do
    it "reads the configured signing key file" do
      Tempfile.create(["obseal", ".key"]) do |f|
        f.write("-----BEGIN RSA PRIVATE KEY-----\nfake\n-----END RSA PRIVATE KEY-----\n")
        f.flush
        creds = described_class.new(client_cert_path: "c", client_key_path: "k", signing_key_path: f.path)
        expect(creds.signing_key_pem).to include("BEGIN RSA PRIVATE KEY")
      end
    end

    it "raises a path-free CredentialError when no signing key is configured" do
      expect { base.signing_key_pem }.to raise_error(Navesti::CredentialError, /no signing key/)
    end

    it "raises a path-free CredentialError when the file cannot be read" do
      creds = described_class.new(client_cert_path: "c", client_key_path: "k", signing_key_path: "/no/such/file.key")
      expect { creds.signing_key_pem }.to raise_error(Navesti::CredentialError) do |e|
        expect(e.message).to match(/could not read/)
        expect(e.message).not_to include("/no/such/file")
      end
    end
  end
end
