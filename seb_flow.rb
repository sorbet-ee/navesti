require_relative 'navesti'
require 'pp'

Navesti.define :show_accounts do
    format :json

    source :initiate_authorization_parameters do
    end

    workflow do
        initial_data = nil
        step "Initiate Authorization in :show_accounts" do |data|
            url = "#{data[:base_url]}/auth/#{data[:authorization_version]}/authorizations"
            data[:url] = url
            data[:payload] = {
                "client_id" => data[:client_id],
                "scope" => data[:scope],
                "start_mode" => "ast"
            }
            initial_data = data
            initiate_authorization_response = Navesti::ExternalServices.initiate_authorization(data)
            initial_data.merge!(initiate_authorization_response: initiate_authorization_response)
            pp "Step 1: Initiating Authorization in :show_accounts executed"
            pp initial_data[:initiate_authorization_response]
            initial_data
        end

        step "Retrieve Token After Authorization in :show_accounts" do |data|
            data[:url] = data[:base_url] + "/auth/#{data[:authorization_version]}/authorizations/#{data[:initiate_authorization_response]["auth_req_id"]}"
            retrieve_token_after_authorization_response = Navesti::ExternalServices.retrieve_token_after_authorization_step(data)
            initial_data.merge!(retrieve_token_after_authorization_response: retrieve_token_after_authorization_response)
            pp "Step 2: Retrieve Token After Authorization in :show_accounts executed"
            pp initial_data[:retrieve_token_after_authorization_response]
            initial_data
        end

        step "Start Bank ID App Simulation in :show_accounts" do |data|
            data[:url] = data[:base_url] + "/open/sb/auth/mock/v1/login"
            data[:payload] = {
                "personal_identity_number" => "199311219639",
                "start_token" => data[:retrieve_token_after_authorization_response]["autostart_token"]
            }
            start_bank_id_app_simulation_response = Navesti::ExternalServices.start_bank_id_app_simulation(data)
            initial_data.merge!(start_bank_id_app_simulation_response: start_bank_id_app_simulation_response)
            pp "Step 3: Start Bank ID App Simulation in :show_accounts executed"
            pp initial_data[:start_bank_id_app_simulation_response]
            initial_data
        end

        step "Polling Status in :show_accounts" do |data|
            data[:url] = data[:base_url] + "/auth/#{data[:authorization_version]}/authorizations/#{data[:initiate_authorization_response]["auth_req_id"]}"
            polling_status_response = Navesti::ExternalServices.get_sca_status(data)
            initial_data.merge!(polling_status_response: polling_status_response)
            pp "Step 4: Polling Status in :show_accounts executed"
            pp initial_data[:polling_status_response]
            initial_data
        end

        step "Get Access Token in :show_accounts" do |data|
            data[:url] = data[:base_url] + "/auth/#{data[:authorization_version]}/tokens"
            data[:payload] = {
                "auth_req_id" => data[:initiate_authorization_response]["auth_req_id"],
                "client_id" => data[:client_id],
                "client_secret" => data[:client_secret],
                "redirect_uri" => "https://www.google.com"
            }
            access_token_response = Navesti::ExternalServices.get_access_token(data)
            initial_data.merge!(access_token_response: access_token_response)
            pp "Step 5: Get Access Token in :show_accounts executed"
            pp initial_data[:access_token_response]
            initial_data
        end

        step "Retrieve an Access Token with a Refresh Token in :show_accounts" do |data|
            data[:url] = data[:base_url] + "/auth/#{data[:authorization_version]}/tokens"
            data[:payload] = {
                "refresh_token" => data[:access_token_response]["refresh_token"],
                "client_id" => data[:client_id],
                "client_secret" => data[:client_secret],
                "redirect_uri" => "https://www.google.com"
            }
            access_token_response = Navesti::ExternalServices.retrieve_an_access_token_with_a_refresh_token(data)
            initial_data.merge!(access_token_response: access_token_response)
            pp "Step 6: Retrieve an Access Token with a Refresh Token in :show_accounts executed"
            pp initial_data[:access_token_response]
            initial_data
        end

        step "Show Accounts in :show_accounts" do |data|
            data[:url] = data[:base_url] + "/ais/#{data[:account_information_version]}/identified2/accounts"
            data[:headers].merge!(
                "X-Request-Id" => SecureRandom.uuid,
                "Authorization" => "Bearer #{data[:access_token_response]["access_token"]}"
            )
            accounts_response = Navesti::ExternalServices.show_accounts(data)
            initial_data.merge!(accounts_response: accounts_response)
            pp "Step 7: Show Accounts in :show_accounts executed"
            pp initial_data[:accounts_response]
            initial_data[:accounts_response]
        end
    end
