require_relative 'navesti'
require 'pp'
require 'cgi'

Navesti.define :show_accounts do
    format :json

    source :show_accounts_parameters do
    end

    workflow do
        step "Get authorization code" do |data|
            data[:url] = "https://my.nbg.gr/identity/connect/authorize?client_id=#{data[:client_id]}&response_type=#{data[:response_type]}&scope=#{data[:scope]}&redirect_uri=#{data[:redirect_uri]}"
            data[:headers] = {
                "Content-Type" => "application/x-www-form-urlencoded"
            }
            authorization_code_response = Navesti::ExternalServices.get_authorization_code(data)
            data.merge!(authorization_code_response: authorization_code_response)
            url = authorization_code_response.match(/https:[^']+/)
            # Open the URL in the default web browser
            puts "Awaiting Authorization"
            puts "After authorization, paste the redirected URL here:"
            system("xdg-open '#{url}'") if RUBY_PLATFORM.include?("linux")  # Linux
            system("open '#{url}'") if RUBY_PLATFORM.include?("darwin")  # Mac
            system("start #{url}") if RUBY_PLATFORM.include?("mswin")  # Windows
            # Step 3: Pause execution and wait for user input
            redirected_url = $stdin.gets.chomp.strip  # Ensures input is read properly
            # Step 4: Extract authorization code from the redirected URL
            parsed_params = CGI.parse(URI.parse(redirected_url).query)
            auth_data = {
                code: parsed_params["code"]&.first
            }
            data.merge!(auth_data: auth_data)
            pp "Step 1: Get authorization code executed"
            pp data[:auth_data]
            data
        end

        step "Get access token" do |data|
            data[:url] = "https://my.nbg.gr/identity/connect/token"
            data[:headers].merge!(
                "Content-Type" => "application/x-www-form-urlencoded",
                "Accept" => "application/json"
            )
            data[:payload] = {
                grant_type: data[:grant_type],
                client_id: data[:client_id],
                client_secret: data[:client_secret],
                code: data[:auth_data][:code],
                redirect_uri: data[:redirect_uri]
            }
            if data[:headers]["Content-Type"] == "application/x-www-form-urlencoded"
                access_token_response = Navesti::ExternalServices.get_access_token(data, nil)
            end
            data.merge!(access_token_response: access_token_response)
            pp "Step 2: Get access token executed"
            pp data[:access_token_response]
            data
        end

        step "Create Sandbox" do |data|
            data[:url] = "#{data[:base_accounts_url]}/sandbox"
            data[:sandbox_id] = 'sandbox-1-accounts'
            data[:headers].merge!(
                "Content-Type" => "application/json",
                "Accept" => "application/json",
                "Client-Id" => data[:client_id],
                "Authorization" => "Bearer #{data[:access_token_response]["access_token"]}"
            )
            data[:payload] = {
                'sandboxId' => data[:sandbox_id]
            }
            create_sandbox_response = Navesti::ExternalServices.create_sandbox(data)
            data.merge!(create_sandbox_response: create_sandbox_response)
            pp "Step 3: Create Sandbox executed"
            pp data[:create_sandbox_response]
            data
        end

        step "Create Account Access consent" do |data|
            data[:url] = "#{data[:base_accounts_url]}/consents"
            data[:headers].merge!(
                "Content-Type" => "application/json",
                "Accept" => "application/json",
                "Client-Id" => data[:client_id],
                "Authorization" => "Bearer #{data[:access_token_response]["access_token"]}",
                "X-Request-Id" => SecureRandom.uuid,
                "sandbox-id" => data[:sandbox_id],
                "tpp-callback-url" => data[:redirect_uri],
                "psu-ip-address" => data[:psu_ip_address]
            )
            data[:payload] = {
                "access": {
                "accounts": [],
                "balances": [],
                "transactions": [],
                "availableAccounts": "allAccounts"
            },
            "recurringIndicator": false,
            "validUntil": "#{Date.today + 1}",
            "frequencyPerDay": 4,
            "combinedServiceIndicator": false
            }
            consent_response = Navesti::ExternalServices.create_consent(data)
            data.merge!(consent_response: consent_response)
            pp "Step 4: Create Account Access consent executed"
            pp data[:consent_response]
            data
        end

        step "Accept Account Access consent" do |data|
            url = data[:consent_response]['_links']['scaRedirect']['href']
            # Open the URL in the default web browser
            puts "Awaiting Authorization"
            puts "After authorization, just type 'ok' to proceed:"
            puts "Waiting 3 seconds for browser to open"
            sleep 3
            system("xdg-open '#{url}'") if RUBY_PLATFORM.include?("linux")  # Linux
            system("open '#{url}'") if RUBY_PLATFORM.include?("darwin")  # Mac
            system("start #{url}") if RUBY_PLATFORM.include?("mswin")  # Windows
            # Step 3: Pause execution and wait for user input
            ok_flag = $stdin.gets.chomp.strip  # Ensures input is read properly
            data
        end

        step "Get Account Access consent status" do |data|
            data[:url] = "#{data[:base_accounts_url]}/consents/#{data[:consent_response]["consentId"]}/status"
            data[:headers].merge!(
                "Content-Type" => "application/json",
                "Accept" => "application/json",
                "Client-Id" => data[:client_id],
                "Authorization" => "Bearer #{data[:access_token_response]["access_token"]}",
                "X-Request-Id" => SecureRandom.uuid,
                "sandbox-id" => data[:sandbox_id],
                "psu-ip-address" => data[:psu_ip_address]
            )
            consent_status_response = Navesti::ExternalServices.get_consent_status(data)
            data.merge!(consent_status_response: consent_status_response)
            pp "Step 5: Get Account Access consent status executed"
            pp data[:consent_status_response]
            data
        end

        step "Show accounts" do |data|
            data[:url] = "#{data[:base_accounts_url]}/accounts?withBalance=true"
            data[:headers].merge!(
                "Content-Type" => "application/json",
                "Accept" => "application/json",
                "Client-Id" => data[:client_id],
                "Authorization" => "Bearer #{data[:access_token_response]["access_token"]}",
                "X-Request-Id" => SecureRandom.uuid,
                "sandbox-id" => data[:sandbox_id],
                "psu-ip-address" => data[:psu_ip_address],
                "consent-id" => data[:consent_status_response]["consentId"]
            )
            accounts_response = Navesti::ExternalServices.show_accounts(data)
            data.merge!(accounts_response: accounts_response)
            pp "Step 1: Show accounts executed"
            pp data[:accounts_response]
            data[:accounts_response]
        end
    end
end

Navesti.define :show_account do
    format :json

    source :show_account_parameters do
    end
    
    workflow do
        step "Show account" do |data|
            data[:accounts_response] = Navesti.run(:show_accounts, data)
            data[:url] = "#{data[:base_accounts_url]}/accounts/#{data[:accounts_response]["accounts"][0]["resourceId"]}"
            data[:headers].merge!(
                "Content-Type" => "application/json",
                "Accept" => "application/json",
                "Client-Id" => data[:client_id],
                "Authorization" => "Bearer #{data[:access_token_response]["access_token"]}",
                "X-Request-Id" => SecureRandom.uuid,
                "sandbox-id" => data[:sandbox_id],
                "psu-ip-address" => data[:psu_ip_address],
                "consent-id" => data[:consent_status_response]["consentId"]
            )
            account_response = Navesti::ExternalServices.show_account(data)
            data.merge!(account_response: account_response)
            pp "Step 7: Show account executed"
            pp data[:account_response]
            data[:account_response]
        end
    end
end

Navesti.define :show_transactions do
    format :json

    source :show_transactions_parameters do
    end
    
    workflow do
        step "Show account transactions" do |data|
            data[:account_response] = Navesti.run(:show_account, data)
            data[:url] = "#{data[:base_accounts_url]}/accounts/#{data[:account_response]["account"]["resourceId"]}/transactions?bookingStatus=booked"
            data[:headers].merge!(
                "Content-Type" => "application/json",
                "Accept" => "application/json",
                "Client-Id" => data[:client_id],
                "Authorization" => "Bearer #{data[:access_token_response]["access_token"]}",
                "X-Request-Id" => SecureRandom.uuid,
                "sandbox-id" => data[:sandbox_id],
                "psu-ip-address" => data[:psu_ip_address],
                "consent-id" => data[:consent_status_response]["consentId"]
            )
            transactions_response = Navesti::ExternalServices.show_account_transactions(data)
            data.merge!(transactions_response: transactions_response)
            pp "Step 1: Show transactions executed"
            pp data[:transactions_response]
            data[:transactions_response]
        end
    end
end

Navesti.define :show_balances do
    format :json

    source :show_balances_parameters do
    end

    workflow do
        step "Show account balances" do |data|
            data[:account_response] = Navesti.run(:show_account, data)
            data[:url] = "#{data[:base_accounts_url]}/accounts/#{data[:account_response]["account"]["resourceId"]}/balances"
            data[:headers].merge!(
                "Content-Type" => "application/json",
                "Accept" => "application/json",
                "Client-Id" => data[:client_id],
                "Authorization" => "Bearer #{data[:access_token_response]["access_token"]}",
                "X-Request-Id" => SecureRandom.uuid,
                "sandbox-id" => data[:sandbox_id],
                "psu-ip-address" => data[:psu_ip_address],
                "consent-id" => data[:consent_status_response]["consentId"]
            )
            balances_response = Navesti::ExternalServices.show_account_balances(data)
            data.merge!(balances_response: balances_response)
            pp "Step 1: Show balances executed"
            pp data[:balances_response]
            data[:balances_response]
        end
    end
end

Navesti.define :payment_initiation do
    format :json

    source :payment_initiation_parameters do
    end

    workflow do
        step "Run the :show_account workflow" do |data|
            data[:account_response] = Navesti.run(:show_account, data)
            data
        end

        step "Get authorization code" do |data|
            data[:scope] = "sandbox-bg-ob-payments offline_access"
            data[:url] = "https://my.nbg.gr/identity/connect/authorize?client_id=#{data[:client_id]}&response_type=#{data[:response_type]}&scope=#{data[:scope]}&redirect_uri=#{data[:redirect_uri]}"
            data[:headers] = {
                "Content-Type" => "application/x-www-form-urlencoded"
            }
            authorization_code_response = Navesti::ExternalServices.get_authorization_code(data)
            data.merge!(authorization_code_response: authorization_code_response)
            url = authorization_code_response.match(/https:[^']+/)
            # Open the URL in the default web browser
            puts "Awaiting Authorization"
            puts "After authorization, paste the redirected URL here:"
            system("xdg-open '#{url}'") if RUBY_PLATFORM.include?("linux")  # Linux
            system("open '#{url}'") if RUBY_PLATFORM.include?("darwin")  # Mac
            system("start #{url}") if RUBY_PLATFORM.include?("mswin")  # Windows
            # Step 3: Pause execution and wait for user input
            redirected_url = $stdin.gets.chomp.strip  # Ensures input is read properly
            # Step 4: Extract authorization code from the redirected URL
            parsed_params = CGI.parse(URI.parse(redirected_url).query)
            auth_data = {
                code: parsed_params["code"]&.first
            }
            data.merge!(auth_data: auth_data)
            pp "Step 1: Get authorization code executed"
            pp data[:auth_data]
            data
        end

        step "Get access token" do |data|
            data[:url] = "https://my.nbg.gr/identity/connect/token"
            data[:headers].merge!(
                "Content-Type" => "application/x-www-form-urlencoded",
                "Accept" => "application/json"
            )
            data[:payload] = {
                grant_type: data[:grant_type],
                client_id: data[:client_id],
                client_secret: data[:client_secret],
                code: data[:auth_data][:code],
                redirect_uri: data[:redirect_uri]
            }
            if data[:headers]["Content-Type"] == "application/x-www-form-urlencoded"
                access_token_response = Navesti::ExternalServices.get_access_token(data, nil)
            end
            data.merge!(access_token_response: access_token_response)
            pp "Step 2: Get access token executed"
            pp data[:access_token_response]
            data
        end

        step "Create Sandbox" do |data|
            data[:url] = "#{data[:base_payments_url]}/sandbox"
            data[:sandbox_id] = "sandbox-1-payments"
            data[:headers].merge!(
                "Content-Type" => "application/json",
                "Accept" => "application/json",
                "Client-Id" => data[:client_id],
                "Authorization" => "Bearer #{data[:access_token_response]["access_token"]}",
                "X-Request-Id" => SecureRandom.uuid,
                "sandbox-id" => data[:sandbox_id],
                "psu-ip-address" => data[:psu_ip_address]
            )
            sandbox_response = Navesti::ExternalServices.create_sandbox(data)
            data.merge!(sandbox_response: sandbox_response)
            pp "Step 3: Create Sandbox executed"
            pp data[:sandbox_response]
            data
        end

        step "Initiate sepa credit transfer" do |data|
            data[:url] = "#{data[:base_payments_url]}/payments/sepa-credit-transfers"
            data[:headers].merge!(
                "Content-Type" => "application/json",
                "Accept" => "application/json",
                "Client-Id" => data[:client_id],
                "Authorization" => "Bearer #{data[:access_token_response]["access_token"]}",
                "X-Request-Id" => SecureRandom.uuid,
                "sandbox-id" => data[:sandbox_id],
                "psu-ip-address" => data[:psu_ip_address],
                "consent-id" => data[:consent_status_response]["consentId"]
            )
            data[:payload] = {
                "endToEndIdentification": "#{SecureRandom.uuid.delete('-')}",
                "debtorAccount": {
                    "iban": "GR3201106970000069774934603",
                    "bban": "BARC12345612345678",
                    "msisdn": "+306912345678",
                    "taxId": "000000009",
                    "currency": "EUR"
                },
                "debtorName": "John Doe",
                "instructedAmount": {
                    "currency": "EUR",
                    "amount": "1"
                },
                "creditorAccount": {
                    "iban": "GR0601100400000004001504283",
                    "currency": "EUR"
                },
                "creditorName": "John Doe",
                "creditorAddress": {
                    "streetName": "123 Main St",
                    "buildingNumber": "123",
                    "townName": "Athens",
                    "postCode": "12345",
                    "country": "GR"
                },
                "creditorAgent": "ETHNGRAA",
                "creditorAgentName": "ETHNGRAA",
                "remittanceInformationUnstructured": "Payment for goods",
                "chargeBearer": "Shared",
                "priorityCode": "Normal"
            }
            payment_initiation_response = Navesti::ExternalServices.initiate_payment(data)
            data.merge!(payment_initiation_response: payment_initiation_response)
            pp "Step 6: Initiate payment executed"
            pp data[:payment_initiation_response]
            data
        end

        step "Authorize payment" do |data|
            data[:url] = data[:payment_initiation_response]["_links"]["scaRedirect"]["href"]
            # Open the URL in the default web browser
            puts "Awaiting Authorization"
            puts "After authorization, just type 'ok' to proceed:"
            puts "Waiting 2 seconds for browser to open"
            sleep 2
            system("xdg-open '#{data[:url]}'") if RUBY_PLATFORM.include?("linux")  # Linux
            system("open '#{data[:url]}'") if RUBY_PLATFORM.include?("darwin")  # Mac
            system("start #{data[:url]}") if RUBY_PLATFORM.include?("mswin")  # Windows
            # Step 3: Pause execution and wait for user input
            ok_flag = $stdin.gets.chomp.strip  # Ensures input is read properly
            data
        end
        step "Get payment status" do |data|
            data[:url] = "#{data[:base_payments_url]}/payments/sepa-credit-transfers/#{data[:payment_initiation_response]["paymentId"]}/status"
            data[:headers].merge!(
                "Content-Type" => "application/json",
                "Accept" => "application/json",
                "Client-Id" => data[:client_id],
                "Authorization" => "Bearer #{data[:access_token_response]["access_token"]}",
                "X-Request-Id" => SecureRandom.uuid,
                "sandbox-id" => data[:sandbox_id],
                "psu-ip-address" => data[:psu_ip_address],
                "consent-id" => data[:consent_status_response]["consentId"]
            )
            payment_status_response = Navesti::ExternalServices.get_payment_status(data)
            data.merge!(payment_status_response: payment_status_response)
            pp "Step 7: Get payment status executed"
            pp data[:payment_status_response]
            data[:payment_status_response]
        end
    end
end
                