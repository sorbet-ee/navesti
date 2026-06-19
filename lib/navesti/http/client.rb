# frozen_string_literal: true

require "net/http"
require "uri"
require "openssl"
require "timeout"

module Navesti
  module HTTP
    # An mTLS-capable HTTP client built on Ruby stdlib (Net::HTTP). It presents
    # a client certificate + private key for transport-layer TPP identification
    # (eIDAS QWAC) and verifies the server against the system trust store.
    #
    # The client is intentionally generic and injectable: it knows nothing of
    # LHV. Adapters build requests; tests substitute a fake responding to
    # #request. It NEVER logs request/response bodies or headers.
    #
    # Server verification uses the default system CA store (LHV's server cert
    # chains to a public root — DigiCert Global Root G2). The provided CA chain
    # is OUR client-cert issuing chain and is sent as extra_chain_cert when the
    # platform supports it; it is not used to verify the server.
    class Client
      DEFAULT_OPEN_TIMEOUT = 10
      DEFAULT_READ_TIMEOUT = 30

      # Failures that provably occur BEFORE the request is written → no side
      # effect (safe to retry).
      SAFE_BEFORE_SEND = [
        OpenSSL::SSL::SSLError, Net::OpenTimeout,
        Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ENETUNREACH, SocketError
      ].freeze

      # Failures that may occur AFTER the request is written, or are ambiguous →
      # the bank may have acted (unsafe to retry blindly). SystemCallError is the
      # catch-all for ECONNRESET / EPIPE / ECONNABORTED and other Errno.
      UNCERTAIN_AFTER_SEND = [
        Net::ReadTimeout, Net::WriteTimeout, Timeout::Error,
        EOFError, IOError, Net::HTTPBadResponse, SystemCallError
      ].freeze

      def initialize(open_timeout: DEFAULT_OPEN_TIMEOUT, read_timeout: DEFAULT_READ_TIMEOUT)
        @open_timeout = open_timeout
        @read_timeout = read_timeout
      end

      # Performs a request. Returns Navesti::HTTP::Response.
      #
      #   method      - :get / :post / :delete
      #   url         - full URL string
      #   headers     - hash of header name => value
      #   body        - request body string (or nil)
      #   credentials - Navesti::Credentials for mTLS (or nil for no client cert)
      #
      # Raises TransportError (redaction-safe, no secrets) on connection/TLS
      # failure, with side_effect_possible reflecting whether the request may
      # already have reached the bank.
      def request(method:, url:, headers: {}, body: nil, credentials: nil)
        uri = URI.parse(url)
        http = build_http(uri, credentials)
        req = build_request(method, uri, headers, body)
        perform(http, req)
      end

      private

      def perform(http, req)
        response = http.request(req)
        Response.new(status: response.code.to_i, headers: response.to_hash, body: response.body)
      rescue *SAFE_BEFORE_SEND, *UNCERTAIN_AFTER_SEND => e
        raise transport_error(e)
      end

      # Classifies a transport exception. side_effect_possible is false ONLY when
      # the failure provably occurred before the request was written; every
      # after-write or ambiguous failure is true (conservative for PIS retry
      # safety). The message carries the exception class only — never a raw
      # message that could contain a URL.
      def transport_error(error)
        if SAFE_BEFORE_SEND.any? { |klass| error.is_a?(klass) }
          TransportError.new("connection failed before send (#{error.class})", side_effect_possible: false)
        else
          TransportError.new("transport uncertain after send (#{error.class})", side_effect_possible: true)
        end
      end

      def build_http(uri, credentials)
        http = Net::HTTP.new(uri.host, uri.port)
        http.open_timeout = @open_timeout
        http.read_timeout = @read_timeout

        if uri.scheme == "https"
          http.use_ssl = true
          http.verify_mode = OpenSSL::SSL::VERIFY_PEER
          http.min_version = OpenSSL::SSL::TLS1_2_VERSION # no legacy TLS downgrade
          apply_mtls(http, credentials) if credentials
        end
        http
      end

      def apply_mtls(http, credentials)
        http.cert = load_cert(credentials.client_cert_path)
        http.key = load_key(credentials.client_key_path)

        chain = load_chain(credentials.ca_chain_path)
        if chain.any? && http.respond_to?(:extra_chain_cert=)
          http.extra_chain_cert = chain
        end
      end

      def load_cert(path)
        raise CredentialError, "client certificate file missing" unless File.file?(path)

        OpenSSL::X509::Certificate.new(File.read(path))
      rescue OpenSSL::X509::CertificateError
        raise CredentialError, "client certificate invalid"
      end

      def load_key(path)
        raise CredentialError, "client key file missing" unless File.file?(path)

        OpenSSL::PKey.read(File.read(path))
      rescue OpenSSL::PKey::PKeyError
        raise CredentialError, "client key invalid"
      end

      def load_chain(path)
        return [] if path.nil? || !File.file?(path)

        pems = File.read(path).scan(/-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----/m)
        pems.map { |pem| OpenSSL::X509::Certificate.new(pem) }
      rescue OpenSSL::X509::CertificateError
        raise CredentialError, "CA chain invalid"
      end

      def build_request(method, uri, headers, body)
        klass = {
          get: Net::HTTP::Get,
          post: Net::HTTP::Post,
          delete: Net::HTTP::Delete
        }.fetch(method) { raise ArgumentError, "unsupported method #{method.inspect}" }

        req = klass.new(uri)
        headers.each { |k, v| req[k] = v }
        req.body = body if body
        req
      end
    end
  end
end