end

Navesti.define :show_account do
    format :json

    source :show_account_parameters do
    end

    workflow do
        initial_data = nil
        step "Show Accounts in :show_account" do |data|
            initial_data = data
            show_accounts_response = Navesti.run(:show_accounts, data)
            initial_data.merge!(show_accounts_response: show_accounts_response)
            pp "Step 1: Show Accounts in :show_account executed"
            pp initial_data[:show_accounts_response]
            initial_data
        end

        step "Show Account in :show_account" do |data|
            data[:url] = data[:base_url] + "/ais/#{data[:account_information_version]}/identified2/accounts/#{data[:show_accounts_response]["accounts"][0]["resourceId"]}"
            data[:headers].merge!(
                "X-Request-Id" => SecureRandom.uuid,
            )
            account_response = Navesti::ExternalServices.show_account(data)
            initial_data.merge!(account_response: account_response)
            pp "Step 2: Show Account in :show_account executed"
            pp initial_data[:account_response]
            initial_data[:account_response]
        end
    end
end

Navesti.define :show_account_balances do
    format :json

    source :show_account_balances_parameters do
    end
    
    workflow do
        initial_data = nil
        step "Show Account in :show_balances" do |data|
            initial_data = data
            show_account_response = Navesti.run(:show_account, data)
            initial_data.merge!(show_account_response: show_account_response)
            pp "Step 1: Show Account in :show_balances executed"
            pp initial_data[:show_account_response]
            initial_data
        end

        step "Show Balances" do |data|
            data[:url] = data[:base_url] + "/ais/#{data[:account_information_version]}/identified2/accounts/#{data[:show_account_response]["resourceId"]}/balances"
            data[:headers].merge!(
                "X-Request-Id" => SecureRandom.uuid
            )
            balances_response = Navesti::ExternalServices.show_account_balances(data)
            initial_data.merge!(balances_response: balances_response)
            pp "Step 2: Show Balances in :show_balances executed"
            pp initial_data[:balances_response]
            initial_data[:balances_response]
        end
    end
end

Navesti.define :show_account_transactions do
    format :json

    source :show_account_transactions_parameters do
    end
    
    workflow do
        initial_data = nil
        step "Show Account in :show_transactions" do |data|
            initial_data = data
            show_account_response = Navesti.run(:show_account, data)
            initial_data.merge!(show_account_response: show_account_response)
            pp "Step 1: Show Account in :show_transactions executed"
            pp initial_data[:show_account_response]
            initial_data
        end

        step "Show Transactions" do |data|
            data[:url] = data[:base_url] + "/ais/#{data[:account_information_version]}/identified2"+"#{data[:show_account_response]["_links"]["transactions"]["href"]}"
            data[:headers].merge!(
                "X-Request-Id" => SecureRandom.uuid
            )
            transactions_response = Navesti::ExternalServices.show_account_transactions(data)
            initial_data.merge!(transactions_response: transactions_response)
            pp "Step 2: Show Transactions in :show_transactions executed"
            pp initial_data[:transactions_response]
            initial_data[:transactions_response]
        end
    end
end

Navesti.define :show_account_transactions_details do
    format :json

    source :show_account_transactions_details_parameters do
    end
    
    workflow do
        initial_data = nil
        step "Show Account Transactions in :show_transactions_details" do |data|
            initial_data = data
            show_account_transactions_response = Navesti.run(:show_account_transactions, data)
            initial_data.merge!(show_account_transactions_response: show_account_transactions_response)
            pp "Step 1: Show Account Transactions in :show_transactions_details executed"
            pp initial_data[:show_account_transactions_response]
            initial_data
        end

        step "Show Transactions Details" do |data|
            data[:url] = data[:base_url] + "/ais/#{data[:account_information_version]}/identified2"+"#{data[:show_account_transactions_response]["transactions"]["booked"][10]["_links"]["transactionDetails"]["href"]}"
            data[:headers].merge!(
                "X-Request-Id" => SecureRandom.uuid
            )
            pp "data url"
            pp data[:url]
            transactions_details_response = Navesti::ExternalServices.show_account_transactions_details(data)
            initial_data.merge!(transactions_details_response: transactions_details_response)
            pp "Step 2: Show Transactions Details in :show_transactions_details executed"
            pp initial_data[:transactions_details_response]
            initial_data[:transactions_details_response]
        end
    end
end

