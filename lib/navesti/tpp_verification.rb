# frozen_string_literal: true

module Navesti
  # Normalized result of a TPP registration/verification check
  # (LHV: GET /v1/tpp-verification). The first smoke test that mTLS works,
  # the certificate identity is recognized, and which roles are enabled.
  class TppVerification < ValueObject
    ACCESS = %i[enabled blocked invalid_certificate unknown].freeze

    attribute :provider
    attribute :access
    attribute :tpp_id, required: false
    attribute :name, required: false
    attribute :roles, default: []
    attribute :raw, required: false

    def enabled? = access == :enabled

    private

    def validate
      unless ACCESS.include?(access)
        raise ValidationError, "TppVerification#access must be one of #{ACCESS.join(', ')}, got #{access.inspect}"
      end
    end
  end
end
