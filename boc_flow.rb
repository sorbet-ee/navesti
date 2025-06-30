require_relative 'navesti'
require 'pp'

Navesti.define :show_accounts do
    format :json

    source :show_accounts_parameters do
    end

    workflow do
        step "Get Access Token in :show_accounts" do |data|
            url = "#{data[:base_url]}/oauth2/token"
            data[:url] = url
            data[:payload] = {
                "client_id" => data[:client_id],
                "client_secret" => data[:client_secret],
                "scope" => data[:scope],
                "grant_type" => data[:grant_type]
            }
            if data[:headers]["Content-Type"] == "application/x-www-form-urlencoded"
                first_access_token_response = Navesti::ExternalServices.get_access_token(data, nil)
            else
                first_access_token_response = Navesti::ExternalServices.get_access_token(data)
            end
            data.merge!(first_access_token_response: first_access_token_response)
            pp "Step 1: Get Access Token in :show_accounts executed"
            pp data[:first_access_token_response]
            data
        end

        step "Get Subscription ID in :show_accounts" do |data|
            url = "#{data[:base_url]}/v1/subscriptions"
            data[:headers].merge!(
                "Authorization" => "Bearer #{data[:first_access_token_response]["access_token"]}",
                "Content-Type" => "application/json",
                "timeStamp" => Time.now.utc.iso8601,
                "journeyId" => SecureRandom.uuid
            )
            payload = {
                "accounts": {
                    "transactionHistory": true,
                    "balance": true,
                    "details": true,
                    "checkFundsAvailability": true
                },
                "payments": {
                    "limit": 99999999,
                    "currency": "EUR",
                    "amount": 999999999
                }
            }
            data.merge!(payload: payload, url: url)
            get_subscription_id_response = Navesti::ExternalServices.get_subscription_id(data)
            data.merge!(get_subscription_id_response: get_subscription_id_response)
            pp "Step 2: Get Subscription ID in :show_accounts executed"
            pp data[:get_subscription_id_response]
            data
        end

        step "Select accounts for subscription id and get authorization code in :show_accounts" do |data|
            data[:response_type] = 'code'
            data[:redirect_uri] = 'https://localhost'
            data[:scope] = 'UserOAuth2Security'
            data[:subscription_id] = data[:get_subscription_id_response]["subscriptionId"]
            #data[:state] = SecureRandom.uuid
            data.merge!(response_type: data[:response_type], redirect_uri: data[:redirect_uri], scope: data[:scope])
            params = {
                response_type: data[:response_type],
                redirect_uri: data[:redirect_uri],
                scope: data[:scope],
                client_id: data[:client_id],
                subscriptionid: data[:subscription_id]
            }
            data.merge!(params: params)
            url = "#{data[:base_url]}/oauth2/authorize?response_type=#{data[:response_type]}&redirect_uri=#{data[:redirect_uri]}&scope=#{data[:scope]}&client_id=#{data[:client_id]}&subscriptionid=#{data[:subscription_id]}"
            data[:url] = url
            # Open the URL in the default web browser
            puts "Awaiting Authorization-COPY PASTE THE URL"
            system("xdg-open '#{data[:url]}'") if RUBY_PLATFORM.include?("linux")  # Linux
            system("open '#{data[:url]}'") if RUBY_PLATFORM.include?("darwin")  # Mac
            system("start #{data[:url]}") if RUBY_PLATFORM.include?("mswin|mingw")  # Windows
            # Step 3: Pause execution and wait for user input
            redirected_url = $stdin.gets.chomp.strip  # Ensures input is read properly
            # Step 4: Extract authorization code from the redirected URL
            parsed_params = CGI.parse(URI.parse(redirected_url).query)
            auth_data = {
                code: parsed_params["code"]&.first
            }
            data.merge!(auth_data: auth_data)
            pp "Step 3: Select accounts for subscription id and get authorization code in :show_accounts executed"
            pp data[:auth_data]
            data
        end

        step "Get Access Token in :show_accounts second time" do |data|
            data[:url] = data[:base_url] + "/oauth2/token"
            data[:payload][:grant_type] = "authorization_code"
            data[:payload] = {
                "grant_type" => data[:payload][:grant_type],
                "client_id" => data[:client_id],
                "client_secret" => data[:client_secret],
                "scope" => data[:scope],
                "code" => data[:auth_data][:code]
            }
            data[:headers].merge!(
                "Content-Type" => "application/x-www-form-urlencoded"
            )
            data[:headers]["Authorization"] = ""
            if data[:headers]["Content-Type"] == "application/x-www-form-urlencoded"
                second_access_token_response = Navesti::ExternalServices.get_access_token(data, nil)
            else
                second_access_token_response = Navesti::ExternalServices.get_access_token(data)
            end
            data.merge!(second_access_token_response: second_access_token_response)
            pp "Step 4: Get Access Token in :show_accounts second time executed"
            data
        end

        step "Get Subscriptions for TPP based on subscription id in :show_accounts" do |data|
            data[:url] = data[:base_url] + "/v1/subscriptions/#{data[:subscription_id]}"
            data[:headers].merge!(
                "Authorization" => "Bearer #{data[:second_access_token_response]["access_token"]}",
                "Content-Type" => "application/json",
                "timeStamp" => Time.now.utc.iso8601,
                "journeyId" => SecureRandom.uuid
            )
            subscriptions_response = Navesti::ExternalServices.get_subscriptions_for_tpp_based_on_subscription_id(data)
            data.merge!(subscriptions_response: subscriptions_response)
            pp "Step 5: Get Subscriptions for TPP based on subscription id in :show_accounts executed"
            pp data[:subscriptions_response]
            data
        end

        step "Update Subscriptions for TPP based on subscription id in :show_accounts" do |data|
            data[:url] = data[:base_url] + "/v1/subscriptions/#{data[:subscription_id]}"
            data[:headers].merge!(
                "timeStamp" => Time.now.utc.iso8601,
                "journeyId" => SecureRandom.uuid
            )
            data[:payload] = data[:subscriptions_response][0]
            patch_subscriptions_response = Navesti::ExternalServices.update_subscription_details_based_on_subscription_id(data)
            data.merge!(patch_subscriptions_response: patch_subscriptions_response)
            pp "Step 6: Update Subscriptions for TPP based on subscription id in :show_accounts executed"
            pp data[:patch_subscriptions_response]
            data
        end

        step "Get Accounts for TPP based on subscription id in :show_accounts" do |data|
            sleep 5
            data[:url] = data[:base_url] + "/v1/accounts"
            data[:headers].merge!(
                "Authorization" => "Bearer #{data[:first_access_token_response]["access_token"]}",
                "timeStamp" => Time.now.utc.iso8601,
                "journeyId" => SecureRandom.uuid,
                "subscriptionId" => data[:patch_subscriptions_response]["subscriptionId"]
            )
            accounts_response = Navesti::ExternalServices.show_accounts(data)
            data.merge!(accounts_response: accounts_response)
            pp "Step 7: Get Accounts for TPP based on subscription id in :show_accounts executed"
            pp data
            data[:accounts_response]
        end
    end
