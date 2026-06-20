# frozen_string_literal: true

RSpec.describe Navesti::Redaction do
  describe ".scrub" do
    it "masks bearer tokens" do
      out = described_class.scrub("Authorization: Bearer abc123.def-456")
      expect(out).not_to include("abc123")
      expect(out).to include("Bearer [REDACTED]")
    end

    it "masks PEM blocks" do
      pem = "-----BEGIN RSA PRIVATE KEY-----\nMIIEpAIB...\n-----END RSA PRIVATE KEY-----"
      out = described_class.scrub("loaded #{pem} ok")
      expect(out).not_to include("MIIEpAIB")
      expect(out).to include("[REDACTED] (PEM)")
    end

    it "masks sensitive JSON fields" do
      out = described_class.scrub('{"access_token":"secret-value","scope":"psd2"}')
      expect(out).not_to include("secret-value")
      expect(out).to include("psd2")
    end

    it "masks authorization codes and client secrets" do
      expect(described_class.scrub("code=AA532908s")).not_to include("AA532908s")
      expect(described_class.scrub("client_secret=hunter2")).not_to include("hunter2")
    end

    it "leaves ordinary text untouched" do
      expect(described_class.scrub("payment RJCT for EE71...")).to eq("payment RJCT for EE71...")
    end
  end

  describe "error integration" do
    it "scrubs secrets out of raised error messages" do
      err = Navesti::Error.new("failed with Bearer leak-me-token")
      expect(err.message).not_to include("leak-me-token")
    end
  end
end
