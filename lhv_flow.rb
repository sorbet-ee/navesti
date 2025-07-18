require_relative 'navesti'
require 'pp'
require 'json'

Navesti.define :show_account do
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
            pp data[:url]
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
            pp data[:consent_response]
            data
        end
    end
end