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

        # Berlin Group balanceType values, classified into the two facts the
        # BalanceProvider port carries. All raw entries are preserved on the
        # Balance regardless; this only decides which becomes available/booked.
        AVAILABLE_BALANCE_TYPES = %w[interimAvailable forwardAvailable expected authorised].freeze
        BOOKED_BALANCE_TYPES    = %w[closingBooked interimBooked openingBooked].freeze

        # Deterministic, well-established SEPA constraints we can enforce
        # host-side before dialing the bank. Charset, IBAN checksum, and date
        # rules are intentionally NOT enforced here (false-rejection risk); the
        # bank enforces those. See docs/12 / swagger-notes.
        CREDITOR_NAME_MAX = 70   # SEPA creditor name
        REMITTANCE_MAX    = 140  # SEPA unstructured remittance
        SEPA_RAILS        = %i[sepa_credit_transfer sepa_instant].freeze

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

        # Validates a PaymentOrder against the SEPA constraints LHV enforces,
        # raising ValidationError before any bank call. Deterministic only —
        # not a substitute for bank-side validation, but it turns predictable
        # user errors into clear local failures instead of bank rejections.
        def validate_payment_order!(order)
          if SEPA_RAILS.include?(order.rail) && order.money.currency != "EUR"
            raise ValidationError, "LHV SEPA requires EUR, got #{order.money.currency}"
          end
          if order.creditor_name.to_s.length > CREDITOR_NAME_MAX
            raise ValidationError, "creditorName exceeds the SEPA #{CREDITOR_NAME_MAX}-char limit"
          end
          if order.remittance_information.to_s.length > REMITTANCE_MAX
            raise ValidationError, "remittanceInformationUnstructured exceeds the SEPA #{REMITTANCE_MAX}-char limit"
          end

          order
        end

        def available_balance_type?(type)
          AVAILABLE_BALANCE_TYPES.include?(type.to_s)
        end

        def booked_balance_type?(type)
          BOOKED_BALANCE_TYPES.include?(type.to_s)
        end
      end
    end
  end
end
