# frozen_string_literal: true

module Navesti
  # A Strong Customer Authentication method the bank offers for a payment
  # (decoupled SCA *discovery* — LHV-2B). Surfacing the available methods is
  # read-only; actually starting a decoupled authorisation is deferred.
  #
  # LHV/Berlin Group examples: method_id "MID" (Mobile-ID), "SID" (Smart-ID),
  # "BIO" (Biometrics); authentication_type "SMS_OTP", "PUSH_OTP".
  class ScaMethod < ValueObject
    attribute :method_id
    attribute :authentication_type, required: false
    attribute :name, required: false

    private

    def validate
      raise ValidationError, "ScaMethod#method_id must be present" if method_id.to_s.empty?
    end
  end
end
