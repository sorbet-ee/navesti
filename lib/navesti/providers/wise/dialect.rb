# frozen_string_literal: true

module Navesti
  module Providers
    module Wise
      # The Wise (UK OBIE) bank dialect. Wise and Revolut share the OBIE
      # vocabulary, so the tables + normalizers live in Navesti::Dialects::UkObie
      # (docs/adr/0007 — the ADR-0004 three-times extraction). `include` makes the
      # tables reachable as Dialect::CONSTANT; `extend` makes the normalizers
      # callable as Dialect.consent_status. Wise uses the full OBIE permission
      # set, so only its provider label differs.
      module Dialect
        include Navesti::Dialects::UkObie # CONSENT_STATUS, PERMISSIONS, balance/payment tables, limits
        extend  Navesti::Dialects::UkObie # consent_status, payment_status, balance classifiers, validate_payment_order!

        def self.provider_label = "Wise"
      end
    end
  end
end
