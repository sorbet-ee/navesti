# frozen_string_literal: true

module Navesti
  # The three-layer normalized payment status (docs/08-status-normalization.md):
  #
  #   raw_status  -> status (rich) -> safety_status + side_effect_possible
  #
  # `status` is Navesti's expressive vocabulary; `safety_status` is the minimal
  # contract Sorbet-Core acts on; `side_effect_possible` is the double-spend
  # axis and is NOT uniform across :pending.
  class PaymentStatus < ValueObject
    SAFETY = %i[confirmed rejected pending ambiguous unknown].freeze
    SIDE_EFFECT = [true, false, :unknown].freeze

    attribute :status
    attribute :safety_status
    attribute :side_effect_possible
    attribute :raw_status, required: false
    attribute :provider_reference, required: false
    attribute :reason_code, required: false
    attribute :reason_message, required: false
    attribute :raw, required: false

    def confirmed? = safety_status == :confirmed
    def rejected? = safety_status == :rejected
    def pending? = safety_status == :pending
    def ambiguous? = safety_status == :ambiguous

    private

    def validate
      unless status.is_a?(Symbol)
        raise ValidationError, "PaymentStatus#status must be a Symbol, got #{status.inspect}"
      end
      unless SAFETY.include?(safety_status)
        raise ValidationError,
              "PaymentStatus#safety_status must be one of #{SAFETY.join(', ')}, got #{safety_status.inspect}"
      end
      unless SIDE_EFFECT.include?(side_effect_possible)
        raise ValidationError,
              "PaymentStatus#side_effect_possible must be true, false, or :unknown, got #{side_effect_possible.inspect}"
      end
    end
  end
end
