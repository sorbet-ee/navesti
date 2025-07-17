require_relative 'navesti'
require 'base64'

Navesti.define :show_account do
    format :json

    source :show_account_parameters do
    end
    
    workflow do
        step "Generate access token" do |data|
            pp "Step 1: Generate access token started..."
            data[:url] = "#{data[:base_url]}/v1/oauth2/token"
            data[:credentials] = Base64.strict_encode64("#{data[:client_id]}:#{data[:client_secret]}")
            data[:headers] = {
                "Content-Type" => "application/x-www-form-urlencoded",
                "Authorization" => "Basic #{data[:credentials]}"
            }
            data[:payload] = {
                "grant_type" => "client_credentials"
            }
            if data[:headers]["Content-Type"] == "application/x-www-form-urlencoded"
                access_token_response = Navesti::ExternalServices.get_access_token(data, nil)
            end
            data.merge!(access_token_response: access_token_response)
            pp "Step 1: Generate access token executed"
            pp data[:access_token_response]
            data
        end

        step "Show account" do |data|
            pp "Step 2: Show account started..."
            data[:url] = "#{data[:base_url]}/v1/identity/oauth2/userinfo?schema=paypalv1.1"
            data[:headers] = {
                "Content-Type" => "application/json",
                "Authorization" => "Bearer #{data[:access_token_response]["access_token"]}"
            }
            account_response = Navesti::ExternalServices.show_account(data)
            data.merge!(account_response: account_response)
            pp "Step 2: Show account executed"
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
        step "Run show_account workflow" do |data|
            pp "Step 1: Run show_account workflow started..."
            data[:account_response] = Navesti.run(:show_account, data)
            data
        end

        step "Show transactions" do |data|
            pp "Step 2: Show transactions started..."
            data[:url] = "#{data[:base_url]}/v1/reporting/transactions/?start_date=#{data[:start_date]}&end_date=#{data[:end_date]}"
            data[:headers] = {
                "Content-Type" => "application/json",
                "Authorization" => "Bearer #{data[:access_token_response]["access_token"]}"
            }
            transactions_response = Navesti::ExternalServices.show_account_transactions(data)
            data.merge!(transactions_response: transactions_response)
            pp "Step 2: Show transactions executed"
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
        step "Run show_account workflow" do |data|
            pp "Step 1: Run show_account workflow started..."
            data[:account_response] = Navesti.run(:show_account, data)
            data
        end

        step "Show balances" do |data|
            pp "Step 2: Show balances started..."
            data[:url] = "#{data[:base_url]}/v1/reporting/balances?as_of_time=#{data[:end_date]}&currency_code=ALL&include_crypto_currencies=true"
            data[:headers] = {
                "Content-Type" => "application/json",
                "Authorization" => "Bearer #{data[:access_token_response]["access_token"]}"
            }
            balances_response = Navesti::ExternalServices.show_account_balances(data)
            data.merge!(balances_response: balances_response)
            pp "Step 2: Show balances executed"
            pp data[:balances_response]
            data[:balances_response]
        end
    end
end

Navesti.define :order do
    format :json

    source :order_parameters do
    end
    
    workflow do
        step "Generate access token" do |data|
            pp "Step 1: Generate access token started..."
            data[:url] = "#{data[:base_url]}/v1/oauth2/token"
            data[:credentials] = Base64.strict_encode64("#{data[:client_id]}:#{data[:client_secret]}")
            data[:headers] = {
                "Content-Type" => "application/x-www-form-urlencoded",
                "Authorization" => "Basic #{data[:credentials]}"
            }
            data[:payload] = {
                "grant_type" => "client_credentials"
            }
            if data[:headers]["Content-Type"] == "application/x-www-form-urlencoded"
                access_token_response = Navesti::ExternalServices.get_access_token(data, nil)
            end
            data.merge!(access_token_response: access_token_response)
            pp "Step 1: Generate access token executed"
            pp data[:access_token_response]
            data
        end

        step "Create order" do |data|
            pp "Step 2: Create order started..."
            data[:url] = "#{data[:base_url]}/v2/checkout/orders"
            data[:headers] = {
                "Content-Type" => "application/json",
                "Authorization" => "Bearer #{data[:access_token_response]["access_token"]}",
                "PayPal-Request-Id" => "#{SecureRandom.uuid}",
                "Prefer" => "return=representation"
            }
            data[:payload] = {
                "intent" => "AUTHORIZE",
                "payment_source" => {
                    "paypal" => {
                        "experience_context" => {
                            "return_url" => "https://developer.paypal.com",
                            "cancel_url" => "https://www.bing.com",
                            "user_action" => "PAY_NOW"
                        }
                    }
                },
                "purchase_units" => [
                    {
                        "amount" => {
                            "currency_code" => "USD",
                            "value" => "100.00"
                        }
                    }
                ]
            }
            order_response = Navesti::ExternalServices.create_order(data)
            data.merge!(order_response: order_response)
            pp "Step 2: Create order executed"
            pp data[:order_response]
            data
        end

        step "Confirm payment source" do |data|
            pp "Step 3: Confirm payment source started..."
            data[:url] = "#{data[:base_url]}/v2/checkout/orders/#{data[:order_response]["id"]}/confirm-payment-source"
            data[:headers] = {
                "Content-Type" => "application/json",
                "Authorization" => "Bearer #{data[:access_token_response]["access_token"]}",
                "PayPal-Request-Id" => "#{SecureRandom.uuid}",
                "Prefer" => "return=representation"
            }
            data[:payload] = {
                "payment_source" => {
                    "card" => {
                        "number" => "4111111111111111",
                        "expiry" => "2035-12"
                    }
                }
            }
            payment_source_response = Navesti::ExternalServices.confirm_payment_source(data)
            data.merge!(payment_source_response: payment_source_response)
            pp "Step 3: Confirm payment source executed"
            pp data[:payment_source_response]
            data
        end

        step "Authorize order" do |data|
            pp "Step 4: Authorize order started..."
            data[:url] = "#{data[:base_url]}/v2/checkout/orders/#{data[:order_response]["id"]}/authorize"
            data[:headers] = {
                "Content-Type" => "application/json",
                "Authorization" => "Bearer #{data[:access_token_response]["access_token"]}",
                "PayPal-Request-Id" => "#{SecureRandom.uuid}",
                "Prefer" => "return=representation"
            }
            data[:payload] = {}
            authorize_response = Navesti::ExternalServices.initiate_authorization(data)
            data.merge!(authorize_response: authorize_response)
            pp "Step 4: Authorize order executed"
            pp data[:authorize_response]
            data
        end

        step "Capture authorization" do |data|
            pp "Step 5: Capture authorization started..."
            data[:url] = "#{data[:base_url]}/v2/payments/authorizations/#{data[:authorize_response]["purchase_units"][0]["payments"]["authorizations"][0]["id"]}/capture"
            data[:headers] = {
                "Content-Type" => "application/json",
                "Authorization" => "Bearer #{data[:access_token_response]["access_token"]}"
            }
            sleep 5
            capture_response = Navesti::ExternalServices.capture_authorization(data)
            data.merge!(capture_response: capture_response)
            pp "Step 5: Capture authorization executed"
            pp data[:capture_response]
            data[:capture_response]
        end
    end
end
    