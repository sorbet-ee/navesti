require_relative 'navesti'
require 'pp'
require 'json'

Navesti.define :show_accounts do
    format :json
    source :show_account_parameters do
    end
    workflow do
        step "Create authorization" do |data|
            pp "Step 1: Create authorization started..."
            data[:url] = "#{data[:base_url]}/oauth/authorisations"
            data[:headers] = {
                'Accept' => 'application/hal+json;charset=UTF-8',
                'PSU-ID' => data[:psu_id],
                'PSU-Corporate-ID' => data[:psu_corporate_id],
                'X-Request-ID' => SecureRandom.uuid,
                'Content-Type' => 'application/json;charset=UTF-8'
            }
            data[:payload] = {
                "authenticationMethodId" => data[:authentication_method_id]
            }
            authorization_response = Navesti::ExternalServices.initiate_authorization(data)
            data.merge!(authorization_response: authorization_response)
            pp "Step 1: Create authorization executed"
            pp data[:authorization_response]
            data
        end
        
        step "Wait for the authorization to be completed" do |data|
            pp "Step 2: Wait for the authorization to be completed started..."
            data[:url] = "#{data[:base_url]}/oauth/authorisations/#{data[:authorization_response]['authorisationId']}"
            data[:headers] = {
                'Accept' => 'application/hal+json;charset=UTF-8',
                'PSU-ID' => data[:psu_id],
                'PSU-Corporate-ID' => data[:psu_corporate_id],
                'X-Request-ID' => SecureRandom.uuid,
                'Content-Type' => 'application/json;charset=UTF-8'
            }
            sleep 10
            authorization_status_response = Navesti::ExternalServices.get_sca_status(data)
            data.merge!(authorization_status_response: authorization_status_response)
            pp "Step 2: Wait for the authorization to be completed executed"
            pp data[:authorization_status_response]
            data
        end

        step "Get access token" do |data|
            pp "Step 3: Get access token started..."
            data[:url] = "#{data[:base_url].gsub("/v1", "")}/oauth/token"
            data[:headers] = {
                'Accept' => 'application/hal+json;charset=UTF-8',
                'PSU-ID' => data[:psu_id],
                'PSU-Corporate-ID' => data[:psu_corporate_id],
                'X-Request-ID' => SecureRandom.uuid,
                'Content-Type' => 'application/x-www-form-urlencoded'
            }
            data[:payload] = {
                "grant_type" => "authorization_code",
                "client_id" => data[:client_id],
                "code" => data[:authorization_status_response]['authorisationCode']
            }
            if data[:headers]["Content-Type"] == "application/x-www-form-urlencoded"
                access_token_response = Navesti::ExternalServices.get_access_token(data, nil)
            end
            data.merge!(access_token_response: access_token_response)
            pp "Step 3: Get access token executed"
            pp data[:access_token_response]
            data
        end

        step "Create consent" do |data|
            pp "Step 4: Create consent started..."
            data[:url] = "#{data[:base_url]}/consents"
            data[:headers] = {
                'Accept' => 'application/hal+json;charset=UTF-8',
                'PSU-ID' => data[:psu_id],
                'PSU-Corporate-ID' => data[:psu_corporate_id],
                'X-Request-ID' => SecureRandom.uuid,
                'Content-Type' => 'application/json;charset=UTF-8',
                'Authorization' => "Bearer #{data[:access_token_response]['access_token']}",
                'PSU-IP-Address' => data[:psu_ip_address],
                'TPP-Redirect-URI' => data[:tpp_redirect_uri],
                'TPP-Redirect-Preferred' =>  data[:tpp_redirect_preferred]
            }
            data[:payload] = {
                "access" => {
                    "balances" => [{ "iban" => data[:iban] }],
                    "transactions" => [{ "iban" => data[:iban] }],
                    "availableAccounts" => "allAccounts"
                },
                "recurringIndicator" => true,
                "validUntil" => "#{Date.today + 1}",
                "frequencyPerDay" => 50,
                "combinedServiceIndicator" => false
            }
            consent_response = Navesti::ExternalServices.create_consent(data)
            data.merge!(consent_response: consent_response)
            pp "Step 4: Create consent executed"
            data
        end

        step "Start decoupled consent signing" do |data|
            pp "Step 5: Start decoupled consent signing started..."
            data[:url] = "#{data[:base_url]}/consents/#{data[:consent_response]['consentId']}/authorisations"
            data[:headers] = {
                'Accept' => 'application/hal+json;charset=UTF-8',
                'PSU-ID' => data[:psu_id],
                'PSU-Corporate-ID' => data[:psu_corporate_id],
                'X-Request-ID' => SecureRandom.uuid,
                'Content-Type' => 'application/json;charset=UTF-8',
                'Authorization' => "Bearer #{data[:access_token_response]['access_token']}",
                'PSU-IP-Address' => data[:psu_ip_address],
                'TPP-Redirect-URI' => data[:tpp_redirect_uri],
                'TPP-Redirect-Preferred' =>  data[:tpp_redirect_preferred]
            }
            data[:payload] = {
                "authenticationMethodId" => data[:authentication_method_id]
            }
            consent_signing_response = Navesti::ExternalServices.initiate_authorization(data)
            data.merge!(consent_signing_response: consent_signing_response)
            pp "Step 5: Start decoupled consent signing executed"
            data
        end

        step "Get sca status for consent signing" do |data|
            pp "Step 6: Get sca status for consent signing started..."
            data[:url] = "#{data[:base_url]}/consents/#{data[:consent_response]['consentId']}/authorisations/#{data[:consent_signing_response]['authorisationId']}"
            data[:headers] = {
                'Accept' => 'application/hal+json;charset=UTF-8',
                'PSU-ID' => data[:psu_id],
                'PSU-Corporate-ID' => data[:psu_corporate_id],
                'X-Request-ID' => SecureRandom.uuid,
                'Content-Type' => 'application/json;charset=UTF-8',
                'Authorization' => "Bearer #{data[:access_token_response]['access_token']}",
                'PSU-IP-Address' => data[:psu_ip_address],
                'TPP-Redirect-URI' => data[:tpp_redirect_uri],
                'TPP-Redirect-Preferred' =>  data[:tpp_redirect_preferred]
            }
            sleep 10
            authorization_status_response = Navesti::ExternalServices.get_sca_status(data)
            data.merge!(authorization_status_response: authorization_status_response)
            pp "Step 6: Get sca status for consent signing executed"
            pp data[:authorization_status_response]
            data
        end

        step "Get consent details" do |data|
            pp "Step 7: Get consent details started..."
            data[:url] = "#{data[:base_url]}/consents/#{data[:consent_response]['consentId']}"
            data[:headers] = {
                'Accept' => 'application/hal+json;charset=UTF-8',
                'PSU-ID' => data[:psu_id],
                'PSU-Corporate-ID' => data[:psu_corporate_id],
                'X-Request-ID' => SecureRandom.uuid,
                'Content-Type' => 'application/json;charset=UTF-8',
                'Authorization' => "Bearer #{data[:access_token_response]['access_token']}",
                'PSU-IP-Address' => data[:psu_ip_address],
                'TPP-Redirect-URI' => data[:tpp_redirect_uri],
                'TPP-Redirect-Preferred' =>  data[:tpp_redirect_preferred]
            }
            consent_details_response = Navesti::ExternalServices.get_consent_details(data)
            data.merge!(consent_details_response: consent_details_response)
            pp "Step 7: Get consent details executed"
            pp data[:consent_details_response]
            data
        end

        step "Show accounts" do |data|
            pp "Step 8: Show accounts started..."
            data[:url] = "#{data[:base_url]}/accounts"
            data[:headers] = {
                'Accept' => 'application/hal+json;charset=UTF-8',
                'PSU-ID' => data[:psu_id],
                'PSU-Corporate-ID' => data[:psu_corporate_id],
                'X-Request-ID' => SecureRandom.uuid,
                'Content-Type' => 'application/json;charset=UTF-8',
                'Authorization' => "Bearer #{data[:access_token_response]['access_token']}",
                'PSU-IP-Address' => data[:psu_ip_address],
                'TPP-Redirect-URI' => data[:tpp_redirect_uri],
                'TPP-Redirect-Preferred' =>  data[:tpp_redirect_preferred],
                'Consent-Id' => data[:consent_response]['consentId']
            }
            accounts_response = Navesti::ExternalServices.show_accounts(data)
            data.merge!(accounts_response: accounts_response)
            pp "Step 8: Show accounts executed"
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
            pp "Step 1: Show account started..."
            data[:accounts_response] = Navesti.run(:show_accounts, data)
            data[:url] = "#{data[:base_url]}/accounts/#{data[:accounts_response]["accounts"][0]["resourceId"]}"
            data[:headers].merge!(
                "X-Request-ID" => SecureRandom.uuid
            )
            account_response = Navesti::ExternalServices.show_account(data)
            data.merge!(account_response: account_response)
            pp "Step 1: Show account executed"
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
            pp "Step 1: Show balances started..."
            data[:account_response] = Navesti.run(:show_account, data)
            data[:url] = "#{data[:base_url]}/accounts/#{data[:accounts_response]["accounts"][0]["resourceId"]}/balances"
            data[:headers].merge!(
                "X-Request-ID" => SecureRandom.uuid
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
            pp "Step 1: Show transactions started..."
            data[:account_response] = Navesti.run(:show_account, data)
            data[:url] = "#{data[:base_url]}/accounts/#{data[:accounts_response]["accounts"][0]["resourceId"]}/transactions?dateFrom=#{data[:date_from]}&dateTo=#{data[:date_to]}&bookingStatus=#{data[:booking_status]}"
            data[:headers].merge!(
                "X-Request-ID" => SecureRandom.uuid
            )
            transactions_response = Navesti::ExternalServices.show_account_transactions(data)
            data.merge!(transactions_response: transactions_response)
            pp "Step 1: Show transactions executed"
            pp data[:transactions_response]
            data[:transactions_response]
        end
    end
end
