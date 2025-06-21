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
      #pp Navesti.instance_variable_get(:@workflows).inspect
      initial_data = data
      create_consent_response = Navesti::ExternalServices.create_consent(data)
      initial_data.merge!(create_consent_response: create_consent_response)
      pp "Step 1: Creating Consent executed"
      pp initial_data[:create_consent_response]
      initial_data
    end

    step "Get consent status" do |data|
      data[:url] = data[:base_url] + data[:create_consent_response]["_links"]["status"]["href"] + "?bic=" + data[:bic] + "&app-id=" + data[:app_id]
      get_status_response = Navesti::ExternalServices.get_consent_status(data)
      initial_data.merge!(get_status_response: get_status_response)
      pp "Step 2: Getting Consent Status executed"
      pp initial_data[:get_status_response]
      initial_data
    end

    step "Get consent details" do |data|
      data[:url] = data[:url].sub("/status", "")
      get_consent_details_response = Navesti::ExternalServices.get_consent_details(data)
      initial_data.merge!(get_consent_details_response: get_consent_details_response)
      pp "Step 3: Getting Consent Details executed"
      pp initial_data[:get_consent_details_response]
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
      pp initial_data[:get_status_response]
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

Navesti.define :show_specific_account do
  format :json

  source :show_specific_account_parameters do
  end

  workflow do
    initial_data = nil
    
    step "Create Consent" do |data|
      initial_data = data
      create_consent_response = Navesti::ExternalServices.create_consent(data)
      initial_data.merge!(create_consent_response: create_consent_response)
      pp "Step 1: Creating Consent executed"
      pp initial_data[:create_consent_response]
      initial_data
    end

    step "Open browser to accept consent" do |data|
      system("open #{data[:create_consent_response]['_links']['scaRedirect']['href']}")
      sleep 6
      pp "Step 2: Opening Browser to Accept Consent executed"
      data
    end

    step "Get consent status after approval" do |data|
      data[:url] = data[:base_url] + data[:create_consent_response]["_links"]["status"]["href"] + "?bic=" + data[:bic] + "&app-id=" + data[:app_id]
      get_status_response = Navesti::ExternalServices.get_consent_status(data)
      initial_data.merge!(get_status_response: get_status_response)
      pp "Step 3: Getting Consent Status After Approval executed"
      pp initial_data[:get_status_response]
      data
    end

    step "Show accounts" do |data|
      data[:url] = data[:base_url] + "/sandbox/v5/accounts" + "?bic=" + data[:bic] + "&app-id=" + data[:app_id]
      data[:headers] = data[:headers].merge("Consent-ID" => data[:create_consent_response]["consentId"])
      get_accounts_response = Navesti::ExternalServices.show_accounts(data)
      data.merge!(get_accounts_response: get_accounts_response)
      pp "Step 4: Showing Accounts executed"
      pp data[:get_accounts_response]
      data
    end

    step "Create Consent" do |data|
      data[:url] = data[:base_url] + "/sandbox/v5/consents" + "?bic=" + data[:bic] + "&app-id=" + data[:app_id]
      create_consent_response = Navesti::ExternalServices.create_consent(data)
      data.merge!(create_consent_response: create_consent_response)
      pp "Step 5: Creating Consent executed"
      pp data[:create_consent_response]
      data
    end

    step "Open browser to accept consent" do |data|
      system("open #{data[:create_consent_response]['_links']['scaRedirect']['href']}")
      sleep 6
      pp "Step 6: Opening Browser to Accept Consent executed"
      data
    end

    step "Get consent status after approval" do |data|
      data[:url] = data[:base_url] + data[:create_consent_response]["_links"]["status"]["href"] + "?bic=" + data[:bic] + "&app-id=" + data[:app_id]
      get_status_response = Navesti::ExternalServices.get_consent_status(data)
      data.merge!(get_status_response: get_status_response)
      pp "Step 7: Getting Consent Status After Approval executed"
      pp data[:get_status_response]
      data
    end

    step "Show specific account" do |data|
      data[:url] = data[:base_url] + "/sandbox/v5/accounts/" + data[:get_accounts_response]["accounts"][0]["resourceId"] + "?bic=" + data[:bic] + "&app-id=" + data[:app_id]
      data[:headers] = data[:headers].merge("Consent-ID" => data[:create_consent_response]["consentId"])
      get_account_response = Navesti::ExternalServices.show_account(data)
      data.merge!(get_account_response: get_account_response)
      pp "Step 8: Showing Specific Account executed"
      pp data[:get_account_response]
      data[:get_account_response]
    end
  end
end

