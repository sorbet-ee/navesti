# frozen_string_literal: true

require "net/http"
require "uri"

RSpec.describe Navesti::HTTP::Client do
  subject(:client) { described_class.new }

  # transport_error is the pure classifier behind the rescue — test it directly
  # so we cover the class -> side_effect_possible mapping without real sockets.
  def classify(error)
    client.send(:transport_error, error)
  end

  describe "#transport_error classification" do
    it "marks provably-before-send failures as no side effect (safe to retry)" do
      [
        OpenSSL::SSL::SSLError.new("handshake"),
        Net::OpenTimeout.new("connect"),
        Errno::ECONNREFUSED.new,
        SocketError.new("dns")
      ].each do |e|
        err = classify(e)
        expect(err).to be_a(Navesti::TransportError)
        expect(err.side_effect_possible).to eq(false), "expected #{e.class} => false"
      end
    end

    it "marks after-write / ambiguous failures as side-effect-possible (PIS-unsafe)" do
      [
        Net::ReadTimeout.new,
        Net::WriteTimeout.new,
        EOFError.new,
        Errno::ECONNRESET.new,
        Errno::EPIPE.new,
        IOError.new("closed")
      ].each do |e|
        err = classify(e)
        expect(err).to be_a(Navesti::TransportError)
        expect(err.side_effect_possible).to eq(true), "expected #{e.class} => true"
      end
    end

    it "carries only the exception class in the message (no URL leakage)" do
      msg = classify(Errno::ECONNRESET.new("connection reset by peer 1.2.3.4")).message
      expect(msg).to include("ECONNRESET")
      expect(msg).not_to include("1.2.3.4")
    end
  end

  describe "#build_http TLS setup" do
    it "sets an explicit system-default cert store for https" do
      # Net::HTTP's implicit default store inherits a CRL-check flag on some
      # OpenSSL builds and fails ALL verification ("unable to get certificate
      # CRL"); we set a clean store explicitly.
      http = client.send(:build_http, URI("https://api.sandbox.lhv.eu/psd2/v1/x"), nil)
      expect(http.use_ssl?).to be(true)
      expect(http.verify_mode).to eq(OpenSSL::SSL::VERIFY_PEER)
      expect(http.cert_store).to be_a(OpenSSL::X509::Store)
    end
  end

  describe "#perform wraps transport exceptions" do
    it "raises a typed TransportError when the connection raises" do
      fake_http = Object.new
      def fake_http.request(_req) = raise(EOFError, "boom")

      expect { client.send(:perform, fake_http, nil) }
        .to raise_error(Navesti::TransportError) { |e| expect(e.side_effect_possible).to eq(true) }
    end
  end
end
