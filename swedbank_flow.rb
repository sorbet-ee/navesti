require_relative 'navesti'
require 'pp'

Navesti.define :show_accounts do
  format :json

  source :show_accounts_parameters do
    map :tpp_redirect_preferred, to: :tpp_redirect_preferred
    map :frequency_per_day, to: :frequency_per_day
    map :recurring_indicator, to: :recurring_indicator
    map :iban, to: :iban
  end

  workflow do
    initial_data = nil
    step "Create Consent" do |data|
      pp Navesti.instance_variable_get(:@workflows).inspect
      initial_data = data
      create_consent_response = Navesti::ExternalServices.create_consent(data)
      initial_data.merge!(create_consent_response: create_consent_response)
      pp "Step 1: Creating Consent executed"
      initial_data
    end

    step "Get consent status" do |data|
      data[:url] = data[:base_url] + data[:create_consent_response]["_links"]["status"]["href"] + "?bic=" + data[:bic] + "&app-id=" + data[:app_id]
      get_status_response = Navesti::ExternalServices.get_consent_status(data)
      initial_data.merge!(get_status_response: get_status_response)
      pp "Step 2: Getting Consent Status executed"
      initial_data
    end

    step "Get consent details" do |data|
      data[:url] = data[:url].sub("/status", "")
      get_consent_details_response = Navesti::ExternalServices.get_consent_details(data)
      initial_data.merge!(get_consent_details_response: get_consent_details_response)
      pp "Step 3: Getting Consent Details executed"
      initial_data
    end

    step "Open browser to accept consent" do |data|
      system("open #{data[:create_consent_response]['_links']['scaRedirect']['href']}")
      sleep 6
      pp "Step 4: Opening Browser to Accept Consent executed"
      data
    end

    step "Get consent status after approval" do |data|
      data[:url] = data[:base_url] + data[:create_consent_response]["_links"]["status"]["href"] + "?bic=" + data[:bic] + "&app-id=" + data[:app_id]
      get_status_response = Navesti::ExternalServices.get_consent_status(data)
      initial_data.merge!(get_status_response: get_status_response)
      pp "Step 5: Getting Consent Status After Approval executed"
      initial_data
    end

    step "Show accounts" do |data|
      data[:url] = data[:base_url] + "/sandbox/v5/accounts?bic=" + data[:bic] + "&app-id=" + data[:app_id]
      data[:headers] = data[:headers].merge("Consent-ID" => data[:create_consent_response]["consentId"])
      get_accounts_response = Navesti::ExternalServices.show_accounts(data)
      final_log_data = initial_data.merge!(get_accounts_response: get_accounts_response)
      pp "Step 6: Showing Accounts executed"
      puts ""
      puts "THE FINAL LOG DATA IS:"
      puts ""
      puts final_log_data.inspect
      puts ""
      puts "AND THE FINAL NAVESTI DATA IS:"
      puts ""
      final_navesti_data = data[:get_accounts_response]
    end
  end
end
