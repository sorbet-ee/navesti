# frozen_string_literal: true

module Navesti
  # The fact that a payment order was submitted to a bank — the primary output
  # of connectivity dispatch (docs/03-sorbet-core-boundary.md). Wraps the
  # normalized PaymentStatus plus the interaction (when SCA is required) and
  # the URLs the host needs to advance or poll.
  class PaymentSubmission < ValueObject
    attribute :status                       # Navesti::PaymentStatus
    attribute :provider_reference, required: false  # Navesti::ProviderReference(:payment)
    attribute :interaction, required: false # Navesti::Interaction (e.g. redirect for SCA)
    attribute :status_url, required: false
    attribute :authorisation_url, required: false
    attribute :idempotency_key, required: false
    attribute :submitted_at, required: false
    attribute :raw, required: false

    # Convenience delegators to the safety axis (docs/08).
    def safety_status = status.safety_status
    def side_effect_possible = status.side_effect_possible
    def requires_authorization? = !interaction.nil? && interaction.type != :none

    private

    def validate
      raise ValidationError, "PaymentSubmission#status must be a Navesti::PaymentStatus" unless status.is_a?(PaymentStatus)
    end
  end
end
