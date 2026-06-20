# frozen_string_literal: true

module Navesti
  module Providers
    module Wise
      # The Wise (UK OBIE) bank dialect: the compact, declarative description of
      # what Wise's codes *mean*, normalized to Navesti's shared vocabulary so a
      # host treats "consent authorised" identically across banks. Raw strings
      # are always preserved on the value object (docs/08).
      #
      # Mirrors LHV::Dialect deliberately — the parts that come out identical
      # here are the evidence for a future shared table/DSL
      # (docs/14-semantic-compression-and-the-connector-layer.md). The OBIE
      # *vocabulary* differs (CamelCase Status, Permissions list); the *shape*
      # (raw code -> normalized symbol, "unknown never collapses to valid") does
      # not.
      module Dialect
        # OBIE account-access-consent Status => Navesti's shared consent symbol.
        # AwaitingAuthorisation maps to :received (created, not yet authorised) so
        # it reads the same as LHV's "received"; Authorised maps to :valid.
        CONSENT_STATUS = {
          "AwaitingAuthorisation" => :received,
          "Authorised"            => :valid,
          "Rejected"              => :rejected,
          "Revoked"               => :revoked_by_psu,
          "Expired"               => :expired,
          "Consumed"              => :consumed
        }.freeze

        # An unmapped consent status is never treated as authorised: :unknown,
        # never :valid (docs/08 rule 1). The raw string is preserved on Consent.
        UNKNOWN_CONSENT_STATUS = :unknown

        # The OBIE AISP permission strings (OBReadConsent1 Data.Permissions).
        # The host requests a subset; balances/transactions require their reads.
        PERMISSIONS = %w[
          ReadAccountsBasic
          ReadAccountsDetail
          ReadBalances
          ReadTransactionsBasic
          ReadTransactionsCredits
          ReadTransactionsDebits
          ReadTransactionsDetail
          ReadDirectDebits
        ].freeze

        # The smallest permission set that grants accounts + balances — the
        # default for a balance-reading consent (parallels LHV's
        # "allAccountsWithBalances").
        DEFAULT_PERMISSIONS = %w[ReadAccountsBasic ReadBalances].freeze

        # OBIE OBReadBalance1 Type values, classified into the two facts the
        # Balance carries. All raw entries are preserved regardless; this only
        # decides which becomes available vs booked.
        AVAILABLE_BALANCE_TYPES = %w[InterimAvailable ClosingAvailable ForwardAvailable OpeningAvailable Expected].freeze
        BOOKED_BALANCE_TYPES    = %w[InterimBooked ClosingBooked OpeningBooked PreviouslyClosedBooked].freeze

        # OBIE domestic payment-order Status => normalized PaymentStatus facts.
        #
        # The double-spend boundary differs from LHV: a Wise payment-order is
        # POSTed *after* the consent's SCA, so the instruction is already
        # committed — every status except an explicit Rejected carries
        # side_effect_possible: true. Do not "simplify" this to false.
        PAYMENT_STATUS = {
          "Pending"                           => { status: :pending_execution, safety_status: :pending,   side_effect_possible: true },
          "AcceptedSettlementInProcess"       => { status: :pending_execution, safety_status: :pending,   side_effect_possible: true },
          "AcceptedWithoutPosting"            => { status: :pending_execution, safety_status: :pending,   side_effect_possible: true },
          "AcceptedSettlementCompleted"       => { status: :confirmed,         safety_status: :confirmed, side_effect_possible: true },
          "AcceptedCreditSettlementCompleted" => { status: :confirmed,         safety_status: :confirmed, side_effect_possible: true },
          "Rejected"                          => { status: :rejected,          safety_status: :rejected,  side_effect_possible: false }
        }.freeze

        # Unknown payment codes are never safe by default: unknown + side-effect
        # possible, never rejected (docs/08 rule 1).
        UNKNOWN_PAYMENT_STATUS = { status: :unknown, safety_status: :unknown, side_effect_possible: true }.freeze

        # The payment Reference length limit varies by currency (Wise OB docs):
        # 35 chars for EUR, 18 for GBP. CreditorAccount.Name is capped at 70.
        REFERENCE_MAX = { "GBP" => 18 }.freeze
        REFERENCE_DEFAULT_MAX = 35
        CREDITOR_NAME_MAX = 70

        module_function

        # Normalizes an OBIE consent Status into a symbol, preserving the raw
        # string on the Consent. Unknown values never map to :valid.
        def consent_status(raw_status)
          CONSENT_STATUS.fetch(raw_status.to_s, UNKNOWN_CONSENT_STATUS)
        end

        def known_consent_status?(raw_status)
          CONSENT_STATUS.key?(raw_status.to_s)
        end

        # Normalizes an OBIE payment Status into a PaymentStatus, preserving the
        # raw code. Unknown codes never collapse to a safe value.
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

        # Deterministic, well-established OBIE limits enforced host-side before
        # dialing: the per-currency Reference length and the 70-char creditor
        # name. A domestic payment also needs an IBAN creditor (our AccountRef is
        # IBAN-based). Charset / sort-code rules are left to the bank.
        def validate_payment_order!(order)
          if order.creditor.iban.to_s.empty?
            raise ValidationError, "Wise domestic payment requires a creditor IBAN"
          end

          reference = order.end_to_end_reference.to_s
          unless reference.empty?
            max = REFERENCE_MAX.fetch(order.money.currency, REFERENCE_DEFAULT_MAX)
            if reference.length > max
              raise ValidationError, "Wise payment reference exceeds the #{max}-char limit for #{order.money.currency}"
            end
          end

          if order.creditor_name.to_s.length > CREDITOR_NAME_MAX
            raise ValidationError, "creditor name exceeds the OBIE #{CREDITOR_NAME_MAX}-char limit"
          end

          order
        end

        def available_balance_type?(type)
          AVAILABLE_BALANCE_TYPES.include?(type.to_s)
        end

        def booked_balance_type?(type)
          BOOKED_BALANCE_TYPES.include?(type.to_s)
        end

        # OBIE amounts are unsigned with a CreditDebitIndicator; a Debit balance
        # is negative. The mapper applies the sign — this is the classifier.
        def debit?(credit_debit_indicator)
          credit_debit_indicator.to_s == "Debit"
        end
      end
    end
  end
end
