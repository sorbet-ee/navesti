# frozen_string_literal: true

module Navesti
  module Providers
    module Wise
      # Maps Wise (UK OBIE) JSON into Navesti value objects. The OBIE
      # Data-envelope grammar is shared with Revolut in Navesti::Mappers::UkObie
      # (docs/adr/0007 — the ADR-0004 three-times extraction); Wise supplies only
      # its provider name and dialect. Raw evidence is preserved on every object
      # (docs/01, docs/07).
      module Mappers
        extend Navesti::Mappers::UkObie # accounts/balances/consent/token/payment_* + helpers (+ evidence)

        def self.provider_name = Config::PROVIDER
        def self.dialect = Dialect
      end
    end
  end
end
