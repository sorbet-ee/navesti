require_relative 'navesti'
require 'pp'
require 'launchy'


Navesti.define :show_accounts do
    format :json

    source :show_accounts_parameters do
    end

    workflow do
        step "Get access token" do |data|
            puts "Step 1: Get access token started..."
            data[:url] = "#{data[:base_url]}/token"
            data[:headers] = {
                "Content-Type" => "application/x-www-form-urlencoded"
            }
            data[:payload] = {
                grant_type: data[:grant_type],
                client_id: data[:client_id],
                scope: data[:scope]
            }
            if data[:headers]["Content-Type"] == "application/x-www-form-urlencoded"
                access_token_response = Navesti::ExternalServices.get_access_token(data, nil)
            end
            data.merge!(access_token_response: access_token_response)
            pp "Step 2: Get access token executed"
            pp data[:access_token_response]
            data
        end

        step "Create account access consent" do |data|
            puts "Step 2: Create account access consent started..."
            data[:url] = "#{data[:base_url]}/account-access-consents"
            data[:headers].merge!(
                "Content-Type" => "application/json",
                "Authorization" => "Bearer #{data[:access_token_response]["access_token"]}",
                "x-fapi-financial-id" => '001580000103UAvAAM'
            )
            data[:payload] = {
                'Data' => {
                    'Permissions' => [
                        'ReadAccountsBasic',
                        'ReadAccountsDetail',
                        'ReadBalances',
                        'ReadBeneficiariesBasic',
                        'ReadBeneficiariesDetail',
                        'ReadDirectDebits',
                        'ReadStandingOrdersBasic',
                        'ReadStandingOrdersDetail',
                        'ReadTransactionsBasic',
                        'ReadTransactionsDetail',
                        'ReadTransactionsCredits',
                        'ReadTransactionsDebits'
                    ],
                    'ExpirationDateTime' => '2025-12-02T00:00:00+00:00',
                    'TransactionFromDateTime' => '2025-09-03T00:00:00+00:00',
                    'TransactionToDateTime' => '2025-12-03T00:00:00+00:00'
                },
                'Risk' => {}
            }
            consent_response = Navesti::ExternalServices.create_consent(data)
            data.merge!(consent_response: consent_response)
            pp "Step 4: Create Account Access consent executed"
            pp data[:consent_response]
            data
        end

        step "Make the jwt" do |data|
            puts "Step 5: Make the jwt started..."
            data[:jwt] = {
                header: {
                    'alg' => 'PS256',
                    'kid' => '007'
                },
                payload: {
                    'response_type' => 'code id_token',
                    'client_id' => data[:client_id],
                    'redirect_uri' => 'https://www.google.com',
                    'aud' => 'https://sandbox-oba-auth.revolut.com',
                    'scope' => 'accounts',
                    'nbf' => Time.now.to_i,
                    'exp' => Time.now.to_i + 60,
                    'claims' => {
                        'id_token' => {
                            'openbanking_intent_id' => {
                                'value' => "#{data[:consent_response]['Data']['ConsentId']}"
                            }
                        }
                    }
                }
            }
            data[:jwt][:encoded] = JWT.encode(data[:jwt][:payload], data[:ssl_options][:client_key], 'PS256', data[:jwt][:header])
            data
        end

        step "Open the browser and authorize" do |data|
            puts "Step 6: Open the browser started..."
            data[:url] = "https://sandbox-oba.revolut.com/ui/index.html?response_type=#{data[:response_type]}&scope=#{data[:jwt][:payload]['scope']}&redirect_uri=#{data[:jwt][:payload]['redirect_uri']}&client_id=#{data[:client_id]}&request=#{data[:jwt][:encoded]}"
    
            # Step 1: Prompt user to complete authorization
            puts "Open the following URL in your browser to authorize: "
            Launchy.open(data[:url])
            puts "After authorization, paste the redirected URL here: "
    
            # Step 2: Pause execution and wait for user input
            redirected_url = $stdin.gets.chomp.strip  # Ensures input is read properly

            # Validate the URL format
            unless redirected_url.match?(/^https?:\/\/\S+/)
              raise URI::InvalidURIError, "Invalid URL provided: #{redirected_url}"
            end

            # Step 3: Extract authorization code from the redirected URL
            parsed_params = CGI.parse(URI.parse(redirected_url).query)
            auth_data = {
              code: parsed_params["code"]&.first,
              id_token: parsed_params["id_token"]&.first
            }

            data.merge!(auth_data: auth_data)
            data
        end

        step "Get access token after authorization" do |data|
            puts "Step 7: Get access token after authorization started..."
            data[:url] = "#{data[:base_url]}/token"
            data[:grant_type] = "authorization_code"
            data[:headers] = {
                "Content-Type" => "application/x-www-form-urlencoded"
            }
            data[:payload] = {
                grant_type: data[:grant_type],
                code: data[:auth_data][:code],

            }
            if data[:headers]["Content-Type"] == "application/x-www-form-urlencoded"
                access_token_response = Navesti::ExternalServices.get_access_token(data, nil)
            end
            data.merge!(access_token_response: access_token_response)
            pp "Step 8: Get access token after authorization executed"
            pp data[:access_token_response]
            data
        end

        step "Get accounts" do |data|
            puts "Step 9: Get accounts started..."
            data[:url] = "#{data[:base_url]}/accounts"
            data[:headers].merge!(
                "Content-Type" => "application/json",
                "Authorization" => "Bearer #{data[:access_token_response]["access_token"]}",
                "x-fapi-financial-id" => '001580000103UAvAAM'
            )
            accounts_response = Navesti::ExternalServices.show_accounts(data)
            data.merge!(accounts_response: accounts_response)
            pp "Step 10: Get accounts executed"
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
            puts "Step 1: Show account started..."
            data[:accounts_response] = Navesti.run(:show_accounts, data)
            data[:url] = "#{data[:base_url]}/accounts/#{data[:accounts_response]["Data"]["Account"][0]["AccountId"]}"
            data[:headers].merge!(
                "Content-Type" => "application/json",
                "Authorization" => "Bearer #{data[:access_token_response]["access_token"]}",
                "x-fapi-financial-id" => '001580000103UAvAAM'
            )
            account_response = Navesti::ExternalServices.show_account(data)
            data.merge!(account_response: account_response)
            pp "Step 2: Show account executed"
            pp data[:account_response]
            data[:account_response]
        end
    end
