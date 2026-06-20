# frozen_string_literal: true

require "uri"

module Navesti
  module Http
    # The origin-pinned HATEOAS/redirect guard shared by every provider Config
    # (docs/10, CLAUDE.md). A bank-supplied or tampered link is resolved and
    # then validated to be on the configured API origin (scheme/host/port) and
    # under the root's base path — otherwise UnsafeUrlError, so a credentialed
    # (mTLS/Bearer) request can never be redirected off-origin (SSRF / token
    # exfiltration). Extracted under the three-times rule (ADR-0004): LHV, Wise,
    # and Revolut carried the same `absolute`/`allowed_root?`/`parse_uri`.
    #
    # `include` it into a Config. The Config must expose `root` (the validation
    # root, whose path is the base — "/psd2", "/open-banking", or empty). Where
    # the bank emits host-absolute hrefs (Wise: hrefs already carry the base
    # path), override the private `link_origin` to return the host-only origin.
    module OriginGuard
      def absolute(href)
        s = href.to_s.strip
        raise UnsafeUrlError, "empty URL" if s.empty?
        raise UnsafeUrlError, "refusing protocol-relative URL" if s.start_with?("//")
        raise UnsafeUrlError, "refusing path traversal" if s.include?("..")

        url = s.start_with?("/") ? "#{link_origin}#{s}" : s
        uri = parse_origin_uri(url)
        raise UnsafeUrlError, "refusing URL outside the configured API root" unless within_root?(uri)

        url
      end

      private

      # What a leading-slash href is resolved against. Default: the full `root`
      # (the href is relative to the base path, as LHV/Revolut emit it). Wise
      # overrides this to the host-only origin because its hrefs already carry
      # the `/open-banking` base path.
      def link_origin
        root
      end

      # Same origin (scheme/host/port) AND path under the configured root path
      # (empty base path → any path on the origin is in-scope).
      def within_root?(uri)
        root_uri = URI.parse(root)
        return false unless uri.scheme == root_uri.scheme &&
                            uri.host == root_uri.host &&
                            uri.port == root_uri.port

        path = uri.path.to_s
        base = root_uri.path.to_s
        base.empty? || path == base || path.start_with?("#{base}/")
      end

      def parse_origin_uri(string)
        URI.parse(string)
      rescue URI::InvalidURIError
        raise UnsafeUrlError, "invalid URL"
      end
    end
  end
end
