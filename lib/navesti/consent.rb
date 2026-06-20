# frozen_string_literal: true

module Navesti
  # An AIS consent the PSU granted the TPP (LHV: POST /v1/consents and
  # GET /v1/consents/{id}/status). Read Balances and the consent-gated accounts
  # list require a Consent-ID; without it the only accounts call that works is
  # the no-consent /v1/accounts-list, whose "basic" Account schema has no
  # resourceId — so balances resolves to a malformed path (FORMAT_ERROR).
  #
  # Navesti stays stateless: it returns the Consent (with the consentId the host
  # needs) and forgets it. The host holds the consent_id and supplies it to the
  # consent-gated calls. status follows the Berlin Group consent lifecycle
  # (received/rejected/valid/expired/revokedByPsu/terminatedByTpp); the dialect
  # preserves the raw string alongside the symbol.
  class Consent < ValueObject
    attribute :provider
    attribute :consent_id
    attribute :status                       # symbol from Dialect.consent_status
    attribute :raw_status, required: false # the bank's consentStatus string
    attribute :interaction, required: false # Navesti::Interaction (redirect SCA)
    attribute :sca_methods, default: []    # [Navesti::ScaMethod]
    attribute :valid_until, required: false
    attribute :recurring_indicator, required: false
    attribute :raw, required: false

    def requires_authorization? = !interaction.nil? && interaction.type != :none

    private

    def validate
      raise ValidationError, "Consent#provider must be present" if provider.to_s.empty?
      raise ValidationError, "Consent#consent_id must be present" if consent_id.to_s.empty?
      raise ValidationError, "Consent#status must be present" if status.nil?
    end
  end
end