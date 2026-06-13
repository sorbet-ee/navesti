# frozen_string_literal: true

module Navesti
  # The normalized payment instruction Navesti receives from the host. Input
  # object — Navesti never creates or mutates one, and never originates from a
  # provider, so it carries no raw evidence (docs/02-domain-model.md).
  #
  # Sorbet-Core builds this from its money packet. Navesti does not know what a
  # packet is.
  class PaymentOrder < ValueObject
    attribute :money                 # Navesti::Money
    attribute :debtor                # Navesti::AccountRef (optional for LHV UI-selection, but required here for Phase 1)
    attribute :creditor              # Navesti::AccountRef
    attribute :creditor_name
    attribute :rail, default: :sepa_credit_transfer
    attribute :remittance_information, required: false
    attribute :end_to_end_reference, required: false
    attribute :requested_execution_date, required: false
    # Connector-level idempotency key, supplied by the host. Opaque to Navesti;
    # forwarded to the bank only where the dialect declares support.
    attribute :idempotency_key, required: false

    private

    def validate
      raise ValidationError, "PaymentOrder#money must be a Navesti::Money" unless money.is_a?(Money)
      raise ValidationError, "PaymentOrder#creditor must be a Navesti::AccountRef" unless creditor.is_a?(AccountRef)
      unless debtor.is_a?(AccountRef)
        raise ValidationError, "PaymentOrder#debtor must be a Navesti::AccountRef"
      end
      raise ValidationError, "PaymentOrder#creditor_name must be present" if creditor_name.to_s.empty?
      if money.amount_minor <= 0
        raise ValidationError, "PaymentOrder#money must be positive, got #{money.amount_minor}"
      end
    end
  end
end
