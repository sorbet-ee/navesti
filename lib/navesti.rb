# frozen_string_literal: true

# Navesti — the small language of bank connectivity for Sorbet.
#
# A headless Ruby gem that describes bank capabilities, flows, mappings,
# statuses, and webhooks as compact, auditable dialects, then turns them into
# normalized AIS/PIS facts for Sorbet-Core. It does not move money, decide
# compliance, own ledger state, retry payments, persist anything, or render UI.
#
# See docs/ for the architecture; CLAUDE.md for the rules.

require_relative "navesti/version"

# Foundations (order matters: redaction before errors).
require_relative "navesti/redaction"
require_relative "navesti/errors"
require_relative "navesti/value_object"

# Value objects (docs/02-domain-model.md).
require_relative "navesti/money"
require_relative "navesti/account_ref"
require_relative "navesti/provider_reference"
require_relative "navesti/account"
require_relative "navesti/balance"
require_relative "navesti/payment_status"
require_relative "navesti/sca_method"
require_relative "navesti/interaction"
require_relative "navesti/tpp_verification"
require_relative "navesti/payment_order"
require_relative "navesti/payment_submission"
require_relative "navesti/token"
require_relative "navesti/credentials"

# Security + HTTP infrastructure (docs/10, shared across PSD2 banks).
require_relative "navesti/security/certificate_identity"
require_relative "navesti/http/response"
require_relative "navesti/http/client"

# Providers.
require_relative "navesti/providers/lhv/config"
require_relative "navesti/providers/lhv/dialect"
require_relative "navesti/providers/lhv/mappers"
require_relative "navesti/providers/lhv/adapter"

module Navesti
  # Constructs a bank adapter. Credentials and HTTP client are supplied by the
  # host; Navesti holds them only for the call's duration.
  #
  #   Navesti.adapter(:lhv, credentials: creds, env: :sandbox)
  def self.adapter(provider, **kwargs)
    case provider.to_sym
    when :lhv
      Providers::LHV::Adapter.new(**kwargs)
    else
      raise ArgumentError, "unknown provider #{provider.inspect}"
    end
  end
end
