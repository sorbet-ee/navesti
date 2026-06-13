#!/usr/bin/env ruby
# frozen_string_literal: true

# Human-in-the-loop OAuth via official Firefox (headed). Opens the LHV
# authorization URL in a visible, dedicated-profile Firefox; the human completes
# bank login/SCA; the local callback server captures the code; then the code is
# exchanged for a token set.
#
# DEVELOPER TOOLING ONLY. Sandbox-gated (LHV_LIVE=1). Never headless, no iframe,
# LHV URL visible (CLAUDE.md browser rules). Selenium is not a gem dependency.
require_relative "../dev/lhv_dev"

LhvDev.require_live!

driver = nil
begin
  code = LhvDev.capture_oauth_code(timeout: Integer(ENV["LHV_OAUTH_TIMEOUT"] || "300")) do |url, _state|
    driver = LhvDev.open_firefox(url)
    puts "Firefox opened to the LHV login. Complete bank login/SCA in the visible window."
  end

  # Exchange the captured code for a token set (optional but convenient).
  token = LhvDev.adapter.exchange_code(code: code, redirect_uri: LhvDev.redirect_uri)
  LhvDev.save_json("token_set.json", {
    "access_token" => token.access_token,
    "refresh_token" => token.refresh_token,
    "token_type" => token.token_type,
    "expires_in" => token.expires_in,
    "scope" => token.scope,
    "obtained_at" => token.obtained_at
  }, secret: true)
  puts "Token set saved -> tmp/lhv/token_set.json (chmod 600)"
  puts token.inspect # redacted
ensure
  driver&.quit
end
