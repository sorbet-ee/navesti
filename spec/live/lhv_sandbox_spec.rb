# frozen_string_literal: true

# Opt-in live sandbox tests. These hit the real LHV sandbox over mTLS and run
# ONLY when LHV_LIVE=1 (see spec_helper + docs/12). CI never runs them.
#
#   LHV_LIVE=1 \
#   LHV_CLIENT_CERT_PATH=certs/lhv_sandbox.crt \
#   LHV_CLIENT_KEY_PATH=certs/lhv_sandbox.key \
#   LHV_CA_CHAIN_PATH=certs/lhv_sandbox_chain.pem \
#   bundle exec rspec spec/live/lhv_sandbox_spec.rb
#
# Uses the documented sandbox preset bearer token so no OAuth redirect is
# needed to exercise the data calls.
RSpec.describe "LHV sandbox (live)", :live do
  let(:credentials) { Navesti::Credentials.from_env }
  let(:adapter) { Navesti.adapter(:lhv, credentials: credentials, env: :sandbox) }

  it "verifies the TPP over mTLS and recognizes the certificate identity" do
    result = adapter.tpp_verification
    expect(result.access).to be_in(%i[enabled blocked])
    expect(result.tpp_id).to match(/\APSDEE-LHVTEST-/)
  end

  it "lists accounts with the preset sandbox bearer token" do
    accounts = adapter.accounts_list(access_token: "Liis-MariMnnik")
    expect(accounts).not_to be_empty
    expect(accounts.first.iban).to start_with("EE")
    # Multi-currency container — currency may be "XXX".
    expect(accounts.first.provider_reported_currency).to be_a(String).or be_nil
  end

  it "reads balances for a returned account (consent-gated; skips if not permitted)" do
    accounts = adapter.accounts_list(access_token: "Liis-MariMnnik")
    account = accounts.first

    begin
      balances = adapter.balances(access_token: "Liis-MariMnnik", account_id: account.provider_account_id)
    rescue Navesti::ConsentError, Navesti::ProviderError => e
      skip "balances need an AIS consent the sandbox token lacks: #{e.message}"
    end

    expect(balances).to be_an(Array)
    balances.each do |bal|
      expect(bal.currency).to match(/\A[A-Z]{3}\z/) # real currency, not "XXX"
      expect(bal.available_amount_minor || bal.booked_amount_minor).to be_a(Integer)
    end
  end

  it "initiates a SEPA payment between the customer's own accounts (ACSC exemption)" do
    order = Navesti::PaymentOrder.new(
      money: Navesti::Money.new(amount_minor: 1_00, currency: "EUR"),
      debtor: Navesti::AccountRef.iban("EE717700771001735865"),
      creditor: Navesti::AccountRef.iban("EE277700771001735881"),
      creditor_name: "Liis-Mari Mannik",
      remittance_information: "navesti live test",
      idempotency_key: "live-#{Time.now.utc.to_i}"
    )
    submission = adapter.initiate_sepa_payment(
      order: order, access_token: "Liis-MariMnnik", redirect_uri: "https://localhost/callback"
    )
    expect(submission.provider_reference).not_to be_nil
    # Own-account exemption is expected to confirm immediately; if SCA is
    # required instead, we still get a valid pending submission.
    expect(submission.safety_status).to be_in(%i[confirmed pending])
  end
end
