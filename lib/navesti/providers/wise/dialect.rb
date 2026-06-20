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

        module_function

        # Normalizes an OBIE consent Status into a symbol, preserving the raw
        # string on the Consent. Unknown values never map to :valid.
        def consent_status(raw_status)
          CONSENT_STATUS.fetch(raw_status.to_s, UNKNOWN_CONSENT_STATUS)
        end

        def known_consent_status?(raw_status)
          CONSENT_STATUS.key?(raw_status.to_s)
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