end

Navesti.define :show_balances do
    format :json

    source :show_balances_parameters do
    end
    
    workflow do
        step "Show balances" do |data|
            puts "Step 1: Show balances started..."
            data[:account_response] = Navesti.run(:show_account, data)
            data[:url] = "#{data[:base_url]}/accounts/#{data[:account_response]["Data"]["Account"][0]["AccountId"]}/balances"
            data[:headers].merge!(
                "Content-Type" => "application/json",
                "Accept" => "application/json",
                "Authorization" => "Bearer #{data[:access_token_response]["access_token"]}",
                "x-fapi-financial-id" => '001580000103UAvAAM'
            )
            balances_response = Navesti::ExternalServices.show_account_balances(data)
            data.merge!(balances_response: balances_response)
            pp "Step 1: Show balances executed"
            pp data[:balances_response]
            data[:balances_response]
        end
    end
end

Navesti.define :show_transactions do
    format :json

    source :show_transactions_parameters do
    end
    
    workflow do
        step "Show transactions" do |data|
            puts "Step 1: Show transactions started..."
            data[:account_response] = Navesti.run(:show_account, data)
            data[:url] = "#{data[:base_url]}/accounts/#{data[:account_response]["Data"]["Account"][0]["AccountId"]}/beneficiaries"
            data[:headers].merge!(
                "Content-Type" => "application/json",
                "Accept" => "application/json",
                "Authorization" => "Bearer #{data[:access_token_response]["access_token"]}",
                "x-fapi-financial-id" => '001580000103UAvAAM'
            )
            transactions_response = Navesti::ExternalServices.show_account_transactions(data)
            data.merge!(transactions_response: transactions_response)
            pp "Step 1: Show transactions executed"
            pp data[:transactions_response]
            data[:transactions_response]
        end
    end
end

