# frozen_string_literal: true

require "json"
require "uri"
require "securerandom"
require "digest"

module Navesti
  module Providers
    module LHV
      # The LHV adapter: a thin set of explicit, ordered operations over the
      # LHV PSD2 / Berlin Group interface. No flow engine (docs/06, docs/13 Q4)
      # — the "flow" is the documented calling order:
      #
      #   tpp_verification
      #   authorize_url -> (PSU at bank) -> exchange_code
      #   accounts_list
      #   initiate_sepa_payment -> (redirect SCA) -> payment_status
      #
      # Stateless: every call takes what it needs as arguments. Persists
      # nothing; returns normalized facts with raw evidence.
      class Adapter
        include Adapters::ErrorGuard # guard_response! / guard_oauth_response! / raise_provider_error!
        include Adapters::Headers    # bearer_headers

        attr_reader :config, :credentials

        def initialize(credentials:, env: :sandbox, http: HTTP::Client.new, request_id: nil)
          @credentials = credentials
          @config = Config.new(env: env)
          @http = http
          @request_id = request_id || -> { SecureRandom.uuid }
        end

        # GET /v1/tpp-verification — the first smoke test (mTLS + identity).
        # Returns TppVerification for any recognizable response (ENABLED,
        # BLOCKED, certificate-invalid); does not treat BLOCKED/invalid as an
        # exception — they are facts the caller acts on.
        def tpp_verification
          response = @http.request(
            method: :get,
            url: config.tpp_verification_url,
            headers: base_headers,
            credentials: credentials
          )
          Mappers.tpp_verification(response)
        end

        # Builds the OAuth authorization redirect. URL construction only — no
        # HTTP, no UI. Returns an Interaction descriptor; the host presents it,
        # the bank renders SCA (docs/04).
        def authorize_url(redirect_uri:, state:, scope: "psd2")
          url = config.oauth_authorize_url(
            client_id: client_id,
            redirect_uri: redirect_uri,
            state: state,
            scope: scope
          )
          Interaction.new(type: :redirect, url: url, state: state)
        end

        # POST /oauth/token (authorization_code) — exchanges the code for a
        # token pair. Always mints a new pair. Navesti returns the Token to the
        # host and forgets it; refresh/revoke are deferred (docs/10).
        def exchange_code(code:, redirect_uri:)
          body = URI.encode_www_form(
            client_id: client_id,
            grant_type: "authorization_code",
            code: code,
            redirect_uri: redirect_uri
          )
          response = @http.request(
            method: :post,
            url: config.oauth_token_url,
            headers: base_headers("Content-Type" => "application/x-www-form-urlencoded"),
            body: body,
            credentials: credentials
          )
          guard_oauth_response!(response)
          Mappers.token(response)
        end

        # GET /v1/accounts-list (no-consent) or GET /v1/accounts (consent-gated).
        # Returns [Account]. When `consent_id` is present, hits the consent-gated
        # /v1/accounts (Consent-ID header) — that path returns the full
        # AccountResponse schema with resourceId, which is what Read Balances
        # needs. Without it, falls back to the no-consent basic list (no
        # resourceId; balances then resolve via the bank-supplied balances href).
        def accounts_list(access_token:, only_active: true, psu_corporate_id: nil, consent_id: nil)
          headers = bearer_headers(access_token)
          headers["PSU-Corporate-ID"] = psu_corporate_id if psu_corporate_id
          headers["Consent-ID"] = consent_id if consent_id
          url = consent_id ? config.accounts_with_consent_url(only_active: only_active)
                            : config.accounts_list_url(only_active: only_active)
          response = @http.request(
            method: :get,
            url: url,
            headers: headers,
            credentials: credentials
          )
          guard_response!(response)
          Mappers.accounts(response)
        end

        # POST /v1/consents → Navesti::Consent.
        #
        # Creates an AIS consent granting balances on all accounts. LHV's
        # AccessReference.availableAccounts is an enum: "allAccounts" grants only
        # the account LIST, "allAccountsWithBalances" grants the list AND
        # balances (OpenAPI-verified). The latter is required so Read Balances
        # resolves — "allAccounts" alone makes balances return FORMAT_ERROR
        # (the consent does not cover the balances resource). The PSU authorizes
        # via the redirect SCA in _links.scaRedirect (host opens it; PSU completes
        # SCA at LHV; consent moves received → valid). The host holds the
        # returned consentId and supplies it to consent-gated calls.
        #
        # `valid_until` is a required host-supplied ISO date string (YYYY-MM-DD)
        # — the gem stays deterministic: no Date.today here.
        def create_consent(access_token:, valid_until:, redirect_uri:,
                           recurring_indicator: false, frequency_per_day: 4,
                           combined_service_indicator: false, psu_corporate_id: nil,
                           psu_ip_address: "127.0.0.1")
          headers = bearer_headers(access_token).merge(
            "Content-Type" => "application/json",
            "TPP-Redirect-Preferred" => "true",
            "TPP-Redirect-URI" => redirect_uri,
            "PSU-IP-Address" => psu_ip_address
          )
          headers["PSU-Corporate-ID"] = psu_corporate_id if psu_corporate_id

          body = {
            "access" => { "availableAccounts" => "allAccountsWithBalances" },
            "recurringIndicator" => recurring_indicator,
            "validUntil" => valid_until,
            # Berlin Group: a one-off (non-recurring) consent must request exactly
            # one access per day. Coerce rather than trust the caller, so we never
            # send the invalid recurring=false + frequencyPerDay>1 combination.
            "frequencyPerDay" => recurring_indicator ? frequency_per_day : 1,
            "combinedServiceIndicator" => combined_service_indicator
          }
          response = @http.request(
            method: :post,
            url: config.consents_url,
            headers: headers,
            body: JSON.generate(body),
            credentials: credentials
          )
          guard_response!(response)
          Mappers.consent(response, config: config)
        end

        # GET /v1/consents/{consentId}/status → Navesti::Consent (status-only).
        # Poll after the PSU completes SCA; the consent moves received → valid.
        def consent_status(consent_id:, access_token:)
          response = @http.request(
            method: :get,
            url: config.consent_status_url(consent_id),
            headers: bearer_headers(access_token),
            credentials: credentials
          )
          guard_response!(response)
          Mappers.consent_status(response, consent_id: consent_id)
        end

        # GET /v1/accounts/{account_id}/balances → [Balance], one per currency.
        #
        # Consent-gated AIS service: unlike accounts-list, Read Balances needs a
        # valid AIS consent. The host supplies `consent_id` (sent as Consent-ID);
        # the consent-creation flow is a later phase. Pass `balances_href` (e.g.
        # account._links.balances.href from accounts-list) to follow the bank's
        # own link instead of the built path.
        def balances(access_token:, account_id:, balances_href: nil, consent_id: nil, psu_corporate_id: nil)
          headers = bearer_headers(access_token)
          headers["Consent-ID"] = consent_id if consent_id
          headers["PSU-Corporate-ID"] = psu_corporate_id if psu_corporate_id

          url = balances_href ? config.absolute(balances_href) : config.account_balances_url(account_id)
          response = @http.request(method: :get, url: url, headers: headers, credentials: credentials)
          guard_response!(response)
          Mappers.balances(response, provider_account_id: account_id)
        end

        # POST /oauth/token (refresh_token) — mints a fresh access token from a
        # refresh token. Stateless: the host owns token lifecycle/storage;
        # Navesti only performs the exchange and returns the Token (docs/10).
        def refresh_token(refresh_token:)
          body = URI.encode_www_form(
            client_id: client_id,
            grant_type: "refresh_token",
            refresh_token: refresh_token
          )
          response = @http.request(
            method: :post,
            url: config.oauth_token_url,
            headers: base_headers("Content-Type" => "application/x-www-form-urlencoded"),
            body: body,
            credentials: credentials
          )
          guard_oauth_response!(response)
          Mappers.token(response)
        end

        # POST /v1.1/payments/sepa-credit-transfers (JSON). Returns a
        # PaymentSubmission: a redirect interaction when SCA is required, or a
        # confirmed status when an SCA exemption applied (no scaRedirect).
        def initiate_sepa_payment(order:, access_token:, redirect_uri:, nok_redirect_uri: nil, psu_corporate_id: nil)
          Dialect.validate_payment_order!(order) # local SEPA checks before dialing

          headers = bearer_headers(access_token).merge(
            "Content-Type" => "application/json",
            "TPP-Redirect-Preferred" => "true",
            "TPP-Redirect-URI" => redirect_uri
          )
          headers["TPP-Nok-Redirect-URI"] = nok_redirect_uri if nok_redirect_uri
          headers["PSU-Corporate-ID"] = psu_corporate_id if psu_corporate_id
          # Stable, bank-visible correlation id derived from the host's
          # idempotency key, so a retry reuses the same X-Request-ID. NOTE: LHV's
          # JSON SEPA API documents NO idempotency mechanism — this provides
          # correlation (and dedup only if LHV rejects duplicate request ids),
          # NOT a guarantee. After an ambiguous outcome the host MUST reconcile
          # via payment status before retrying (docs/08, docs/12).
          if order.idempotency_key
            headers["X-Request-ID"] = self.class.deterministic_request_id(order.idempotency_key)
          end

          response = @http.request(
            method: :post,
            url: config.sepa_payment_url,
            headers: headers,
            body: JSON.generate(payment_body(order)),
            credentials: credentials
          )
          guard_response!(response)
          Mappers.payment_submission(response, config: config, idempotency_key: order.idempotency_key)
        end

        # RFC 4122 v5 UUID derived from a fixed namespace + seed, so the same
        # idempotency key always yields the same X-Request-ID across retries.
        def self.deterministic_request_id(seed)
          digest = Digest::SHA1.digest("navesti-lhv-idempotency\x00#{seed}")
          bytes = digest[0, 16].bytes
          bytes[6] = (bytes[6] & 0x0f) | 0x50 # version 5
          bytes[8] = (bytes[8] & 0x3f) | 0x80 # variant 10xx
          hex = bytes.map { |b| format("%02x", b) }.join
          "#{hex[0, 8]}-#{hex[8, 4]}-#{hex[12, 4]}-#{hex[16, 4]}-#{hex[20, 12]}"
        end

        # GET /v1.1/payments/sepa-credit-transfers/{paymentId}/status
        def payment_status(payment_id:, access_token:)
          response = @http.request(
            method: :get,
            url: config.payment_status_url(payment_id),
            headers: bearer_headers(access_token),
            credentials: credentials
          )
          guard_response!(response)
          Mappers.payment_status(response, payment_id: payment_id)
        end

        # DELETE /v1.1/payments/sepa-credit-transfers/{paymentId}/cancel
        #
        # Cancels a bank-side initiation — valid only before the PSU completes
        # SCA (RCVD/RVCD). Useful for abandonment: if the PSU walks away from
        # the redirect, the host can cancel here before retrying elsewhere.
        # Returns a cancelled PaymentStatus; if SCA already completed, the bank
        # rejects and this raises (ProviderError) — the caller must not assume
        # cancellation succeeded.
        def cancel_payment(payment_id:, access_token:)
          response = @http.request(
            method: :delete,
            url: config.payment_cancel_url(payment_id),
            headers: bearer_headers(access_token),
            credentials: credentials
          )
          guard_response!(response)
          Mappers.cancellation(response, payment_id: payment_id)
        end

        # POST /oauth/revoke — revokes an access or refresh token. Idempotent:
        # revoking a nonexistent token still succeeds (LHV returns 200). The host
        # owns token lifecycle; Navesti just performs the revocation. Returns
        # true on success; raises on auth/validation failure.
        def revoke_token(token:, token_type_hint: nil)
          form = { client_id: client_id, token: token }
          form[:token_type_hint] = token_type_hint if token_type_hint
          response = @http.request(
            method: :post,
            url: config.oauth_revoke_url,
            headers: base_headers("Content-Type" => "application/x-www-form-urlencoded"),
            body: URI.encode_www_form(form),
            credentials: credentials
          )
          guard_oauth_response!(response)
          true
        end

        private

        def client_id
          @client_id ||= credentials.resolve_tpp_id
        end

        # The Berlin Group / LHV SEPA JSON body. amount_minor -> decimal string
        # via the currency exponent (never *100); debtorAccount is included
        # (optional at LHV, required by our Phase 1 PaymentOrder).
        #
        # NOTE: order.end_to_end_reference is intentionally NOT sent — LHV's
        # documented JSON SEPA schema has no endToEndIdentification field (its
        # remittanceInformationStructured is a different concept, the Estonian
        # creditor reference). It is preserved on the order for the host's own
        # reconciliation. Revisit if LHV confirms support (docs/12).
        def payment_body(order)
          body = {
            "instructedAmount" => {
              "currency" => order.money.currency,
              "amount" => order.money.to_decimal_string
            },
            "debtorAccount" => { "iban" => order.debtor.iban },
            "creditorName" => order.creditor_name,
            "creditorAccount" => { "iban" => order.creditor.iban }
          }
          if order.remittance_information
            body["remittanceInformationUnstructured"] = order.remittance_information
          end
          body
        end

        def base_headers(extra = {})
          { "X-Request-ID" => @request_id.call, "Accept" => "application/json" }.merge(extra)
        end

        # Hooks for Adapters::ErrorGuard. LHV is Berlin Group: the error code
        # lives in tppMessages[ category == "ERROR" ].code.
        #
        # NB: a Berlin Group error message always carries a `code` (it is a
        # required field), so the only divergence from the pre-substrate adapter
        # — an ERROR message with NO code falling through to the generic
        # "request failed" instead of "error " (blank) — is unreachable in
        # practice and an accepted, cleaner normalization (reviewed 2026-06).
        def provider_label
          "LHV"
        end

        def provider_error_code(body)
          (body["tppMessages"] || []).find { |m| m["category"] == "ERROR" }&.dig("code")
        end
      end
    end
  end
end
