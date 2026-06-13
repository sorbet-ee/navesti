# frozen_string_literal: true

require "net/http"
require "uri"
require "openssl"

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

        response = http.request(req)
        Response.new(
          status: response.code.to_i,
          headers: response.to_hash,
          body: response.body
        )
      rescue OpenSSL::SSL::SSLError => e
        # TLS handshake failed → request never completed; safe side.
        raise TransportError.new("TLS error: #{e.message}", side_effect_possible: false)
      rescue Net::OpenTimeout, Errno::ECONNREFUSED, SocketError => e
        # Failed before the request was written → no side effect.
        raise TransportError.new("connection failed: #{e.message}", side_effect_possible: false)
      rescue Net::ReadTimeout, Net::WriteTimeout => e
        # Request may have reached the bank → unsafe; assume side effect.
        raise TransportError.new("timeout: #{e.message}", side_effect_possible: true)
      end

      private

      def build_http(uri, credentials)
        http = Net::HTTP.new(uri.host, uri.port)
        http.open_timeout = @open_timeout
        http.read_timeout = @read_timeout

        if uri.scheme == "https"
          http.use_ssl = true
          http.verify_mode = OpenSSL::SSL::VERIFY_PEER
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
