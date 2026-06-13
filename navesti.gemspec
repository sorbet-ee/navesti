# frozen_string_literal: true

require_relative "lib/navesti/version"

Gem::Specification.new do |spec|
  spec.name        = "navesti"
  spec.version     = Navesti::VERSION
  spec.authors     = ["Sorbet"]
  spec.email       = ["openbanking@sorbet.ee"]

  spec.summary     = "The small language of bank connectivity for Sorbet."
  spec.description = "Navesti is a headless Ruby gem that describes bank " \
                     "capabilities, flows, mappings, statuses, and webhooks as " \
                     "compact, auditable dialects, then turns them into normalized " \
                     "AIS/PIS facts for Sorbet-Core. It does not move money, decide " \
                     "compliance, own ledger state, retry payments, or render UI."
  spec.homepage    = "https://github.com/sorbet-ee/navesti"
  spec.license     = "Nonstandard"
  spec.required_ruby_version = ">= 3.1"

  spec.metadata["rubygems_mfa_required"] = "true"
  spec.metadata["source_code_uri"] = spec.homepage

  spec.files = Dir["lib/**/*.rb", "README.md", "CLAUDE.md", "LICENSE"]
  spec.require_paths = ["lib"]

  # Runtime: stdlib only (net/http, openssl, json, bigdecimal, securerandom).
  spec.add_development_dependency "rspec", "~> 3.12"
end
