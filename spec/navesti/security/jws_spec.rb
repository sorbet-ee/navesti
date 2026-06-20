# frozen_string_literal: true

require "base64"

RSpec.describe Navesti::Security::JWS do
  # One keypair for the whole group (RSA generation is slow).
  let(:key) { RSA_KEY }
  RSA_KEY = OpenSSL::PKey::RSA.new(2048)

  def b64url_decode(segment)
    padded = segment + ("=" * ((4 - (segment.length % 4)) % 4))
    Base64.urlsafe_decode64(padded)
  end

  def decode_part(jws, index)
    JSON.parse(b64url_decode(jws.split(".")[index]))
  end

  describe ".sign_ps256" do
    subject(:jws) do
      described_class.sign_ps256(
        { "iss" => "ob-dummy-tpp", "openbanking_intent_id" => "123" },
        signing_key_pem: key.to_pem, kid: "kid-1"
      )
    end

    it "produces a three-part compact JWS" do
      expect(jws.split(".").size).to eq(3)
    end

    it "writes a PS256 header carrying the kid" do
      expect(decode_part(jws, 0)).to eq("alg" => "PS256", "typ" => "JWT", "kid" => "kid-1")
    end

    it "carries the claims verbatim in the payload" do
      expect(decode_part(jws, 1)).to eq("iss" => "ob-dummy-tpp", "openbanking_intent_id" => "123")
    end

    it "produces a signature the matching public key verifies under PS256" do
      header_b64, payload_b64, sig_b64 = jws.split(".")
      signing_input = "#{header_b64}.#{payload_b64}"
      ok = key.verify_pss("SHA256", b64url_decode(sig_b64), signing_input, salt_length: :digest, mgf1_hash: "SHA256")
      expect(ok).to be(true)
    end

    it "uses unpadded base64url (no '=' in any segment)" do
      expect(jws).not_to include("=")
    end

    it "omits kid from the header when not supplied" do
      bare = described_class.sign_ps256({ "a" => 1 }, signing_key_pem: key.to_pem)
      expect(decode_part(bare, 0)).to eq("alg" => "PS256", "typ" => "JWT")
    end
  end

  describe "key errors (path-free)" do
    it "raises CredentialError on an invalid PEM" do
      expect { described_class.sign_ps256({}, signing_key_pem: "not a pem") }
        .to raise_error(Navesti::CredentialError, /could not load/)
    end

    it "raises CredentialError when handed a public key (cannot sign)" do
      expect { described_class.sign_ps256({}, signing_key_pem: key.public_key.to_pem) }
        .to raise_error(Navesti::CredentialError, /RSA private key/)
    end
  end
end
