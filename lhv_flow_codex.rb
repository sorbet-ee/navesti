require 'json'
require 'rest-client'
require 'openssl'
require 'securerandom'
require_relative 'navesti'

LHV_FLOW = Navesti.flow 'lhv_flow_codex' do
  base_url = 'https://api.sandbox.lhv.eu/psd2/v1'
  cert_path = File.expand_path('./config/client-cert.pem')
  key_path  = File.expand_path('./config/client-key.pem')
  ca_path   = File.expand_path('./config/ca-chain.pem')

  ssl_opts = {
    ssl_client_cert: OpenSSL::X509::Certificate.new(File.read(cert_path)),
    ssl_client_key:  OpenSSL::PKey::RSA.new(File.read(key_path)),
    ssl_ca_file:     ca_path,
    verify_ssl:      false,
    ssl_version:     'TLSv1_2'
  }

  step :create_oauth_authorization do |input, _|
    url = "#{base_url}/oauth/authorisations"
    headers = {
      'Accept' => 'application/hal+json;charset=UTF-8',
      'PSU-ID' => input.fetch(:psu_id, 'Liis-MariMnnik'),
      'PSU-Corporate-ID' => input.fetch(:psu_corporate_id, 'EE47101010033'),
      'X-Request-ID' => SecureRandom.uuid,
      'Content-Type' => 'application/json;charset=UTF-8'
    }
    payload = { authenticationMethodId: input[:authentication_method_id] }.to_json
    json_request(method: :post, url: url, headers: headers, payload: payload, ssl_options: ssl_opts)
  end

  step :get_oauth_authorization_status do |input, _|
    url = "#{base_url}/oauth/authorisations/#{input[:authorization_id]}"
    headers = {
      'Accept' => 'application/hal+json;charset=UTF-8',
      'X-Request-ID' => SecureRandom.uuid
    }
    json_request(method: :get, url: url, headers: headers, ssl_options: ssl_opts)
  end

  step :get_oauth_token do |input, _|
    url = "#{base_url.gsub('/v1','')}/oauth/token"
    headers = { 'Content-Type' => 'application/x-www-form-urlencoded' }
    payload = [
      "client_id=#{input[:client_id]}",
      'grant_type=authorization_code',
      "code=#{input[:code]}"
    ].join('&')
    json_request(method: :post, url: url, headers: headers, payload: payload, ssl_options: ssl_opts)
  end

  step :create_consent do |input, _|
    url = "#{base_url}/consents"
    headers = {
      'Accept' => 'application/hal+json;charset=UTF-8',
      'PSU-ID' => input.fetch(:psu_id, 'Liis-MariMnnik'),
      'PSU-Corporate-ID' => input.fetch(:psu_corporate_id, 'EE47101010033'),
      'PSU-IP-Address' => '1.2.3.4',
      'TPP-Redirect-URI' => 'http://lhv-redirect',
      'TPP-Redirect-Preferred' => 'true',
      'X-Request-ID' => '99391c7e-ad88-49ec-a2ad-99ddcb1f7721',
      'Authorization' => "Bearer #{input[:access_token]}",
      'Content-Type' => 'application/json;charset=UTF-8'
    }
    payload = {
      access: {
        balances: [{ iban: 'EE717700771001735865' }],
        transactions: [{ iban: 'EE717700771001735865' }],
        availableAccounts: 'allAccounts'
      },
      recurringIndicator: true,
      validUntil: '2025-11-01',
      frequencyPerDay: 50,
      combinedServiceIndicator: false
    }.to_json
    json_request(method: :post, url: url, headers: headers, payload: payload, ssl_options: ssl_opts)
  end

  step :get_consent_authorisations do |input, _|
    url = "#{base_url}/consents/#{input[:consent_id]}/authorisations"
    headers = {
      'Accept' => 'application/hal+json;charset=UTF-8',
      'X-Request-ID' => '99391c7e-ad88-49ec-a2ad-99ddcb1f7721',
      'Authorization' => "Bearer #{input[:access_token]}"
    }
    json_request(method: :get, url: url, headers: headers, ssl_options: ssl_opts)
  end

  step :start_decoupled_consent_signing_for_mid do |input, _|
    url = "#{base_url}/consents/#{input[:consent_id]}/authorisations"
    headers = {
      'Accept' => 'application/hal+json;charset=UTF-8',
      'PSU-IP-Address' => '1.2.3.4',
      'X-Request-ID' => '99391c7e-ad88-49ec-a2ad-99ddcb1f7721',
      'Authorization' => "Bearer #{input[:access_token]}",
      'Content-Type' => 'application/json'
    }
    payload = {
      authenticationMethodId: input[:authentication_method_id],
      scaAuthenticationData: input[:sca_authentication_data]
    }.to_json
    json_request(method: :post, url: url, headers: headers, payload: payload, ssl_options: ssl_opts)
  end

  step :start_decoupled_consent_signing do |input, _|
    url = "#{base_url}/consents/#{input[:consent_id]}/authorisations"
    headers = {
      'Accept' => 'application/hal+json;charset=UTF-8',
      'PSU-IP-Address' => '1.2.3.4',
      'X-Request-ID' => '99391c7e-ad88-49ec-a2ad-99ddcb1f7721',
      'Authorization' => "Bearer #{input[:access_token]}",
      'Content-Type' => 'application/json'
    }
    payload = { authenticationMethodId: input[:authentication_method_id] }.to_json
    json_request(method: :post, url: url, headers: headers, payload: payload, ssl_options: ssl_opts)
  end

  step :get_existing_consent_details do |input, _|
    url = "#{base_url}/consents/#{input[:consent_id]}"
    headers = {
      'Accept' => 'application/hal+json;charset=UTF-8',
      'X-Request-ID' => '99391c7e-ad88-49ec-a2ad-99ddcb1f7721',
      'Authorization' => "Bearer #{input[:access_token]}"
    }
    json_request(method: :get, url: url, headers: headers, ssl_options: ssl_opts)
  end

  step :terminate_existing_consent do |input, _|
    url = "#{base_url}/consents/#{input[:consent_id]}"
    headers = {
      'Accept' => '*/*',
      'X-Request-ID' => '99391c7e-ad88-49ec-a2ad-99ddcb1f7721',
      'Authorization' => "Bearer #{input[:access_token]}"
    }
    http_request(method: :delete, url: url, headers: headers, ssl_options: ssl_opts)
  end

  step :get_consent_status do |input, _|
    url = "#{base_url}/consents/#{input[:consent_id]}/status"
    headers = {
      'Accept' => 'application/hal+json;charset=UTF-8',
      'X-Request-ID' => '99391c7e-ad88-49ec-a2ad-99ddcb1f7721',
      'Authorization' => "Bearer #{input[:access_token]}"
    }
    json_request(method: :get, url: url, headers: headers, ssl_options: ssl_opts)
  end

  step :get_consent_authorisation_status do |input, _|
    url = "#{base_url}/consents/#{input[:consent_id]}/authorisations/#{input[:consent_authorisation_id]}"
    headers = {
      'Accept' => 'application/hal+json;charset=UTF-8',
      'X-Request-ID' => '99391c7e-ad88-49ec-a2ad-99ddcb1f7721',
      'Authorization' => "Bearer #{input[:access_token]}"
    }
    json_request(method: :get, url: url, headers: headers, ssl_options: ssl_opts)
  end

  step :get_accounts do |input, _|
    url = "#{base_url}/accounts?onlyActive=#{input.fetch(:only_active, false)}"
    headers = {
      'Accept' => 'application/hal+json;charset=UTF-8',
      'Consent-ID' => input[:consent_id].to_s,
      'X-Request-ID' => '99391c7e-ad88-49ec-a2ad-99ddcb1f7721',
      'Authorization' => "Bearer #{input[:access_token]}"
    }
    json_request(method: :get, url: url, headers: headers, ssl_options: ssl_opts)
  end

  step :get_account_details do |input, _|
    url = "#{base_url}/accounts/#{input[:resource_id]}"
    headers = {
      'Accept' => 'application/hal+json;charset=UTF-8',
      'Consent-ID' => input[:consent_id].to_s,
      'X-Request-ID' => '99391c7e-ad88-49ec-a2ad-99ddcb1f7721',
      'Authorization' => "Bearer #{input[:access_token]}"
    }
    json_request(method: :get, url: url, headers: headers, ssl_options: ssl_opts)
  end

  step :get_account_transactions do |input, _|
    url = "#{base_url}/accounts/#{input[:resource_id]}/transactions?dateFrom=#{input[:start_date]}&dateTo=#{input.fetch(:end_date, Date.today.to_s)}&bookingStatus=#{input[:booking_status]}"
    headers = {
      'Accept' => 'application/hal+json;charset=UTF-8',
      'Consent-ID' => input[:consent_id].to_s,
      'PSU-IP-Address' => '127.0.0.1',
      'X-Request-ID' => '99391c7e-ad88-49ec-a2ad-99ddcb1f7721',
      'Authorization' => "Bearer #{input[:access_token]}"
    }
    json_request(method: :get, url: url, headers: headers, ssl_options: ssl_opts)
  end

  step :get_account_balances do |input, _|
    url = "#{base_url}/accounts/#{input[:resource_id]}/balances"
    headers = {
      'Accept' => 'application/hal+json;charset=UTF-8',
      'Consent-ID' => input[:consent_id].to_s,
      'X-Request-ID' => '99391c7e-ad88-49ec-a2ad-99ddcb1f7721',
      'Authorization' => "Bearer #{input[:access_token]}"
    }
    json_request(method: :get, url: url, headers: headers, ssl_options: ssl_opts)
  end

  step :get_accounts_list do |input, _|
    url = "#{base_url}/accounts-list?onlyActive=#{input.fetch(:only_active, false)}"
    headers = {
      'Accept' => 'application/hal+json;charset=UTF-8',
      'PSU-Corporate-ID' => input.fetch(:psu_corporate_id, 'EE47101010033'),
      'X-Request-ID' => '99391c7e-ad88-49ec-a2ad-99ddcb1f7721',
      'Authorization' => "Bearer #{input[:access_token]}"
    }
    json_request(method: :get, url: url, headers: headers, ssl_options: ssl_opts)
  end

  step :get_sepa_payment_authorisations do |input, _|
    url = "#{base_url}/payments/sepa-credit-transfers/#{input[:payment_id]}/authorisations"
    headers = {
      'Accept' => 'application/hal+json;charset=UTF-8',
      'X-Request-ID' => SecureRandom.uuid,
      'Authorization' => "Bearer #{input[:access_token]}"
    }
    json_request(method: :get, url: url, headers: headers, ssl_options: ssl_opts)
  end

  step :start_decoupled_payment_signing do |input, _|
    url = "#{base_url}/payments/sepa-credit-transfers/#{input[:payment_id]}/authorisations"
    headers = {
      'Accept' => 'application/hal+json;charset=UTF-8',
      'PSU-IP-Address' => '1.2.3.4',
      'X-Request-ID' => SecureRandom.uuid,
      'Authorization' => "Bearer #{input[:access_token]}",
      'Content-Type' => 'application/json;charset=UTF-8'
    }
    payload = {
      authenticationMethodId: input[:authentication_method_id],
      scaAuthenticationData: input[:sca_authentication_data]
    }.to_json
    json_request(method: :post, url: url, headers: headers, payload: payload, ssl_options: ssl_opts)
  end

  step :initiate_sepa_payment_request do |input, _|
    url = "#{base_url}.1/payments/sepa-credit-transfers"
    headers = {
      'Accept' => 'application/hal+json;charset=UTF-8',
      'PSU-Corporate-ID' => input.fetch(:psu_corporate_id, 'EE47101010033'),
      'PSU-IP-Address' => '1.2.3.4',
      'TPP-Redirect-Preferred' => 'true',
      'TPP-Redirect-URI' => 'http://localhost:3000/callback',
      'X-Request-ID' => SecureRandom.uuid,
      'Authorization' => "Bearer #{input[:access_token]}",
      'Content-Type' => 'application/json;charset=UTF-8'
    }
    payload = {
      debtorAccount: { iban: input[:debtor_iban] },
      instructedAmount: { currency: input[:currency], amount: input[:amount] },
      creditorAccount: { iban: input[:creditor_iban] },
      creditorName: input[:creditor_name],
      remittanceInformationUnstructured: input[:remittance_info],
      remittanceInformationStructured: { reference: 'Reference example' },
      requestedExecutionDate: (Date.today >> 1).to_s
    }.to_json
    json_request(method: :post, url: url, headers: headers, payload: payload, ssl_options: ssl_opts)
  end

  step :get_sepa_payment_information do |input, _|
    url = "#{base_url}/payments/sepa-credit-transfers/#{input[:payment_id]}"
    headers = {
      'Accept' => 'application/hal+json;charset=UTF-8',
      'X-Request-ID' => SecureRandom.uuid,
      'Authorization' => "Bearer #{input[:access_token]}"
    }
    json_request(method: :get, url: url, headers: headers, ssl_options: ssl_opts)
  end

  step :cancel_sepa_payment do |input, _|
    url = "#{base_url}/payments/sepa-credit-transfers/#{input[:payment_id]}"
    headers = {
      'Accept' => '*/*',
      'X-Request-ID' => SecureRandom.uuid,
      'Authorization' => "Bearer #{input[:access_token]}"
    }
    http_request(method: :delete, url: url, headers: headers, ssl_options: ssl_opts)
  end

  step :get_sepa_payment_status do |input, _|
    url = "#{base_url}/payments/sepa-credit-transfers/#{input[:payment_id]}/status"
    headers = {
      'Accept' => 'application/hal+json;charset=UTF-8',
      'X-Request-ID' => SecureRandom.uuid,
      'Authorization' => "Bearer #{input[:access_token]}"
    }
    json_request(method: :get, url: url, headers: headers, ssl_options: ssl_opts)
  end

  step :get_sepa_payment_authorisation_status do |input, _|
    url = "#{base_url}/payments/sepa-credit-transfers/#{input[:payment_id]}/authorisations/#{input[:authorisation_id]}"
    headers = {
      'Accept' => 'application/hal+json;charset=UTF-8',
      'X-Request-ID' => SecureRandom.uuid,
      'Authorization' => "Bearer #{input[:access_token]}"
    }
    json_request(method: :get, url: url, headers: headers, ssl_options: ssl_opts)
  end

  step :create_confirmation_of_funds_consent do |input, _|
    url = "#{base_url}/consents/confirmation-of-funds"
    headers = {
      'Accept' => 'application/hal+json;charset=UTF-8',
      'PSU-IP-Address' => '1.2.3.4',
      'TPP-Redirect-URI' => 'http://lhv-redirect',
      'TPP-Redirect-Preferred' => 'true',
      'X-Request-ID' => SecureRandom.uuid,
      'Authorization' => "Bearer #{input[:access_token]}",
      'Content-Type' => 'application/json;charset=UTF-8'
    }
    payload = { account: { iban: input[:iban] } }.to_json
    json_request(method: :post, url: url, headers: headers, payload: payload, ssl_options: ssl_opts)
  end

  step :get_confirmation_of_funds_authorisations do |input, _|
    url = "#{base_url}/consents/confirmation-of-funds/#{input[:consent_id]}/authorisations"
    headers = {
      'Accept' => 'application/hal+json;charset=UTF-8',
      'X-Request-ID' => SecureRandom.uuid,
      'Authorization' => "Bearer #{input[:access_token]}"
    }
    json_request(method: :get, url: url, headers: headers, ssl_options: ssl_opts)
  end

  step :post_confirmation_of_funds_authorisations do |input, _|
    url = "#{base_url}/consents/confirmation-of-funds/#{input[:consent_id]}/authorisations"
    headers = {
      'Accept' => 'application/hal+json;charset=UTF-8',
      'X-Request-ID' => SecureRandom.uuid,
      'Authorization' => "Bearer #{input[:access_token]}",
      'Content-Type' => 'application/json'
    }
    payload = {
      authenticationMethodId: input[:authentication_method_id],
      scaAuthenticationData: input[:sca_authentication_data]
    }.to_json
    json_request(method: :post, url: url, headers: headers, payload: payload, ssl_options: ssl_opts)
  end

  step :get_confirmation_of_funds_consent do |input, _|
    url = "#{base_url}/consents/confirmation-of-funds/#{input[:consent_id]}"
    headers = {
      'Accept' => 'application/hal+json;charset=UTF-8',
      'X-Request-ID' => SecureRandom.uuid,
      'Authorization' => "Bearer #{input[:access_token]}"
    }
    json_request(method: :get, url: url, headers: headers, ssl_options: ssl_opts)
  end

  step :terminate_confirmation_of_funds_consent do |input, _|
    url = "#{base_url}/consents/confirmation-of-funds/#{input[:consent_id]}"
    headers = {
      'Accept' => '*/*',
      'X-Request-ID' => SecureRandom.uuid,
      'Authorization' => "Bearer #{input[:access_token]}"
    }
    http_request(method: :delete, url: url, headers: headers, ssl_options: ssl_opts)
  end

  step :get_confirmation_of_funds_consent_status do |input, _|
    url = "#{base_url}/consents/confirmation-of-funds/#{input[:consent_id]}/status"
    headers = {
      'Accept' => 'application/hal+json;charset=UTF-8',
      'X-Request-ID' => SecureRandom.uuid,
      'Authorization' => "Bearer #{input[:access_token]}"
    }
    json_request(method: :get, url: url, headers: headers, ssl_options: ssl_opts)
  end

  step :get_confirmation_of_funds_consent_authorisation_status do |input, _|
    url = "#{base_url}/consents/confirmation-of-funds/#{input[:consent_id]}/authorisations/#{input[:authorisation_id]}"
    headers = {
      'Accept' => 'application/hal+json;charset=UTF-8',
      'X-Request-ID' => SecureRandom.uuid,
      'Authorization' => "Bearer #{input[:access_token]}"
    }
    json_request(method: :get, url: url, headers: headers, ssl_options: ssl_opts)
  end
end
