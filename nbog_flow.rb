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

    step "Get Account Access consent" do |data|
        data[:url] = "#{data[:base_accounts_url]}/consents"
        data[:psu_ip_address] = '127.0.0.1'
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
        create_sandbox_response = Navesti::ExternalServices.create_sandbox(data)
        data.merge!(create_sandbox_response: create_sandbox_response)
        pp "Step 4: Get Account Access consent executed"
        pp data[:create_sandbox_response]
        data
    end

    step "Accept Account Access consent" do |data|
        url = data[:create_sandbox_response]['_links']['scaRedirect']['href']
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
        data[:url] = "#{data[:base_accounts_url]}/consents/#{data[:create_sandbox_response]["consentId"]}/status"
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
        pp "Step 6: Show accounts executed"
        pp data[:accounts_response]
        data[:accounts_response]
    end
end