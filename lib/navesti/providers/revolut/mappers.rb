# frozen_string_literal: true

module Navesti
  module Providers
    module Revolut
      # Maps Revolut (UK OBIE) JSON into Navesti value objects. Same OBIE `Data`
      # envelope as Wise, shared in Navesti::Mappers::UkObie (docs/adr/0007);
      # Revolut supplies only its provider name and dialect.
      module Mappers
        extend Navesti::Mappers::UkObie # accounts/balances/consent/token/payment_* + helpers (+ evidence)

        def self.provider_name = Config::PROVIDER
        def self.dialect = Dialect
      end
    end
  end
end
