# frozen_string_literal: true

# Direct contract for the shared SSRF origin guard, independent of any provider
# (it is mixed into every Config). A future bank inherits exactly this behavior.
RSpec.describe Navesti::Http::OriginGuard do
  # A minimal Config-like host that adopts the guard. `link_origin` (what a
  # leading-slash href resolves against) defaults to `root`; pass an override to
  # model Wise's host-absolute hrefs.
  def guard(root:, link_origin: nil)
    Class.new do
      include Navesti::Http::OriginGuard
      attr_reader :root
      def initialize(root, lo)
        @root = root
        @lo = lo
      end

      private

      def link_origin = @lo || root
    end.new(root, link_origin)
  end

  describe "root WITH a base path (LHV-style, e.g. /psd2)" do
    subject(:c) { guard(root: "https://api.bank.test/psd2") }

    it "resolves a leading-slash href against the full root" do
      expect(c.absolute("/v1/accounts/5/balances")).to eq("https://api.bank.test/psd2/v1/accounts/5/balances")
    end

    it "accepts an absolute URL under the base path" do
      expect(c.absolute("https://api.bank.test/psd2/v1/x")).to eq("https://api.bank.test/psd2/v1/x")
    end

    it "rejects a same-origin URL OUTSIDE the base path" do
      expect { c.absolute("https://api.bank.test/other/x") }.to raise_error(Navesti::UnsafeUrlError)
    end
  end

  describe "root WITHOUT a base path (Revolut-style)" do
    subject(:c) { guard(root: "https://oba.bank.test") }

    it "resolves a leading-slash href against the origin" do
      expect(c.absolute("/accounts/5")).to eq("https://oba.bank.test/accounts/5")
    end

    it "accepts any path on the origin (empty base path)" do
      expect(c.absolute("https://oba.bank.test/anything/at/all")).to eq("https://oba.bank.test/anything/at/all")
    end
  end

  describe "host-absolute hrefs via link_origin override (Wise-style)" do
    # root carries the /open-banking base path, but the bank emits hrefs that
    # already include it, so they resolve against the host-only origin.
    subject(:c) { guard(root: "https://ob.bank.test/open-banking", link_origin: "https://ob.bank.test") }

    it "resolves against the host, keeping the bank's own base-path prefix" do
      expect(c.absolute("/open-banking/aisp/accounts")).to eq("https://ob.bank.test/open-banking/aisp/accounts")
    end

    it "still rejects a path outside the base path" do
      expect { c.absolute("/v1/accounts") }.to raise_error(Navesti::UnsafeUrlError)
    end
  end

  describe "rejections (any configuration)" do
    subject(:c) { guard(root: "https://api.bank.test/psd2") }

    {
      "empty" => "",
      "protocol-relative" => "//evil.com/x",
      "path traversal" => "/v1/../../etc",
      "off-origin host" => "https://evil.com/x",
      "look-alike host" => "https://api.bank.test.evil.com/x",
      "scheme downgrade" => "http://api.bank.test/psd2/x",
      "userinfo spoof" => "https://api.bank.test@evil.com/x",
      "invalid URL" => "http://[::1::bad]/x"
    }.each do |label, bad|
      it "refuses #{label}" do
        expect { c.absolute(bad) }.to raise_error(Navesti::UnsafeUrlError)
      end
    end

    it "never echoes the offending URL in the error message (it may carry a token)" do
      expect { c.absolute("https://evil.com/cb?code=SECRET") }
        .to raise_error(Navesti::UnsafeUrlError) { |e| expect(e.message).not_to include("SECRET") }
    end
  end
end
