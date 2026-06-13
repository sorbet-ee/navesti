# frozen_string_literal: true

module Navesti
  module Providers
    module LHV
      # The LHV bank dialect: the compact, declarative description of what LHV's
      # codes *mean*. This is the OMeta/STEPS idea applied — the status table is
      # the dialect's productions, mapping raw bank codes to normalized facts.
      #
      # Two transformations live here (docs/08-status-normalization.md):
      #   raw bank code -> rich status + side_effect_possible   (LHV-specific)
      #   rich status   -> safety_status                        (shared default)
      module Dialect
        # raw_status => { status:, safety_status:, side_effect_possible: }
        #
        # The double-spend boundary: RCVD/RVCD are pre-SCA (side_effect false),
        # ACSP is post-SCA (side_effect true). Do not "simplify" this.
        STATUS = {
          "RCVD" => { status: :requires_authorization,         safety_status: :pending,   side_effect_possible: false },
          "RVCD" => { status: :requires_authorization,         safety_status: :pending,   side_effect_possible: false },
          "PATC" => { status: :partially_authorized,           safety_status: :pending,   side_effect_possible: false },
          "ACSP" => { status: :pending_execution,              safety_status: :pending,   side_effect_possible: true },
          "ACWC" => { status: :pending_execution_with_warning, safety_status: :pending,   side_effect_possible: true },
          "ACSC" => { status: :confirmed,                      safety_status: :confirmed, side_effect_possible: true },
          "RJCT" => { status: :rejected,                       safety_status: :rejected,  side_effect_possible: false },
          "CANC" => { status: :cancelled,                      safety_status: :rejected,  side_effect_possible: false },
          "PDNG" => { status: :pending_xml_signature,          safety_status: :pending,   side_effect_possible: :unknown }
        }.freeze

        # Unknown bank codes are never safe by default: unknown + side-effect
        # possible, never rejected (docs/08 rule 1).
        UNKNOWN = { status: :unknown, safety_status: :unknown, side_effect_possible: true }.freeze

        # tpp-verification "access" string => normalized symbol. Invalid-cert is
        # derived from tppMessages (see Mappers), not from this map.
        ACCESS = {
          "ENABLED" => :enabled,
          "BLOCKED" => :blocked
        }.freeze

        module_function

        # Normalizes an LHV transactionStatus into a PaymentStatus, preserving
        # the raw code and any reason/provider reference.
        def payment_status(raw_status, provider_reference: nil, reason_code: nil, reason_message: nil, raw: nil)
          mapping = STATUS.fetch(raw_status.to_s, UNKNOWN)
          PaymentStatus.new(
            status: mapping[:status],
            safety_status: mapping[:safety_status],
            side_effect_possible: mapping[:side_effect_possible],
            raw_status: raw_status,
            provider_reference: provider_reference,
            reason_code: reason_code,
            reason_message: reason_message,
            raw: raw
          )
        end

        def known_status?(raw_status)
          STATUS.key?(raw_status.to_s)
        end

        def access(access_string)
          ACCESS.fetch(access_string.to_s, :unknown)
        end
      end
    end
  end
end