Navesti.define :payment_initiation do
    format :json

    source :payment_initiation_parameters do
    end
    
    workflow do
        initial_data = nil
        step "Initiate Authorization in :payment_initiation" do |data|
            url = "#{data[:base_url]}/auth/#{data[:authorization_version]}/authorizations"
            data[:url] = url
            data[:payload] = {
                "client_id" => data[:client_id],
                "scope" => data[:scope],
                "start_mode" => "ast"
            }
            initial_data = data
            initiate_authorization_response = Navesti::ExternalServices.initiate_authorization(data)
            initial_data.merge!(initiate_authorization_response: initiate_authorization_response)
            pp "Step 1: Initiate Authorization in :payment_initiation executed"
            pp initial_data[:initiate_authorization_response]
            initial_data
        end

        step "Retrieve Token After Authorization in :payment_initiation" do |data|
            data[:url] = data[:base_url] + "/auth/#{data[:authorization_version]}/authorizations/#{data[:initiate_authorization_response]["auth_req_id"]}"
            retrieve_token_after_authorization_response = Navesti::ExternalServices.retrieve_token_after_authorization_step(data)
            initial_data.merge!(retrieve_token_after_authorization_response: retrieve_token_after_authorization_response)
            pp "Step 2: Retrieve Token After Authorization in :payment_initiation executed"
            pp initial_data[:retrieve_token_after_authorization_response]
            initial_data
        end

        step "Start Bank ID App Simulation in :payment_initiation" do |data|
            data[:url] = data[:base_url] + "/open/sb/auth/mock/v1/login"
            data[:payload] = {
                "personal_identity_number" => "199311219639",
                "start_token" => data[:retrieve_token_after_authorization_response]["autostart_token"]
            }
            start_bank_id_app_simulation_response = Navesti::ExternalServices.start_bank_id_app_simulation(data)
            initial_data.merge!(start_bank_id_app_simulation_response: start_bank_id_app_simulation_response)
            pp "Step 3: Start Bank ID App Simulation in :payment_initiation executed"
            pp initial_data[:start_bank_id_app_simulation_response]
            initial_data
        end

        step "Polling Status in :payment_initiation" do |data|
            data[:url] = data[:base_url] + "/auth/#{data[:authorization_version]}/authorizations/#{data[:initiate_authorization_response]["auth_req_id"]}"
            polling_status_response = Navesti::ExternalServices.get_sca_status(data)
            initial_data.merge!(polling_status_response: polling_status_response)
            pp "Step 4: Polling Status in :payment_initiation executed"
            pp initial_data[:polling_status_response]
            initial_data
        end

        step "Get Access Token in :payment_initiation" do |data|
            data[:url] = data[:base_url] + "/auth/#{data[:authorization_version]}/tokens"
            data[:payload] = {
                "auth_req_id" => data[:initiate_authorization_response]["auth_req_id"],
                "client_id" => data[:client_id],
                "client_secret" => data[:client_secret],
                "redirect_uri" => "https://www.google.com"
            }
            access_token_response = Navesti::ExternalServices.get_access_token(data)
            initial_data.merge!(access_token_response: access_token_response)
            pp "Step 5: Get Access Token in :payment_initiation executed"
            pp initial_data[:access_token_response]
            initial_data
        end

        step "Retrieve an Access Token with a Refresh Token in :payment_initiation" do |data|
            data[:url] = data[:base_url] + "/auth/#{data[:authorization_version]}/tokens"
            data[:payload] = {
                "refresh_token" => data[:access_token_response]["refresh_token"],
                "client_id" => data[:client_id],
                "client_secret" => data[:client_secret],
                "redirect_uri" => "https://www.google.com"
            }
            access_token_response = Navesti::ExternalServices.retrieve_an_access_token_with_a_refresh_token(data)
            initial_data.merge!(access_token_response: access_token_response)
            pp "Step 6: Retrieve an Access Token with a Refresh Token in :payment_initiation executed"
            pp initial_data[:access_token_response]
            initial_data
        end

        step "Get templates in :payment_initiation" do |data|
            data[:url] = data[:base_url] + "/pis/#{data[:payment_initiation_version]}/identified2/templates"
            data[:headers].merge!(
                "X-Request-Id" => SecureRandom.uuid,
                "Authorization" => "Bearer #{data[:access_token_response]["access_token"]}"
            )
            templates_response = Navesti::ExternalServices.get_templates(data)
            initial_data.merge!(templates_response: templates_response)
            pp "Step 7: Get templates in :payment_initiation executed"
            pp initial_data[:templates_response]
            initial_data
        end

        step "Get template in :payment_initiation" do |data|
            data[:url] = data[:base_url] + "/pis/#{data[:payment_initiation_version]}/identified2/templates/#{data[:templates_response][4]["templateId"]}"
            data[:headers].merge!(
                "X-Request-Id" => SecureRandom.uuid,
                "Authorization" => "Bearer #{data[:access_token_response]["access_token"]}"
            )
            template_response = Navesti::ExternalServices.get_template(data)
            initial_data.merge!(template_response: template_response)
            pp "Step 8: Get template in :payment_initiation executed"
            pp initial_data[:template_response]
            initial_data
        end

        step "Create payment initiation in :payment_initiation" do |data|
            data[:url] = data[:base_url] + "/pis/#{data[:payment_initiation_version]}/identified2/payments/#{data[:templates_response][4]["templateId"]}"
            data[:headers].merge!(
                "X-Request-Id" => SecureRandom.uuid
            )
            data[:payload] = {
                "templateId" => data[:templates_response][4]["templateId"],
                "instructionId" => "Payment info",
                "endToEndIdentification" => "string",
                "instructedAmount" => {
                  "amount" => "1",
                  "currency" => "EUR"
                },
                "requestedExecutionDate" => (Date.today + 1).to_s,
                "debtorAccount" => {
                  "iban" => "SE3750000000054400047881"
                },
                "creditorAccount" => {
                  "iban" => "SE3750000000054400047881"
                },
                "creditorAgentBic" => "ESSESSESSXXX",
                "creditorName" => "string",
                "regulatoryReporting" => [
                  {
                    "debitCreditReportingIndicator" => "DEBT",
                    "reportingCode" => "string",
                    "reportingInformation" => "string"
                  }
                ],
                "remittanceInformationUnstructured" => "Liten drake"
            }

            payment_initiation_response = Navesti::ExternalServices.initiate_payment(data)
            initial_data.merge!(payment_initiation_response: payment_initiation_response)
            pp "Step 9: Create payment initiation in :payment_initiation executed"
            pp initial_data[:payment_initiation_response]
            initial_data
        end

        step "Get payment initiation status in :payment_initiation" do |data|
            sleep 5
            data[:url] = data[:base_url] + "/pis/#{data[:payment_initiation_version]}/identified2" + data[:payment_initiation_response]["_links"]["status"]["href"]
            data[:headers].merge!(
                "X-Request-Id" => SecureRandom.uuid
            )
            payment_initiation_status_response = Navesti::ExternalServices.get_payment_status(data)
            initial_data.merge!(payment_initiation_status_response: payment_initiation_status_response)
            pp "Step 10: Get payment initiation status in :payment_initiation executed"
            pp initial_data[:payment_initiation_status_response]
            initial_data
        end

        step "Start payment authorization in :payment_initiation" do |data|
            data[:url] = data[:base_url] + "/pis/#{data[:payment_initiation_version]}/identified2/payments/#{data[:templates_response][4]["templateId"]}/#{data[:payment_initiation_response]["paymentId"]}/authorisations"
            data[:headers].merge!(
                "X-Request-Id" => SecureRandom.uuid,
                "TPP-Redirect-URI" => "https://www.google.com"
            )
            data[:payload] = {
                "authenticationMethodId" => "mobiltbankid"
            }
            pp "data url"
            pp data[:url]
            payment_authorization_response = Navesti::ExternalServices.initiate_authorization(data)
            initial_data.merge!(payment_authorization_response: payment_authorization_response)
            pp "Step 11: Start payment authorization in :payment_initiation executed"
            pp initial_data[:payment_authorization_response]
            sleep 5
            initial_data
        end

        step "Get sca Status in :payment_initiation" do |data|
            sleep 10
            data[:url] = data[:base_url] + "/pis/#{data[:payment_initiation_version]}/identified2/payments/#{data[:templates_response][4]["templateId"]}/#{data[:payment_initiation_response]["paymentId"]}/authorisations/#{data[:payment_authorization_response]["authorisationId"]}"
            data[:headers].merge!(
                "X-Request-Id" => SecureRandom.uuid
            )
            sca_status_response = Navesti::ExternalServices.get_sca_status(data)
            initial_data.merge!(sca_status_response: sca_status_response)
            pp "Step 12: Get sca Status in :payment_initiation executed"
            pp initial_data[:sca_status_response]
            initial_data
        end

        step "Get payment status after authorization in :payment_initiation" do |data|
            sleep 5
            data[:url] = data[:base_url] + "/pis/#{data[:payment_initiation_version]}/identified2" + data[:payment_initiation_response]["_links"]["status"]["href"]
            data[:headers].merge!(
                "X-Request-Id" => SecureRandom.uuid
            )
            payment_initiation_status_response = Navesti::ExternalServices.get_payment_status(data)
            initial_data.merge!(payment_initiation_status_response: payment_initiation_status_response)
            pp "Step 13: Get payment initiation status in :payment_initiation executed"
            pp initial_data[:payment_initiation_status_response]
            initial_data[:payment_initiation_status_response]
        end
    end
end




  