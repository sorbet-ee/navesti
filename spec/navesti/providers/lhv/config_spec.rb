# frozen_string_literal: true

RSpec.describe Navesti::Providers::LHV::Config do
  subject(:config) { described_class.new(env: :sandbox) }

  let(:root) { "https://api.sandbox.lhv.eu/psd2" }

  describe "#absolute (origin-pinned link following)" do
    it "resolves a leading-slash path against root" do
      expect(config.absolute("/v1/accounts/x/balances"))
        .to eq("#{root}/v1/accounts/x/balances")
    end

    it "allows an absolute URL on the configured origin" do
      url = "#{root}/v1/accounts/x/balances"
      expect(config.absolute(url)).to eq(url)
    end

    it "rejects an off-origin absolute URL" do
      expect { config.absolute("https://evil.com/v1/accounts/x/balances") }
        .to raise_error(Navesti::UnsafeUrlError)
    end

    it "rejects a look-alike host" do
      expect { config.absolute("https://api.sandbox.lhv.eu.evil.com/x") }
        .to raise_error(Navesti::UnsafeUrlError)
    end

    it "rejects userinfo-smuggled hosts" do
      expect { config.absolute("https://api.sandbox.lhv.eu@evil.com/x") }
        .to raise_error(Navesti::UnsafeUrlError)
    end

    it "rejects a scheme downgrade to the same host" do
      expect { config.absolute("http://api.sandbox.lhv.eu/psd2/x") }
        .to raise_error(Navesti::UnsafeUrlError)
    end

    it "rejects protocol-relative URLs" do
      expect { config.absolute("//evil.com/x") }.to raise_error(Navesti::UnsafeUrlError)
    end

    it "rejects a same-origin URL outside the PSD2 API root path" do
      expect { config.absolute("https://api.sandbox.lhv.eu/some-other-path") }
        .to raise_error(Navesti::UnsafeUrlError)
    end

    it "rejects a root-prefix look-alike path (/psd2evil)" do
      expect { config.absolute("https://api.sandbox.lhv.eu/psd2evil/x") }
        .to raise_error(Navesti::UnsafeUrlError)
    end

    it "rejects path traversal" do
      expect { config.absolute("/psd2/../evil") }.to raise_error(Navesti::UnsafeUrlError)
    end

    it "allows the bank's SCA UI path under the root (psd2/ui/...)" do
      url = "#{root}/ui/v2/payment/sepa/abc"
      expect(config.absolute(url)).to eq(url)
    end

    it "never echoes the offending URL (it may carry a token)" do
      url = "https://evil.com/cb?code=super-secret-code"
      expect { config.absolute(url) }
        .to(raise_error(Navesti::UnsafeUrlError) { |e| expect(e.message).not_to include("super-secret-code") })
    end
  end

  describe "path-segment encoding" do
    it "encodes ids containing path/query characters" do
      expect(config.payment_status_url("a/b")).to include("/a%2Fb/status")
      expect(config.payment_cancel_url("a?b")).to include("/a%3Fb/cancel")
      expect(config.account_balances_url("a b")).to include("/accounts/a%20b/balances")
    end

    it "prevents an id from traversing to another path" do
      url = config.payment_status_url("../consents/123")
      expect(url).not_to include("/consents/")
      expect(url).to include("..%2Fconsents%2F123")
    end
  end
end