end

Navesti.define :show_account do
    format :json

    source :show_account_parameters do
    end

    workflow do
        step "Running the :show_accounts workflow in :show_account" do |data|
            accounts_response = Navesti.run(:show_accounts, data)
            data.merge!(accounts_response: accounts_response)
            pp "Step 1: Running the :show_accounts workflow in :show_account executed"
            pp data[:accounts_response]
            data
        end

        step "Show account details in :show_account" do |data|
            url = data[:base_url] + "/v1/accounts/#{data[:accounts_response][0]["accountId"]}"
            data[:url] = url
            data[:headers].merge!(
                "timeStamp" => Time.now.utc.iso8601,
                "journeyId" => SecureRandom.uuid
            )
            account_details_response = Navesti::ExternalServices.show_account(data)
            data.merge!(account_details_response: account_details_response)
            pp "Step 2: Show account details in :show_account executed"
            pp data[:account_details_response]
            data[:account_details_response]
        end
    end
end

Navesti.define :show_account_balances do
    format :json

    source :show_account_balances_parameters do
    end
    
    workflow do
        step "Running the :show_account workflow in :show_account_balances" do |data|
            account_response = Navesti.run(:show_account, data)
            data.merge!(account_response: account_response)
            pp "Step 1: Running the :show_account workflow in :show_account_balances executed"
            pp data[:account_response]
            data
        end
        
        step "Show account balances in :show_account_balances" do |data|
            url = data[:base_url] + "/v1/accounts/#{data[:account_details_response][0]["accountId"]}/balance"
            data[:url] = url
            data[:headers].merge!(
                "timeStamp" => Time.now.utc.iso8601,
                "journeyId" => SecureRandom.uuid
            )
            account_balance_response = Navesti::ExternalServices.show_account_balances(data)
            data.merge!(account_balance_response: account_balance_response)
            pp "Step 2: Show account balances in :show_account_balances executed"
            pp data
            data[:account_balance_response]
        end
    end
