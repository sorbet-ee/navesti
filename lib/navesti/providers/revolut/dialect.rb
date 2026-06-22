# frozen_string_literal: true

module Navesti
  module Providers
    module Revolut
      # The Revolut (UK OBIE) bank dialect. Revolut and Wise are both UK OBIE, so
      # this table is — by design — the same SHAPE as Wise::Dialect, with the same
      # vocabulary (OBIE status strings, Permissions, balance types). That this is
      # now the THIRD occurrence of these tables (Berlin Group at LHV, OBIE at Wise
      # + Revolut) is exactly the ADR-0004 "three-times" trigger to extract a
      # shared OBIE dialect (docs/14). Kept standalone here per "build straight
      # first"; the extraction is a deliberate follow-up, not a guess.
      module Dialect
        CONSENT_STATUS = {
          "AwaitingAuthorisation" => :received,
          "Authorised"            => :valid,
          "Rejected"              => :rejected,
          "Revoked"               => :revoked_by_psu,
          "Expired"               => :expired,
          "Consumed"              => :consumed
        }.freeze
        UNKNOWN_CONSENT_STATUS = :unknown

        PERMISSIONS = %w[
          ReadAccountsBasic ReadAccountsDetail ReadBalances
          ReadTransactionsBasic ReadTransactionsCredits ReadTransactionsDebits ReadTransactionsDetail
        ].freeze
        DEFAULT_PERMISSIONS = %w[ReadAccountsBasic ReadBalances].freeze

        AVAILABLE_BALANCE_TYPES = %w[InterimAvailable ClosingAvailable ForwardAvailable OpeningAvailable Expected].freeze
        BOOKED_BALANCE_TYPES    = %w[InterimBooked ClosingBooked OpeningBooked PreviouslyClosedBooked].freeze

        # OBIE domestic payment Status. As at Wise, a payment-order is POSTed
        # post-SCA, so every status but Rejected carries side_effect_possible: true.
        PAYMENT_STATUS = {
          "Pending"                           => { status: :pending_execution, safety_status: :pending,   side_effect_possible: true },
          "AcceptedSettlementInProcess"       => { status: :pending_execution, safety_status: :pending,   side_effect_possible: true },
          "AcceptedWithoutPosting"            => { status: :pending_execution, safety_status: :pending,   side_effect_possible: true },
          "AcceptedSettlementCompleted"       => { status: :confirmed,         safety_status: :confirmed, side_effect_possible: true },
          "AcceptedCreditSettlementCompleted" => { status: :confirmed,         safety_status: :confirmed, side_effect_possible: true },
          "Rejected"                          => { status: :rejected,          safety_status: :rejected,  side_effect_possible: false }
        }.freeze
        UNKNOWN_PAYMENT_STATUS = { status: :unknown, safety_status: :unknown, side_effect_possible: true }.freeze

        # Per-currency Reference limits (OBIE): EUR 35, GBP 18; creditor name ≤ 70.
        REFERENCE_MAX = { "GBP" => 18 }.freeze
        REFERENCE_DEFAULT_MAX = 35
        CREDITOR_NAME_MAX = 70

        module_function

        def consent_status(raw_status)
          CONSENT_STATUS.fetch(raw_status.to_s, UNKNOWN_CONSENT_STATUS)
        end

        def known_consent_status?(raw_status)
          CONSENT_STATUS.key?(raw_status.to_s)
        end

        def payment_status(raw_status, provider_reference: nil, raw: nil)
          mapping = PAYMENT_STATUS.fetch(raw_status.to_s, UNKNOWN_PAYMENT_STATUS)
          PaymentStatus.new(
            status: mapping[:status],
            safety_status: mapping[:safety_status],
            side_effect_possible: mapping[:side_effect_possible],
            raw_status: raw_status,
            provider_reference: provider_reference,
            raw: raw
          )
        end

        def known_payment_status?(raw_status)
          PAYMENT_STATUS.key?(raw_status.to_s)
        end

        def available_balance_type?(type)
          AVAILABLE_BALANCE_TYPES.include?(type.to_s)
        end

        def booked_balance_type?(type)
          BOOKED_BALANCE_TYPES.include?(type.to_s)
        end

        def debit?(credit_debit_indicator)
          credit_debit_indicator.to_s == "Debit"
        end

        # Host-side OBIE limits enforced before dialing: per-currency Reference
        # length, creditor name ≤ 70, IBAN-required.
        def validate_payment_order!(order)
          if order.creditor.iban.to_s.empty?
            raise ValidationError, "Revolut domestic payment requires a creditor IBAN"
          end

          reference = order.end_to_end_reference.to_s
          unless reference.empty?
            max = REFERENCE_MAX.fetch(order.money.currency, REFERENCE_DEFAULT_MAX)
            if reference.length > max
              raise ValidationError, "Revolut payment reference exceeds the #{max}-char limit for #{order.money.currency}"
            end
          end

          if order.creditor_name.to_s.length > CREDITOR_NAME_MAX
            raise ValidationError, "creditor name exceeds the OBIE #{CREDITOR_NAME_MAX}-char limit"
          end

          order
        end
      end
    end
  end
end