Navesti.define :show_account_balances do
  format :json

  source :show_account_balances_parameters do
    
  end

  workflow do
    initial_data = nil
    
    step "Create Consent" do |data|
      initial_data = data
      create_consent_response = Navesti::ExternalServices.create_consent(data)
      initial_data.merge!(create_consent_response: create_consent_response)
      pp "Step 1: Creating Consent executed"
      pp initial_data[:create_consent_response]
      initial_data
    end

    step "Open browser to accept consent" do |data|
      system("open #{data[:create_consent_response]['_links']['scaRedirect']['href']}")
      sleep 6
      pp "Step 2: Opening Browser to Accept Consent executed"
      data
    end

    step "Get consent status after approval" do |data|
      data[:url] = data[:base_url] + data[:create_consent_response]["_links"]["status"]["href"] + "?bic=" + data[:bic] + "&app-id=" + data[:app_id]
      get_status_response = Navesti::ExternalServices.get_consent_status(data)
      initial_data.merge!(get_status_response: get_status_response)
      pp "Step 3: Getting Consent Status After Approval executed"
      pp initial_data[:get_status_response]
      data
    end

    step "Show accounts" do |data|
      data[:url] = data[:base_url] + "/sandbox/v5/accounts" + "?bic=" + data[:bic] + "&app-id=" + data[:app_id]
      data[:headers] = data[:headers].merge("Consent-ID" => data[:create_consent_response]["consentId"])
      get_accounts_response = Navesti::ExternalServices.show_accounts(data)
      data.merge!(get_accounts_response: get_accounts_response)
      pp "Step 4: Showing Accounts executed"
      pp data[:get_accounts_response]
      data
    end

    step "Create Consent" do |data|
      data[:url] = data[:base_url] + "/sandbox/v5/consents" + "?bic=" + data[:bic] + "&app-id=" + data[:app_id]
      create_consent_response = Navesti::ExternalServices.create_consent(data)
      data.merge!(create_consent_response: create_consent_response)
      pp "Step 5: Creating Consent executed"
      pp data[:create_consent_response]
      data
    end

    step "Open browser to accept consent" do |data|
      system("open #{data[:create_consent_response]['_links']['scaRedirect']['href']}")
      sleep 6
      pp "Step 6: Opening Browser to Accept Consent executed"
      data
    end

    step "Get consent status after approval" do |data|
      data[:url] = data[:base_url] + data[:create_consent_response]["_links"]["status"]["href"] + "?bic=" + data[:bic] + "&app-id=" + data[:app_id]
      get_status_response = Navesti::ExternalServices.get_consent_status(data)
      data.merge!(get_status_response: get_status_response)
      pp "Step 7: Getting Consent Status After Approval executed"
      pp data[:get_status_response]
      data
    end

    step "Show specific account" do |data|
      data[:url] = data[:base_url] + "/sandbox/v5/accounts/" + data[:get_accounts_response]["accounts"][0]["resourceId"] + "?bic=" + data[:bic] + "&app-id=" + data[:app_id]
      data[:headers] = data[:headers].merge("Consent-ID" => data[:create_consent_response]["consentId"])
      get_account_response = Navesti::ExternalServices.show_account(data)
      data.merge!(get_account_response: get_account_response)
      pp "Step 8: Showing Specific Account executed"
      pp data[:get_account_response]
      data
    end

    step "Show account balances" do |data|
      data[:url] = data[:base_url] + "/sandbox/v5/accounts/" + data[:get_account_response]["account"]["_links"]["balances"]["href"] + "?bic=" + data[:bic] + "&app-id=" + data[:app_id]
      data[:headers] = data[:headers].merge("Consent-ID" => data[:create_consent_response]["consentId"])
      get_account_balances_response = Navesti::ExternalServices.show_account_balances(data)
      data.merge!(get_account_balances_response: get_account_balances_response)
      pp "Step 9: Showing Account Balances executed"
      pp data[:get_account_balances_response]
      data[:get_account_balances_response]
    end
  end
end

