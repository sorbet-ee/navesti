# frozen_string_literal: true

module Navesti
  # A render-free descriptor of a step that needs the PSU or the bank's UI
  # (docs/04-interaction-descriptors.md). Navesti returns descriptors;
  # Sorbet-Cockpit renders UX; the bank renders SCA. Navesti renders nothing.
  class Interaction < ValueObject
    TYPES = %i[redirect app_redirect decoupled qr poll none].freeze

    attribute :type
    attribute :provider_reference, required: false
    attribute :url, required: false
    attribute :expires_at, required: false
    attribute :state, required: false
    attribute :poll_after, required: false
    attribute :polling_url, required: false
    attribute :method_id, required: false
    attribute :qr_payload, required: false
    attribute :raw, required: false

    def self.none
      new(type: :none)
    end

    private

    def validate
      unless TYPES.include?(type)
        raise ValidationError, "Interaction#type must be one of #{TYPES.join(', ')}, got #{type.inspect}"
      end
      if %i[redirect app_redirect].include?(type) && url.to_s.empty?
        raise ValidationError, "Interaction#url is required for #{type}"
      end
      if type == :qr && qr_payload.to_s.empty?
        raise ValidationError, "Interaction#qr_payload is required for :qr"
      end
    end
  end
end
