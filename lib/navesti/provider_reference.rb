# frozen_string_literal: true

module Navesti
  # A typed wrapper for a bank's identifier of a resource, so references are
  # never bare strings confused across banks. It is the join key of the whole
  # system (correlating submissions, polls, webhooks) — typos here are silent
  # data corruption, which is why it is typed (docs/02-domain-model.md).
  class ProviderReference < ValueObject
    KINDS = %i[payment consent account transaction event authorisation].freeze

    attribute :value
    attribute :kind
    attribute :connector

    private

    def validate
      unless KINDS.include?(kind)
        raise ValidationError, "ProviderReference#kind must be one of #{KINDS.join(', ')}, got #{kind.inspect}"
      end
      raise ValidationError, "ProviderReference#value must be non-empty" if value.to_s.empty?
    end
  end
end