end

Navesti.define :show_account_transactions do
    format :json

    source :show_account_transactions_parameters do
    end
    
    workflow do
        step "Running the :show_account workflow in :show_account_transactions" do |data|
            account_response = Navesti.run(:show_account, data)
            data.merge!(account_response: account_response)
            pp "Step 1: Running the :show_account workflow in :show_account_transactions executed"
            pp data[:account_response]
            data
        end
        
        step "Show account transactions in :show_account_transactions" do |data|
            data[:startDate] = "16/04/2025"
            data[:endDate] = "25/06/2025"
            data[:maxCount] = 10
            url = data[:base_url] + "/v1/accounts/#{data[:account_details_response][0]["accountId"]}/statement?startDate=#{data[:startDate]}&endDate=#{data[:endDate]}&maxCount=#{data[:maxCount]}"
            data[:url] = url
            data[:headers].merge!(
                "timeStamp" => Time.now.utc.iso8601,
                "journeyId" => SecureRandom.uuid
            )
            account_transactions_response = Navesti::ExternalServices.show_account_transactions(data)
            data.merge!(account_transactions_response: account_transactions_response)
            pp "Step 2: Show account transactions in :show_account_transactions executed"
            pp data
            data[:account_transactions_response]
        end
    end
end

Navesti.define :payment_initiation do
    format :json

    source :payment_initiation_parameters do
    end
    
    workflow do
        step "Running the :show_account workflow in :payment_initiation" do |data|
            account_response = Navesti.run(:show_account, data)
            data.merge!(account_response: account_response)
            pp "Step 1: Running the :show_account workflow in :payment_initiation executed"
            pp data[:account_response]
            data
        end
        
        step "Sign request in :payment_initiation" do |data|
            data[:headers] = {
                "Content-Type" => "application/json",
                "Accept" => "application/json",
                'tppId' => 'singpaymentdata'
            }
            data[:payload] = {
                "debtor": {
                    "bankId": "",
                    "accountId": "351012345671"
                },
                "creditor": {
                    "bankId": "CITIUS33",
                    "accountId": "48193222324233"
                },
                "transactionAmount": {
                    "amount": 30,
                    "currency": "EUR"
                },
                "paymentDetails": "SWIFT Transfer"
            }
            data[:url] = "https://sandbox-apis.bankofcyprus.com/df-boc-org-sb/sb/jwssignverifyapi/sign"
            sign_request_response = Navesti::ExternalServices.sign_request(data)
            data.merge!(sign_request_response: sign_request_response)
            pp "Step 2: Sign request in :payment_initiation executed"
            pp data[:sign_request_response]
            data
        end

        step "Payment initiation in :payment_initiation" do |data|
            data[:payload] = data[:sign_request_response]
            data[:headers] = {
                "Content-Type" => "application/json",
                "Accept" => "application/json",
                "Authorization" => "Bearer #{data[:first_access_token_response]["access_token"]}",
                "timeStamp" => Time.now.utc.iso8601,
                "journeyId" => SecureRandom.uuid,
                "subscriptionId" => data[:patch_subscriptions_response]["subscriptionId"],
                "customerIP" => "127.0.0.1",
                "customerSessionId" => "5533484915359744",
                "loginTimeStamp" => "484923761",
                'customerDevice' => 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:138.0) Gecko/20100101 Firefox/138.0'
            }
            data[:url] = data[:base_url] + "/v1/payments/initiate"
            payment_initiation_response = Navesti::ExternalServices.initiate_payment(data)
            data.merge!(payment_initiation_response: payment_initiation_response)
            pp "Step 3: Payment initiation in :payment_initiation executed"
            pp data[:payment_initiation_response]
            data
        end

        step "Review payment in :payment_initiation" do |data|
            data[:url] = "#{data[:base_url]}/oauth2/authorize?response_type=#{data[:response_type]}&redirect_uri=#{data[:redirect_uri]}&scope=#{data[:scope]}&client_id=#{data[:client_id]}&paymentid=#{data[:payment_initiation_response]["payment"]["paymentId"]}"
            pp data[:url]
            # Open the URL in the default web browser
            puts "Awaiting Authorization-COPY PASTE THE URL"
            system("xdg-open '#{data[:url]}'") if RUBY_PLATFORM.include?("linux")  # Linux
            system("open '#{data[:url]}'") if RUBY_PLATFORM.include?("darwin")  # Mac
            system("start #{data[:url]}") if RUBY_PLATFORM.include?("mswin|mingw")  # Windows
            # Step 3: Pause execution and wait for user input
            redirected_url = $stdin.gets.chomp.strip  # Ensures input is read properly
            # Step 4: Extract authorization code from the redirected URL
            parsed_params = CGI.parse(URI.parse(redirected_url).query)
            auth_data = {
                code: parsed_params["code"]&.first
            }
            data.merge!(auth_data: auth_data)
            pp "Step 4: Select accounts for subscription id and get authorization code in :show_accounts executed"
            pp data[:auth_data]
            data
        end

        step "Get access token in :payment_initiation" do |data|
            data[:grant_type] = "authorization_code"
            data[:payload] = {
                "client_id" => data[:client_id],
                "client_secret" => data[:client_secret],
                "scope" => data[:scope],
                "grant_type" => data[:grant_type],
                "code" => data[:auth_data][:code]
            }
            data[:headers] = {
                "Content-Type" => "application/x-www-form-urlencoded",
                "Accept" => "application/json"
            }
            data[:url] = "#{data[:base_url]}/oauth2/token"
            if data[:headers]["Content-Type"] == "application/x-www-form-urlencoded"
                second_access_token_response = Navesti::ExternalServices.get_access_token(data, nil)
            else
                second_access_token_response = Navesti::ExternalServices.get_access_token(data)
            end
            data.merge!(second_access_token_response: second_access_token_response)
            pp "Step 5: Get access token in :payment_initiation executed"
            pp data[:second_access_token_response]
            pp data
        end

        step "Payment initiation in :payment_initiation" do |data|
            data[:headers] = {
                "Content-Type" => "application/json",
                "Accept" => "application/json",
                "Authorization" => "Bearer #{data[:second_access_token_response]["access_token"]}",
                "timeStamp" => Time.now.utc.iso8601,
                "journeyId" => SecureRandom.uuid    
            }
            data[:url] = data[:base_url] + "/v1/payments/#{data[:payment_initiation_response]["payment"]["paymentId"]}/execute"
            data[:payload] = {}
            payment_initiation_response = Navesti::ExternalServices.initiate_payment(data)
            data.merge!(payment_initiation_response: payment_initiation_response)
            pp "Step 6: Payment initiation in :payment_initiation executed"
            pp data[:payment_initiation_response]
            data[:payment_initiation_response]
        end
    end

end
    
    