Navesti.define :show_account_transactions do
  format :json

  source :show_account_transactions_parameters do
  end

  workflow do
    initial_data = nil
    
    step "Create Consent" do |data|
      initial_data = data
      create_consent_response = Navesti::ExternalServices.create_consent(data)
      initial_data.merge!(create_consent_response: create_consent_response)
      pp "Step 1: Creating Consent executed"
      pp initial_data[:create_consent_response]
      initial_data
    end

    step "Open browser to accept consent" do |data|
      system("open #{data[:create_consent_response]['_links']['scaRedirect']['href']}")
      sleep 6
      pp "Step 2: Opening Browser to Accept Consent executed"
      data
    end

    step "Get consent status after approval" do |data|
      data[:url] = data[:base_url] + data[:create_consent_response]["_links"]["status"]["href"] + "?bic=" + data[:bic] + "&app-id=" + data[:app_id]
      get_status_response = Navesti::ExternalServices.get_consent_status(data)
      initial_data.merge!(get_status_response: get_status_response)
      pp "Step 3: Getting Consent Status After Approval executed"
      pp initial_data[:get_status_response]
      data
    end

    step "Show accounts" do |data|
      data[:url] = data[:base_url] + "/sandbox/v5/accounts" + "?bic=" + data[:bic] + "&app-id=" + data[:app_id]
      data[:headers] = data[:headers].merge("Consent-ID" => data[:create_consent_response]["consentId"])
      get_accounts_response = Navesti::ExternalServices.show_accounts(data)
      data.merge!(get_accounts_response: get_accounts_response)
      pp "Step 4: Showing Accounts executed"
      pp data[:get_accounts_response]
      data
    end

    step "Create Consent" do |data|
      data[:url] = data[:base_url] + "/sandbox/v5/consents" + "?bic=" + data[:bic] + "&app-id=" + data[:app_id]
      create_consent_response = Navesti::ExternalServices.create_consent(data)
      data.merge!(create_consent_response: create_consent_response)
      pp "Step 5: Creating Consent executed"
      pp data[:create_consent_response]
      data
    end

    step "Open browser to accept consent" do |data|
      system("open #{data[:create_consent_response]['_links']['scaRedirect']['href']}")
      sleep 6
      pp "Step 6: Opening Browser to Accept Consent executed"
      data
    end

    step "Get consent status after approval" do |data|
      data[:url] = data[:base_url] + data[:create_consent_response]["_links"]["status"]["href"] + "?bic=" + data[:bic] + "&app-id=" + data[:app_id]
      get_status_response = Navesti::ExternalServices.get_consent_status(data)
      data.merge!(get_status_response: get_status_response)
      pp "Step 7: Getting Consent Status After Approval executed"
      pp data[:get_status_response]
      data
    end

    step "Show specific account" do |data|
      data[:url] = data[:base_url] + "/sandbox/v5/accounts/" + data[:get_accounts_response]["accounts"][0]["resourceId"] + "?bic=" + data[:bic] + "&app-id=" + data[:app_id]
      data[:headers] = data[:headers].merge("Consent-ID" => data[:create_consent_response]["consentId"])
      get_account_response = Navesti::ExternalServices.show_account(data)
      data.merge!(get_account_response: get_account_response)
      pp "Step 8: Showing Specific Account executed"
      pp data[:get_account_response]
      data
    end

    step "Show account transactions" do |data|
      data[:url] = data[:base_url] + "/sandbox/v5/accounts/" + data[:get_account_response]["account"]["_links"]["transactions"]["href"] + "?bic=" + data[:bic] + "&app-id=" + data[:app_id] + "&bookingStatus=" + data[:booking_status] + "&dateFrom=" + data[:dateFrom] + "&dateTo=" + data[:dateTo]
      data[:headers] = data[:headers].merge("Consent-ID" => data[:create_consent_response]["consentId"])
      get_account_transactions_response = Navesti::ExternalServices.show_account_transactions(data)
      data.merge!(get_account_transactions_response: get_account_transactions_response)
      pp "Step 9: Showing Account Transactions executed"
      pp data[:get_account_transactions_response]
      data[:get_account_transactions_response]
    end
  end
end

Navesti.define :initiate_payment do
  format :json

  source :initiate_payment_parameters do
  end
  
  workflow do
    initial_data = nil
    
    step "initiate payment" do |data|
      initial_data = data
      initiate_payment_response = Navesti::ExternalServices.initiate_payment(data)
      initial_data.merge!(initiate_payment_response: initiate_payment_response)
      pp "Step 1: Initiating Payment executed"
      pp initial_data[:initiate_payment_response]
      data
    end

    step "Open browser to accept consent" do |data|
      system("open #{data[:initiate_payment_response]['_links']['scaRedirect']['href']}")
      pp "Step 2: Opening Browser to Accept Consent executed"
      sleep 10
      data
    end

    step "Get payment status after approval" do |data|
      data[:url] = data[:base_url] + data[:initiate_payment_response]["_links"]["status"]["href"] + "?bic=" + data[:bic] + "&app-id=" + data[:app_id]
      get_status_response = Navesti::ExternalServices.get_payment_status(data)
      data.merge!(get_status_response: get_status_response)
      pp "Step 3: Getting Payment Status After Approval executed"
      pp data[:get_status_response]
      data
    end

    step "Show payment details" do |data|
      data[:url] = data[:base_url] + data[:initiate_payment_response]["_links"]["self"]["href"] + "?bic=" + data[:bic] + "&app-id=" + data[:app_id]
      get_payment_details_response = Navesti::ExternalServices.show_payment_details(data)
      data.merge!(get_payment_details_response: get_payment_details_response)
      pp "Step 4: Showing Payment Details executed"
      pp data[:get_payment_details_response]
      data
    end
  end

  step "Get scaStatus" do |data|
    data[:url] = data[:base_url] + data[:initiate_payment_response]["_links"]["scaStatus"]["href"] + "?bic=" + data[:bic] + "&app-id=" + data[:app_id]
    get_sca_status_response = Navesti::ExternalServices.get_sca_status(data)
    data.merge!(get_sca_status_response: get_sca_status_response)
    pp "Step 5: Getting SCA Status executed"
    pp data[:get_sca_status_response]
    data[:get_sca_status_response]
  end
end
