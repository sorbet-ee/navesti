require 'json'
require 'rest-client'
require 'securerandom'
require 'pp'
require 'jwt'
require 'launchy'

class RevolutOBClient
  # Constructor
  # Initializes the client with base URL, client ID, and SSL certificates.
  def initialize
    @BASE_URL = "https://sandbox-oba-auth.revolut.com"
    @client_id = "d099c903-2443-410e-844e-7282c6ec118f"
    cert_path = File.expand_path('./config/certs/transport.pem')
    key_path = File.expand_path('./config/certs/private.key')
    

    @ssl_options = {
      ssl_client_cert: OpenSSL::X509::Certificate.new(File.read(cert_path)),
      ssl_client_key: OpenSSL::PKey::RSA.new(File.read(key_path)),
      verify_ssl: false
    }
  end


  # Accounts
  
  # Function: get_access_token
  # Description: Requests and retrieves an access token using client credentials grant type.
  # Parameters: None
  # Returns: Parsed JSON response containing access token data or error details.
  def get_access_token
    url = "#{@BASE_URL}/token"

    headers = {
      'Content-Type' => 'application/x-www-form-urlencoded'
    }

    payload = URI.encode_www_form(
      'grant_type' => 'client_credentials',
      'scope' => 'accounts payments',
      'client_id' => @client_id
    )

    begin
      pp "Making request to: #{url}"
      pp "Headers: #{JSON.pretty_generate(headers)}"
      pp "Payload: #{payload}"
        
      response = RestClient::Request.execute(
        method: :post,
        url: url,
        payload: payload,
        headers: headers,
        **@ssl_options
      )
        
      JSON.parse(response.body)

    rescue RestClient::ExceptionWithResponse => e
      pp "HTTP Request failed with response code #{e.http_code}"
      pp "Response body: #{e.response.body}"

      error_response = JSON.parse(e.response.body) rescue nil
      error_response
    rescue StandardError => e
      pp "An error occurred: #{e.message}"
      pp e.backtrace.join("\n") if e.backtrace
      nil
    end
  end

  # Function: create_an_account_access_consent
  # Description: Creates an account access consent specifying permissions and validity.
  # Parameters: access_token (String) - Access token for authorization.
  # Returns: Parsed JSON response containing consent data or error details.
  def create_an_account_access_consent(access_token:)
    url = "#{@BASE_URL}/account-access-consents"

    headers = {
      'Content-Type' => 'application/json',
      'Authorization' => "Bearer #{access_token}",
      'x-fapi-financial-id' => '001580000103UAvAAM'
    }

    payload = {
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

    begin
      pp "Making request to: #{url}"
      pp "Headers: #{JSON.pretty_generate(headers)}"
      pp "Payload: #{payload.to_json}"

      response = RestClient::Request.execute(
        method: :post,
        url: url,
        payload: payload.to_json,
        headers: headers,
        **@ssl_options
      )

      JSON.parse(response.body)

    rescue RestClient::ExceptionWithResponse => e
      pp "HTTP Request failed with response code #{e.http_code}"
      pp "Response body: #{e.response.body}"

      error_response = JSON.parse(e.response.body) rescue nil
      error_response
    rescue StandardError => e
      pp "An error occurred: #{e.message}"
      pp e.backtrace.join("\n") if e.backtrace
      nil
    end
  end

  # Function: retrieve_an_account_access_consent
  # Description: Retrieves an existing account access consent by its ID.
  # Parameters:
  #   access_token (String) - Access token for authorization.
  #   consent_id (String) - Consent ID to retrieve.
  # Returns: Parsed JSON response containing consent details or error details.
  def retrieve_an_account_access_consent(access_token:, consent_id:)
    url = "#{@BASE_URL}/account-access-consents/#{consent_id}"

    headers = {
      'Content-Type' => 'application/json',
      'Authorization' => "Bearer #{access_token}",
      'x-fapi-financial-id' => '001580000103UAvAAM'
    }

    begin
      pp "Making request to: #{url}"
      pp "Headers: #{JSON.pretty_generate(headers)}"

      response = RestClient::Request.execute(
        method: :get,
        url: url,
        headers: headers,
        **@ssl_options
      )

      JSON.parse(response.body)

    rescue RestClient::ExceptionWithResponse => e
      pp "HTTP Request failed with response code #{e.http_code}"
      pp "Response body: #{e.response.body}"

      error_response = JSON.parse(e.response.body) rescue nil
      error_response
    rescue StandardError => e
      pp "An error occurred: #{e.message}"
      pp e.backtrace.join("\n") if e.backtrace
      nil
    end
  end

  # Function: get_account_access_consent_from_the_user
  # Description: Generates a user authorization URL and retrieves the authorization code from user input.
  # Parameters:
  #   access_token (String) - Access token for authorization.
  #   consent_id (String) - Consent ID for the authorization intent.
  # Returns: Hash containing :code, :id_token, and :state from the user's authorization response.
  def get_account_access_consent_from_the_user(access_token:, consent_id:)
    state = SecureRandom.uuid
    @state = state
    
    header = {
      'alg' => 'PS256',
      'kid' => '007'
    }

    payload = {
      'response_type' => 'code id_token',
      'client_id' => @client_id,
      'redirect_uri' => 'https://www.google.com',
      'aud' => 'https://sandbox-oba-auth.revolut.com',
      'scope' => 'accounts',
      'state' => state,
      'nbf' => 1738158653,
      'exp' => 1738161953,
      'claims' => {
        'id_token' => {
          'openbanking_intent_id' => {
            'value' => "#{consent_id}"
          }
        }
      }
    }
    
    jwt = JWT.encode(payload, @ssl_options[:ssl_client_key], 'PS256', header)
    revolut_url = "https://sandbox-oba.revolut.com/ui/index.html?response_type=code%20id_token&scope=accounts&redirect_uri=#{payload['redirect_uri']}&client_id=#{@client_id}&request=#{jwt}"
    
    # Step 1: Get the authorization URL
    authorization_url = revolut_url
    
    # Step 2: Prompt user to complete authorization
    puts "Open the following URL in your browser to authorize: "
    Launchy.open(authorization_url)
    puts "After authorization, paste the redirected URL here: "
    
    # Step 3: Pause execution and wait for user input
    redirected_url = $stdin.gets.chomp.strip  # Ensures input is read properly

    # Validate the URL format
    unless redirected_url.match?(/^https?:\/\/\S+/)
      raise URI::InvalidURIError, "Invalid URL provided: #{redirected_url}"
    end

    # Step 4: Extract authorization code from the redirected URL
    parsed_params = CGI.parse(URI.parse(redirected_url).query)
    auth_data = {
      code: parsed_params["code"]&.first,
      id_token: parsed_params["id_token"]&.first,
      state: parsed_params["state"]&.first
    }

    auth_data
  end

  # Function: retrieve_all_accounts
  # Description: Retrieves all accounts accessible to the user with the provided access token.
  # Parameters: access_token (String) - Access token for authorization.
  # Returns: Parsed JSON response containing account details or error details.
  def retrieve_all_accounts(access_token:)
    url = "#{@BASE_URL}/accounts"

    headers = {
      'Content-Type' => 'application/json',
      'Authorization' => "Bearer #{access_token}",
      'x-fapi-financial-id' => '001580000103UAvAAM'
    }

    begin
      pp "Making request to: #{url}"
      pp "Headers: #{JSON.pretty_generate(headers)}"

      response = RestClient::Request.execute(
        method: :get,
        url: url,
        headers: headers,
        **@ssl_options
      )

      JSON.parse(response.body)

    rescue RestClient::ExceptionWithResponse => e
      pp "HTTP Request failed with response code #{e.http_code}"
      pp "Response body: #{e.response.body}"

      error_response = JSON.parse(e.response.body) rescue nil
      error_response
    rescue StandardError => e
      pp "An error occurred: #{e.message}"
      pp e.backtrace.join("\n") if e.backtrace
      nil
    end
  end

  # Function: exchange_code_for_access_token
  # Description: Exchanges an authorization code for an access token using Revolut's token endpoint.
  # Parameters:
  #   - code: The authorization code obtained from the authorization step.
  # Returns: Parsed JSON response containing the access token, or error response, or nil on error.
  def exchange_code_for_access_token(code:)
    url = "#{@BASE_URL}/token"

    headers = {
      'Content-Type' => 'application/x-www-form-urlencoded'
    }

    payload = URI.encode_www_form(
      'grant_type' => 'authorization_code',
      'code' => code
    )

    begin
      pp "Making request to: #{url}"
      pp "Headers: #{JSON.pretty_generate(headers)}"
      pp "Payload: #{payload}"

      response = RestClient::Request.execute(
        method: :post,
        url: url,
        payload: payload,
        headers: headers,
        **@ssl_options
      )

      JSON.parse(response.body)

    rescue RestClient::ExceptionWithResponse => e
      pp "HTTP Request failed with response code #{e.http_code}"
      pp "Response body: #{e.response.body}"

      error_response = JSON.parse(e.response.body) rescue nil
      error_response
    rescue StandardError => e
      pp "An error occurred: #{e.message}"
      pp e.backtrace.join("\n") if e.backtrace
      nil
    end
  end

  # Function: retrieve_an_account
  # Description: Retrieves details of a specific account using its account ID.
  # Parameters:
  #   - new_access_token: The access token for authorization.
  #   - account_id: The ID of the account to retrieve.
  # Returns: Parsed JSON response containing account details, or error response, or nil on error.
  def retrieve_an_account(new_access_token:, account_id:)
    url = "#{@BASE_URL}/accounts/#{account_id}"

    headers = {
      'Content-Type' => 'application/json',
      'Authorization' => "Bearer #{new_access_token}",
      'x-fapi-financial-id' => '001580000103UAvAAM'
    }

    begin
      pp "Making request to: #{url}"
      pp "Headers: #{JSON.pretty_generate(headers)}"

      response = RestClient::Request.execute(
        method: :get,
        url: url,
        headers: headers,
        **@ssl_options
      )

      JSON.parse(response.body)

    rescue RestClient::ExceptionWithResponse => e
      pp "HTTP Request failed with response code #{e.http_code}"
      pp "Response body: #{e.response.body}"

      error_response = JSON.parse(e.response.body) rescue nil
      error_response
    rescue StandardError => e
      pp "An error occurred: #{e.message}"
      pp e.backtrace.join("\n") if e.backtrace
      nil
    end
  end

  # Function: retrieve_an_account_balance
  # Description: Retrieves the balance information of a specific account.
  # Parameters:
  #   - new_access_token: The access token for authorization.
  #   - account_id: The ID of the account whose balance is to be retrieved.
  # Returns: Parsed JSON response containing balance information, or error response, or nil on error.
  def retrieve_an_account_balance(new_access_token:, account_id:)
    url = "#{@BASE_URL}/accounts/#{account_id}/balances"

    headers = {
      'Content-Type' => 'application/json',
      'Authorization' => "Bearer #{new_access_token}",
      'x-fapi-financial-id' => '001580000103UAvAAM'
    }

    begin
      pp "Making request to: #{url}"
      pp "Headers: #{JSON.pretty_generate(headers)}"

      response = RestClient::Request.execute(
        method: :get,
        url: url,
        headers: headers,
        **@ssl_options
      )

      JSON.parse(response.body)

    rescue RestClient::ExceptionWithResponse => e
      pp "HTTP Request failed with response code #{e.http_code}"
      pp "Response body: #{e.response.body}"

      error_response = JSON.parse(e.response.body) rescue nil
      error_response
    rescue StandardError => e
      pp "An error occurred: #{e.message}"
      pp e.backtrace.join("\n") if e.backtrace
      nil
    end
  end

  # Function: retrieve_an_accounts_all_beneficiaries
  # Description: Retrieves all beneficiaries linked to a specific account.
  # Parameters:
  #   - new_access_token: The access token for authorization.
  #   - account_id: The ID of the account whose beneficiaries are to be retrieved.
  # Returns: Parsed JSON response containing beneficiaries data, or error response, or nil on error.
  def retrieve_an_accounts_all_beneficiaries(new_access_token:, account_id:)
    url = "#{@BASE_URL}/accounts/#{account_id}/beneficiaries"

    headers = {
      'Content-Type' => 'application/json',
      'Authorization' => "Bearer #{new_access_token}",
      'x-fapi-financial-id' => '001580000103UAvAAM'
    }

    begin
      pp "Making request to: #{url}"
      pp "Headers: #{JSON.pretty_generate(headers)}"

      response = RestClient::Request.execute(
        method: :get,
        url: url,
        headers: headers,
        **@ssl_options
      )

      JSON.parse(response.body)

    rescue RestClient::ExceptionWithResponse => e
      pp "HTTP Request failed with response code #{e.http_code}"
      pp "Response body: #{e.response.body}"

      error_response = JSON.parse(e.response.body) rescue nil
      error_response
    rescue StandardError => e
      pp "An error occurred: #{e.message}"
      pp e.backtrace.join("\n") if e.backtrace
      nil
    end
  end

  # Function: retrieve_an_accounts_all_direct_debits
  # Description: Retrieves all direct debits linked to a specific account.
  # Parameters:
  #   - new_access_token: The access token for authorization.
  #   - account_id: The ID of the account whose direct debits are to be retrieved.
  # Returns: Parsed JSON response containing direct debits data, or error response, or nil on error.
  def retrieve_an_accounts_all_direct_debits(new_access_token:, account_id:)
    url = "#{@BASE_URL}/accounts/#{account_id}/direct-debits"

    headers = {
      'Content-Type' => 'application/json',
      'Authorization' => "Bearer #{new_access_token}",
      'x-fapi-financial-id' => '001580000103UAvAAM'
    }

    begin
      pp "Making request to: #{url}"
      pp "Headers: #{JSON.pretty_generate(headers)}"

      response = RestClient::Request.execute(
        method: :get,
        url: url,
        headers: headers,
        **@ssl_options
      )

      JSON.parse(response.body)

    rescue RestClient::ExceptionWithResponse => e
      pp "HTTP Request failed with response code #{e.http_code}"
      pp "Response body: #{e.response.body}"

      error_response = JSON.parse(e.response.body) rescue nil
      error_response
    rescue StandardError => e
      pp "An error occurred: #{e.message}"
      pp e.backtrace.join("\n") if e.backtrace
      nil
    end
  end

  # Function: retrieve_an_accounts_all_standing_orders
  # Description: Retrieves all standing orders linked to a specific account.
  # Parameters:
  #   - new_access_token: The access token for authorization.
  #   - account_id: The ID of the account whose standing orders are to be retrieved.
  # Returns: Parsed JSON response containing standing orders data, or error response, or nil on error.
  def retrieve_an_accounts_all_standing_orders(new_access_token:, account_id:)
    url = "#{@BASE_URL}/accounts/#{account_id}/standing-orders"

    headers = {
      'Content-Type' => 'application/json',
      'Authorization' => "Bearer #{new_access_token}",
      'x-fapi-financial-id' => '001580000103UAvAAM'
    }

    begin
      pp "Making request to: #{url}"
      pp "Headers: #{JSON.pretty_generate(headers)}"

      response = RestClient::Request.execute(
        method: :get,
        url: url,
        headers: headers,
        **@ssl_options
      )

      JSON.parse(response.body)

    rescue RestClient::ExceptionWithResponse => e
      pp "HTTP Request failed with response code #{e.http_code}"
      pp "Response body: #{e.response.body}"

      error_response = JSON.parse(e.response.body) rescue nil
      error_response
    rescue StandardError => e
      pp "An error occurred: #{e.message}"
      pp e.backtrace.join("\n") if e.backtrace
      nil
    end
  end

  # Function: retrieve_an_accounts_all_transactions
  # Description: Retrieves all transactions linked to a specific account.
  # Parameters:
  #   - new_access_token: The access token for authorization.
  #   - account_id: The ID of the account whose transactions are to be retrieved.
  # Returns: Parsed JSON response containing transactions data, or error response, or nil on error.
  def retrieve_an_accounts_all_transactions(new_access_token:, account_id:)
    url = "#{@BASE_URL}/accounts/#{account_id}/transactions"

    headers = {
      'Content-Type' => 'application/json',
      'Authorization' => "Bearer #{new_access_token}",
      'x-fapi-financial-id' => '001580000103UAvAAM'
    }

    begin
      pp "Making request to: #{url}"
      pp "Headers: #{JSON.pretty_generate(headers)}"

      response = RestClient::Request.execute(
        method: :get,
        url: url,
        headers: headers,
        **@ssl_options
      )

      JSON.parse(response.body)

    rescue RestClient::ExceptionWithResponse => e
      pp "HTTP Request failed with response code #{e.http_code}"
      pp "Response body: #{e.response.body}"

      error_response = JSON.parse(e.response.body) rescue nil
      error_response
    rescue StandardError => e
      pp "An error occurred: #{e.message}"
      pp e.backtrace.join("\n") if e.backtrace
      nil
    end
  end

  # Transactions
  
  # Function: create_a_domestic_payment_consent
  # Description: Creates a consent for a domestic payment.
  # Parameters:
  #   - access_token: The access token for authorization.
  # Returns: Parsed JSON response containing consent details, or error response, or nil on error.
  def create_a_domestic_payment_consent(access_token:)
    url = "#{@BASE_URL}/domestic-payment-consents"
  
    payload = {
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

    jws = JWT.encode(JSON.parse(payload.to_json), @ssl_options[:ssl_client_key], 'PS256', {
      'typ' => 'JOSE',
      'alg' => 'PS256',
      'kid' => '007',
      'crit' => ['http://openbanking.org.uk/tan'],
      'http://openbanking.org.uk/tan' => 'johntheodorou.github.io'
    })

    headers = {
      'Content-Type' => 'application/json',
      'Authorization' => "Bearer #{access_token}",
      'x-fapi-financial-id' => '001580000103UAvAAM',
      'x-jws-signature' => jws,
      'x-idempotency-key' => '123456789'
    }
  
    begin
      pp "Making request to: #{url}"
      pp "Headers: #{JSON.pretty_generate(headers)}"
      pp "Payload: #{JSON.pretty_generate(payload)}"
  
      response = RestClient::Request.execute(
        method: :post,
        url: url,
        payload: payload.to_json,
        headers: headers,
        **@ssl_options
      )
  
      JSON.parse(response.body)
  
    rescue RestClient::ExceptionWithResponse => e
      pp "HTTP Request failed with response code #{e.http_code}"
      pp "Response body: #{e.response.body}"
  
      error_response = JSON.parse(e.response.body) rescue nil
      error_response
    rescue StandardError => e
      pp "An error occurred: #{e.message}"
      pp e.backtrace.join("\n") if e.backtrace
      nil
    end
  end

  # Function: retrieve_a_domestic_payment_consent
  # Description: Retrieves a specific domestic payment consent.
  # Parameters:
  #   - access_token: The access token for authorization.
  #   - consent_id: The ID of the consent to be retrieved.
  # Returns: Parsed JSON response containing consent details, or error response, or nil on error.
  def retrieve_a_domestic_payment_consent(access_token:, consent_id:)
    url = "#{@BASE_URL}/domestic-payment-consents/#{consent_id}"

    headers = {
      'Content-Type' => 'application/json',
      'Authorization' => "Bearer #{access_token}",
      'x-fapi-financial-id' => '001580000103UAvAAM'
    }

    begin
      pp "Making request to: #{url}"
      pp "Headers: #{JSON.pretty_generate(headers)}"

      response = RestClient::Request.execute(
        method: :get,
        url: url,
        headers: headers,
        **@ssl_options
      )

      JSON.parse(response.body)

    rescue RestClient::ExceptionWithResponse => e
      pp "HTTP Request failed with response code #{e.http_code}"
      pp "Response body: #{e.response.body}"

      error_response = JSON.parse(e.response.body) rescue nil
      error_response
    rescue StandardError => e
      pp "An error occurred: #{e.message}"
      pp e.backtrace.join("\n") if e.backtrace
      nil
    end
  end

  # Function: get_domestic_payment_consent_from_the_user
  # Description: Retrieves a domestic payment consent from the user.
  # Parameters:
  #   - access_token: The access token for authorization.
  #   - consent_id: The ID of the consent to be retrieved.
  # Returns: Parsed JSON response containing consent details, or error response, or nil on error.
  def get_domestic_payment_consent_from_the_user(access_token:, consent_id:)
    state = SecureRandom.uuid
    @state = state
    
    header = {
      'alg' => 'PS256',
      'kid' => '007'
    }

    payload = {
      'response_type' => 'code id_token',
      'client_id' => @client_id,
      'redirect_uri' => 'https://www.google.com',
      'aud' => 'https://sandbox-oba-auth.revolut.com',
      'scope' => 'payments',
      'state' => state,
      'nbf' => 1738158653,
      'exp' => 1738161953,
      'claims' => {
        'id_token' => {
          'openbanking_intent_id' => {
            'value' => "#{consent_id}"
          }
        }
      }
    }
    
    jwt = JWT.encode(payload, @ssl_options[:ssl_client_key], 'PS256', header)
    revolut_url = "https://sandbox-oba.revolut.com/ui/index.html?response_type=code%20id_token&scope=payments&redirect_uri=#{payload['redirect_uri']}&client_id=#{@client_id}&request=#{jwt}"
    
    # Step 1: Get the authorization URL
    authorization_url = revolut_url
    
    # Step 2: Prompt user to complete authorization
    puts "Open the following URL in your browser to authorize: "
    Launchy.open(authorization_url)
    puts "After authorization, paste the redirected URL here: "
    
    # Step 3: Pause execution and wait for user input
    redirected_url = $stdin.gets.chomp.strip  # Ensures input is read properly

    # Validate the URL format
    unless redirected_url.match?(/^https?:\/\/\S+/)
      raise URI::InvalidURIError, "Invalid URL provided: #{redirected_url}"
    end

    # Step 4: Extract authorization code from the redirected URL
    parsed_params = CGI.parse(URI.parse(redirected_url).query)
    auth_data = {
      code: parsed_params["code"]&.first,
      id_token: parsed_params["id_token"]&.first,
      state: parsed_params["state"]&.first
    }

    auth_data
  end

  # Function: get_funds_confirmation_for_a_domestic_payment_consent
  # Description: Retrieves funds confirmation for a specific domestic payment consent.
  # Parameters:
  #   - access_token: The access token for authorization.
  #   - consent_id: The ID of the consent for which funds confirmation is requested.
  # Returns: Parsed JSON response containing funds confirmation details, or error response, or nil on error.
  def get_funds_confirmation_for_a_domestic_payment_consent(access_token:, consent_id:)
    url = "#{@BASE_URL}/domestic-payment-consents/#{consent_id}/funds-confirmation"

    headers = {
      'Content-Type' => 'application/json',
      'Authorization' => "Bearer #{access_token}",
      'x-fapi-financial-id' => '001580000103UAvAAM'
    }

    begin
      pp "Making request to: #{url}"
      pp "Headers: #{JSON.pretty_generate(headers)}"

      response = RestClient::Request.execute(
        method: :get,
        url: url,
        headers: headers,
        **@ssl_options
      )

      JSON.parse(response.body)

    rescue RestClient::ExceptionWithResponse => e
      ap "HTTP Request failed with response code #{e.http_code}".colorize(:red)
      ap "Response body: #{e.response.body}".colorize(:red)

      error_response = JSON.parse(e.response.body) rescue nil
      error_response
    rescue StandardError => e
      pp "An error occurred: #{e.message}"
      pp e.backtrace.join("\n") if e.backtrace
      nil
    end
  end

  # Function: create_a_domestic_payment
  # Description: Creates a domestic payment.
  # Parameters:
  #   - access_token: The access token for authorization.
  #   - consent_id: The ID of the consent for which the payment is being created.
  # Returns: Parsed JSON response containing payment details, or error response, or nil on error.
  def create_a_domestic_payment(access_token:, consent_id:)
    url = "#{@BASE_URL}/domestic-payments"
  
    payload = {
      'Data' => {
        'ConsentId' => consent_id,
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
  
    # Generate JWS signature
    jws = JWT.encode(JSON.parse(payload.to_json), @ssl_options[:ssl_client_key], 'PS256', {
      'typ' => 'JOSE',
      'alg' => 'PS256',
      'kid' => '007',
      'crit' => ['http://openbanking.org.uk/tan'],
      'http://openbanking.org.uk/tan' => 'johntheodorou.github.io'
    })
  
    headers = {
      'Content-Type' => 'application/json',
      'Authorization' => "Bearer #{access_token}",
      'x-fapi-financial-id' => '001580000103UAvAAM',
      'x-jws-signature' => jws,
      'x-idempotency-key' => '123456789'
    }
  
    begin
      # Print debugging information
      pp "Making request to: #{url}"
      pp "Headers: #{JSON.pretty_generate(headers)}"
      pp "Payload: #{JSON.pretty_generate(payload)}"
  
      # Make the POST request
      response = RestClient::Request.execute(
        method: :post,
        url: url,
        payload: payload.to_json,
        headers: headers,
        **@ssl_options
      )
  
      # Parse and return the response
      JSON.parse(response.body)
  
    rescue RestClient::ExceptionWithResponse => e
      # Handle HTTP request errors
      pp "HTTP Request failed with response code #{e.http_code}"
      pp "Response body: #{e.response.body}"
  
      error_response = JSON.parse(e.response.body) rescue nil
      error_response
    rescue StandardError => e
      # Handle other errors
      pp "An error occurred: #{e.message}"
      pp e.backtrace.join("\n") if e.backtrace
      nil
    end
  end

  # Function: retrieve_a_domestic_payment
  # Description: Retrieves a specific domestic payment.
  # Parameters:
  #   - access_token: The access token for authorization.
  #   - domestic_payment_id: The ID of the payment to be retrieved.
  # Returns: Parsed JSON response containing payment details, or error response, or nil on error.
  def retrieve_a_domestic_payment(access_token:, domestic_payment_id:)
    url = "#{@BASE_URL}/domestic-payments/#{domestic_payment_id}"

    headers = {
      'Content-Type' => 'application/json',
      'Authorization' => "Bearer #{access_token}",
      'x-fapi-financial-id' => '001580000103UAvAAM'
    }

    begin
      pp "Making request to: #{url}"
      pp "Headers: #{JSON.pretty_generate(headers)}"

      response = RestClient::Request.execute(
        method: :get,
        url: url,
        headers: headers,
        **@ssl_options
      )

      JSON.parse(response.body)

    rescue RestClient::ExceptionWithResponse => e
      pp "HTTP Request failed with response code #{e.http_code}"
      pp "Response body: #{e.response.body}"

      error_response = JSON.parse(e.response.body) rescue nil
      error_response
    rescue StandardError => e
      pp "An error occurred: #{e.message}"
      pp e.backtrace.join("\n") if e.backtrace
      nil
    end
  end
end
