# frozen_string_literal: true

module Navesti
  module Dialects
    # The UK OBIE (Open Banking 3.1.x) dialect: the tables + table-driven
    # normalizers shared by every OBIE bank (Wise, Revolut). Extracted under the
    # ADR-0004 three-times rule once the OBIE vocabulary appeared a second time
    # byte-for-byte identical — see docs/adr/0007. LHV is Berlin Group and keeps
    # its own dialect: this is deliberately ONE standard's vocabulary, not a
    # cross-standard merge. Raw strings are always preserved on the value object
    # (docs/08); an unknown code never collapses to a safe value.
    #
    # A provider dialect adopts it with BOTH `include` (so the tables are
    # reachable as `Dialect::CONSTANT`) and `extend` (so the normalizers are
    # callable as `Dialect.consent_status`), declares its #provider_label, and
    # overrides only what differs:
    #
    #   module Dialect
    #     include Navesti::Dialects::UkObie
    #     extend  Navesti::Dialects::UkObie
    #     def self.provider_label = "Wise"
    #   end
    module UkObie
      # OBIE account-access-consent Status => Navesti's shared consent symbol.
      # AwaitingAuthorisation => :received (created, not yet authorised);
      # Authorised => :valid.
      CONSENT_STATUS = {
        "AwaitingAuthorisation" => :received,
        "Authorised"            => :valid,
        "Rejected"              => :rejected,
        "Revoked"               => :revoked_by_psu,
        "Expired"               => :expired,
        "Consumed"              => :consumed
      }.freeze
      # An unmapped consent status is never treated as authorised (docs/08 rule 1).
      UNKNOWN_CONSENT_STATUS = :unknown

      # The full OBIE AISP permission set (OBReadConsent1 Data.Permissions). A
      # bank whose registration omits one overrides PERMISSIONS (e.g. Revolut
      # drops ReadDirectDebits).
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
      # The smallest set granting accounts + balances — the default for a
      # balance-reading consent.
      DEFAULT_PERMISSIONS = %w[ReadAccountsBasic ReadBalances].freeze

      # OBIE OBReadBalance1 Type values, classified into available vs booked. All
      # raw entries are preserved regardless; this only decides which is which.
      AVAILABLE_BALANCE_TYPES = %w[InterimAvailable ClosingAvailable ForwardAvailable OpeningAvailable Expected].freeze
      BOOKED_BALANCE_TYPES    = %w[InterimBooked ClosingBooked OpeningBooked PreviouslyClosedBooked].freeze

      # OBIE domestic payment-order Status => normalized PaymentStatus facts. A
      # payment-order is POSTed *after* the consent's SCA, so the instruction is
      # already committed — every status except an explicit Rejected carries
      # side_effect_possible: true. Do not "simplify" this to false (docs/08).
      PAYMENT_STATUS = {
        "Pending"                           => { status: :pending_execution, safety_status: :pending,   side_effect_possible: true },
        "AcceptedSettlementInProcess"       => { status: :pending_execution, safety_status: :pending,   side_effect_possible: true },
        "AcceptedWithoutPosting"            => { status: :pending_execution, safety_status: :pending,   side_effect_possible: true },
        "AcceptedSettlementCompleted"       => { status: :confirmed,         safety_status: :confirmed, side_effect_possible: true },
        "AcceptedCreditSettlementCompleted" => { status: :confirmed,         safety_status: :confirmed, side_effect_possible: true },
        "Rejected"                          => { status: :rejected,          safety_status: :rejected,  side_effect_possible: false }
      }.freeze
      # Unknown payment codes are never safe by default (docs/08 rule 1).
      UNKNOWN_PAYMENT_STATUS = { status: :unknown, safety_status: :unknown, side_effect_possible: true }.freeze

      # The payment Reference length limit varies by currency (OBIE): 35 chars
      # default, 18 for GBP. CreditorAccount.Name is capped at 70.
      REFERENCE_MAX = { "GBP" => 18 }.freeze
      REFERENCE_DEFAULT_MAX = 35
      CREDITOR_NAME_MAX = 70

      # Normalizes an OBIE consent Status into a symbol; unknown never -> :valid.
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

      def available_balance_type?(type)
        AVAILABLE_BALANCE_TYPES.include?(type.to_s)
      end

      def booked_balance_type?(type)
        BOOKED_BALANCE_TYPES.include?(type.to_s)
      end

      # OBIE amounts are unsigned with a CreditDebitIndicator; a Debit balance is
      # negative. The mapper applies the sign — this is the classifier.
      def debit?(credit_debit_indicator)
        credit_debit_indicator.to_s == "Debit"
      end

      # Deterministic OBIE limits enforced host-side before dialing: the
      # per-currency Reference length and the 70-char creditor name, plus an
      # IBAN-required creditor. Messages carry the adopting bank's #provider_label.
      def validate_payment_order!(order)
        if order.creditor.iban.to_s.empty?
          raise ValidationError, "#{provider_label} domestic payment requires a creditor IBAN"
        end

        reference = order.end_to_end_reference.to_s
        unless reference.empty?
          max = REFERENCE_MAX.fetch(order.money.currency, REFERENCE_DEFAULT_MAX)
          if reference.length > max
            raise ValidationError, "#{provider_label} payment reference exceeds the #{max}-char limit for #{order.money.currency}"
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
