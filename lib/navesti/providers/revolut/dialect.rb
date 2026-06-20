# frozen_string_literal: true

module Navesti
  module Providers
    module Revolut
      # The Revolut (UK OBIE) bank dialect. Shares the OBIE tables + normalizers
      # via Navesti::Dialects::UkObie (docs/adr/0007 — the ADR-0004 three-times
      # extraction; LHV=Berlin Group, Wise+Revolut=OBIE). `include` exposes the
      # tables as Dialect::CONSTANT; `extend` exposes the normalizers as
      # Dialect.consent_status. Revolut's one delta: its registered consent omits
      # ReadDirectDebits.
      module Dialect
        include Navesti::Dialects::UkObie
        extend  Navesti::Dialects::UkObie

        PERMISSIONS = (Navesti::Dialects::UkObie::PERMISSIONS - %w[ReadDirectDebits]).freeze

        def self.provider_label = "Revolut"
      end
    end
  end
end