Navesti.define :domestic_payment_initiation do
    format :json

    source :domestic_payment_initiation_parameters do
    end
    
    workflow do

        step "Get access token" do |data|
            puts "Step 1: Get access token started..."
            data[:url] = "#{data[:base_url]}/token"
            data[:headers] = {
                "Content-Type" => "application/x-www-form-urlencoded"
            }
            data[:payload] = {
                grant_type: data[:grant_type],
                client_id: data[:client_id],
                scope: data[:scope]
            }
            if data[:headers]["Content-Type"] == "application/x-www-form-urlencoded"
                access_token_response = Navesti::ExternalServices.get_access_token(data, nil)
            end
            data.merge!(access_token_response: access_token_response)
            pp "Step 1: Get access token executed"
            pp data[:access_token_response]
            data
        end

        step "Create jwt for the consent" do |data|
            puts "Step 2: Create jwt for the consent started..."
            data[:url] = "#{data[:base_url]}/domestic-payment-consents"
            data[:jwt] = {
                header: {
                    'typ' => 'JOSE',
                    'alg' => 'PS256',
                    'kid' => '007',
                    'crit' => ['http://openbanking.org.uk/tan'],
                    'http://openbanking.org.uk/tan' => 'johntheodorou.github.io'
                }
            }
            data[:payload] = {
                "Data" => {
                  "Initiation" => {
                    "InstructionIdentification" => "ID412",
                    "EndToEndIdentification" => "E2E123",
                    "InstructedAmount" => {
                      "Amount" => "55.0",
                      "Currency" => "GBP"
                    },
                    "CreditorAccount" => {
                      "SchemeName" => "UK.OBIE.SortCodeAccountNumber",
                      "Identification" => "11223321325698",
                      "Name" => "Receiver Co."
                    },
                    "RemittanceInformation" => {
                      "Unstructured" => "Shipment fee"
                    }
                  }
                },
                "Risk" => {
                  "PaymentContextCode" => "EcommerceGoods",
                  "MerchantCategoryCode" => "5967",
                  "MerchantCustomerIdentification" => "1238808123123",
                  "DeliveryAddress" => {
                    "AddressLine" => ["7"],
                    "StreetName" => "Apple Street",
                    "BuildingNumber" => "1",
                    "PostCode" => "E2 7AA",
                    "TownName" => "London",
                    "Country" => "UK"
                  }
                }
            }
            data[:jwt][:encoded] = JWT.encode(JSON.parse(data[:payload].to_json), data[:ssl_options][:client_key], 'PS256', data[:jwt][:header])
            data[:headers].merge!(
                "Content-Type" => "application/json",
                "Authorization" => "Bearer #{data[:access_token_response]["access_token"]}",
                "x-fapi-financial-id" => '001580000103UAvAAM',
                "x-jws-signature" => data[:jwt][:encoded],
                "x-idempotency-key" => '123456789'
            )
            domestic_payment_initiation_response = Navesti::ExternalServices.create_consent(data)
            data.merge!(domestic_payment_initiation_response: domestic_payment_initiation_response)
            pp "Step 2: Create domestic payment consent executed"
            pp data[:domestic_payment_initiation_response]
            data
        end

        step "Make the jwt" do |data|
            puts "Step 3: Make the jwt started..."
            data[:jwt] = {
                header: {
                    'alg' => 'PS256',
                    'kid' => '007'
                },
                payload: {
                    'response_type' => 'code id_token',
                    'client_id' => data[:client_id],
                    'redirect_uri' => 'https://www.google.com',
                    'aud' => 'https://sandbox-oba-auth.revolut.com',
                    'scope' => 'payments',
                    'nbf' => Time.now.to_i,
                    'exp' => Time.now.to_i + 60,
                    'claims' => {
                        'id_token' => {
                            'openbanking_intent_id' => {
                                'value' => "#{data[:domestic_payment_initiation_response]['Data']['ConsentId']}"
                            }
                        }
                    }
                }
            }
            data[:jwt][:encoded] = JWT.encode(data[:jwt][:payload], data[:ssl_options][:client_key], 'PS256', data[:jwt][:header])
            pp "Step 3: Make the jwt executed"
            pp data[:jwt]
            data
        end

        step "Open the browser and authorize" do |data|
            puts "Step 4: Open the browser started..."
            data[:url] = "https://sandbox-oba.revolut.com/ui/index.html?response_type=#{data[:response_type]}&scope=#{data[:jwt][:payload]['scope']}&redirect_uri=#{data[:jwt][:payload]['redirect_uri']}&client_id=#{data[:client_id]}&request=#{data[:jwt][:encoded]}"
    
            # Step 1: Prompt user to complete authorization
            puts "Open the following URL in your browser to authorize: "
            Launchy.open(data[:url])
            puts "After authorization, paste the redirected URL here: "
    
            # Step 2: Pause execution and wait for user input
            redirected_url = $stdin.gets.chomp.strip  # Ensures input is read properly

            # Validate the URL format
            unless redirected_url.match?(/^https?:\/\/\S+/)
              raise URI::InvalidURIError, "Invalid URL provided: #{redirected_url}"
            end

            # Step 3: Extract authorization code from the redirected URL
            parsed_params = CGI.parse(URI.parse(redirected_url).query)
            auth_data = {
              code: parsed_params["code"]&.first,
              id_token: parsed_params["id_token"]&.first
            }

            data.merge!(auth_data: auth_data)
            pp "Step 4: Open the browser executed"
            pp data[:auth_data]
            data
        end

        step "Get access token after authorization" do |data|
            puts "Step 5: Get access token after authorization started..."
            data[:url] = "#{data[:base_url]}/token"
            data[:grant_type] = "authorization_code"
            data[:headers] = {
                "Content-Type" => "application/x-www-form-urlencoded"
            }
            data[:payload] = {
                grant_type: data[:grant_type],
                code: data[:auth_data][:code],

            }
            if data[:headers]["Content-Type"] == "application/x-www-form-urlencoded"
                access_token_response = Navesti::ExternalServices.get_access_token(data, nil)
            end
            data.merge!(access_token_response: access_token_response)
            pp "Step 5: Get access token after authorization executed"
            pp data[:access_token_response]
            data
        end

        step "Initiate payment" do |data|
            puts "Step 6: Initiate payment started..."
            data[:url] = "#{data[:base_url]}/domestic-payments"
            data[:payload] = {
                'Data' => {
                  'ConsentId' => data[:domestic_payment_initiation_response]["Data"]["ConsentId"],
                  'Initiation' => {
                    'InstructionIdentification' => 'ID412',
                    'EndToEndIdentification' => 'E2E123',
                    'InstructedAmount' => {
                      'Amount' => '55.0',
                      'Currency' => 'GBP'
                    },
                    'CreditorAccount' => {
                      'SchemeName' => 'UK.OBIE.SortCodeAccountNumber',
                      'Identification' => '11223321325698',
                      'Name' => 'Receiver Co.'
                    },
                    'RemittanceInformation' => {
                      'Unstructured' => 'Shipment fee'
                    }
                  }
                },
                "Risk" => {
                  "PaymentContextCode" => "EcommerceGoods",
                  "MerchantCategoryCode" => "5967",
                  "MerchantCustomerIdentification" => "1238808123123",
                  "DeliveryAddress" => {
                    "AddressLine" => ["7"],
                    "StreetName" => "Apple Street",
                    "BuildingNumber" => "1",
                    "PostCode" => "E2 7AA",
                    "TownName" => "London",
                    "Country" => "UK"
                  }
                }
            }
            data[:jwt][:header] = {
                'typ' => 'JOSE',
                'alg' => 'PS256',
                'kid' => '007',
                'crit' => ['http://openbanking.org.uk/tan'],
                'http://openbanking.org.uk/tan' => 'johntheodorou.github.io'
            }
            data[:headers].merge!(
                "Content-Type" => "application/json",
                "Authorization" => "Bearer #{data[:access_token_response]["access_token"]}",
                "x-fapi-financial-id" => '001580000103UAvAAM'
            )
            data[:jwt][:encoded] = JWT.encode(JSON.parse(data[:payload].to_json), data[:ssl_options][:client_key], 'PS256', data[:jwt][:header])
            data[:headers].merge!("x-jws-signature" => data[:jwt][:encoded])
            data[:headers].merge!("x-idempotency-key" => '123456789')
            domestic_payment_initiation_response = Navesti::ExternalServices.create_consent(data)
            data.merge!(domestic_payment_initiation_response: domestic_payment_initiation_response)
            pp "Step 6: Initiate payment executed"
            pp data[:domestic_payment_initiation_response]
            data[:domestic_payment_initiation_response]
        end
    end
end


    
            
