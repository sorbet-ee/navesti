require 'json'
require 'rest-client'
require 'openssl'
require 'securerandom'
require 'uri'
require 'pp'
require_relative 'navesti'

# Define the LHV OAuth Workflow
Navesti.define :lhv_oauth do
  format :json
  
  source :lhv_api do
    map :base_url, to: :base_url
    map :psu_id, to: :psu_id
    map :psu_corporate_id, to: :psu_corporate_id
  end
  
  workflow do
    # Initialize the workflow with default values and configure SSL
    step "initialize_workflow" do |data|
      # Set defaults
      data[:base_url] ||= 'https://api.sandbox.lhv.eu/psd2/v1'
      data[:psu_id] ||= 'Liis-MariMnnik'
      data[:psu_corporate_id] ||= 'EE47101010033'
      
      # Load certificates from known directory
      cert_path = File.expand_path('./config/lhv/client-cert.pem')
      key_path = File.expand_path('./config/lhv/client-key.pem')
      ca_path = File.expand_path('./config/lhv/ca-chain.pem')
      
      begin
        data[:ssl_options] = {
          ssl_client_cert: OpenSSL::X509::Certificate.new(File.read(cert_path)),
          ssl_client_key: OpenSSL::PKey::RSA.new(File.read(key_path)),
          ssl_ca_file: ca_path,
          verify_ssl: false,
          ssl_version: 'TLSv1_2'
        }
        # Log success
        pp "SSL certificates loaded successfully from #{cert_path}"
      rescue => e
        pp "Error loading SSL certificates: #{e.message}"
        data[:ssl_error] = e.message
      end
      
      data
    end
    
    # Step to create OAuth authorization
    step "create_oauth_authorization" do |data|
      if data[:authentication_method_id]
        url = "#{data[:base_url]}/oauth/authorisations"
        
        headers = {
          'Accept' => 'application/hal+json;charset=UTF-8',
          'PSU-ID' => 'Liis-MariMnnik',
          'PSU-Corporate-ID' => 'EE47101010033',
          'X-Request-ID' => SecureRandom.uuid,
          'Content-Type' => 'application/json;charset=UTF-8'
        }
        
        payload = {
          "authenticationMethodId" => data[:authentication_method_id]
        }

        pp "payload: #{payload}"
        
        begin
          pp "Making request to: #{url}"
          pp "Headers: #{JSON.pretty_generate(headers)}"
          pp "Payload: #{payload.to_json}"
          
          response = RestClient::Request.execute(
            method: :post,
            url: url,
            payload: payload.to_json,
            headers: headers,
            **data[:ssl_options],
            timeout: 10,
            open_timeout: 5
          )
          
          data[:authorization_result] = JSON.parse(response.body)
        rescue RestClient::ExceptionWithResponse => e
          pp "HTTP Request failed with response code #{e.http_code}"
          pp "Response body: #{e.response.body}"
          
          error_response = JSON.parse(e.response.body) rescue nil
          if error_response && 
             error_response['tppMessages'] && 
             error_response['tppMessages'][0]['code'] == 'AUTHORISATION_FAILED' &&
             error_response['tppMessages'][0]['text'].include?('already in progress')
            pp "Authorization already in progress - this is expected in some cases"
            data[:authorization_result] = nil
          else
            pp "Unexpected error response"
            pp "Request headers: #{headers}"
            pp "Request payload: #{payload.to_json}"
            data[:authorization_result] = nil
          end
        rescue StandardError => e
          pp "An error occurred: #{e.message}"
          pp "Full error: #{e.class}: #{e.message}"
          pp e.backtrace.join("\n") if e.backtrace
          data[:authorization_result] = nil
        end
      end
      
      data
    end
    
    # Step to check authorization status
    step "get_oauth_authorization_status" do |data|
      if data[:authorization_id]
        url = "#{data[:base_url]}/oauth/authorisations/#{data[:authorization_id]}"
        
        headers = {
          'Accept' => 'application/hal+json;charset=UTF-8',
          'X-Request-ID' => SecureRandom.uuid,
        }
        
        begin
          pp "Making request to: #{url}"
          pp "Headers: #{JSON.pretty_generate(headers)}"
          
          response = RestClient::Request.execute(
            method: :get,
            url: url,
            headers: headers,
            **data[:ssl_options]
          )
          puts "\n"
          pp "===================================================================="
          pp "response from get_oauth_authorization_status: #{response}"
          pp "===================================================================="
          puts "\n"
          
          data[:authorization_status] = JSON.parse(response.body)
        rescue RestClient::ExceptionWithResponse => e
          pp "HTTP Request failed with response code #{e.http_code}"
          pp "Response body: #{e.response.body}"
          pp "Request headers: #{headers}"
          data[:authorization_status] = nil
        rescue StandardError => e
          pp "An error occurred: #{e.message}"
          pp "Full error: #{e.class}: #{e.message}"
          pp e.backtrace.join("\n") if e.backtrace
          data[:authorization_status] = nil
        end
      end
      
      data
    end
=begin
    # Step to check authorization status
    step "get_oauth_authorization_status" do |data|
      if data[:authorization_id]
        url = "#{data[:base_url]}/oauth/authorisations/#{data[:authorization_id]}"
        
        headers = {
          'Accept' => 'application/hal+json;charset=UTF-8',
          'X-Request-ID' => SecureRandom.uuid,
        }
        
        begin
          pp "Making request to: #{url}"
          pp "Headers: #{JSON.pretty_generate(headers)}"
          
          response = RestClient::Request.execute(
            method: :get,
            url: url,
            headers: headers,
            **data[:ssl_options]
          )
          puts "\n"
          pp "===================================================================="
          pp "response from get_oauth_authorization_status: #{response}"
          pp "===================================================================="
          puts "\n"
          
          data[:authorization_status] = JSON.parse(response.body)
        rescue RestClient::ExceptionWithResponse => e
          pp "HTTP Request failed with response code #{e.http_code}"
          pp "Response body: #{e.response.body}"
          pp "Request headers: #{headers}"
          data[:authorization_status] = nil
        rescue StandardError => e
          pp "An error occurred: #{e.message}"
          pp "Full error: #{e.class}: #{e.message}"
          pp e.backtrace.join("\n") if e.backtrace
          data[:authorization_status] = nil
        end
      end
      
      data
    end
    
    # Step to check authorization status
    step "get_oauth_authorization_status" do |data|
      if data[:authorization_id]
        url = "#{data[:base_url]}/oauth/authorisations/#{data[:authorization_id]}"
        
        headers = {
          'Accept' => 'application/hal+json;charset=UTF-8',
          'X-Request-ID' => SecureRandom.uuid,
        }
        
        begin
          pp "Making request to: #{url}"
          pp "Headers: #{JSON.pretty_generate(headers)}"
          
          response = RestClient::Request.execute(
            method: :get,
            url: url,
            headers: headers,
            **data[:ssl_options]
          )
          puts "\n"
          pp "===================================================================="
          pp "response from get_oauth_authorization_status: #{response}"
          pp "===================================================================="
          puts "\n"
          
          data[:authorization_status] = JSON.parse(response.body)
        rescue RestClient::ExceptionWithResponse => e
          pp "HTTP Request failed with response code #{e.http_code}"
          pp "Response body: #{e.response.body}"
          pp "Request headers: #{headers}"
          data[:authorization_status] = nil
        rescue StandardError => e
          pp "An error occurred: #{e.message}"
          pp "Full error: #{e.class}: #{e.message}"
          pp e.backtrace.join("\n") if e.backtrace
          data[:authorization_status] = nil
        end
      end
      
      data
    end
    # Step to check authorization status
    step "get_oauth_authorization_status" do |data|
      if data[:authorization_id]
        url = "#{data[:base_url]}/oauth/authorisations/#{data[:authorization_id]}"
        
        headers = {
          'Accept' => 'application/hal+json;charset=UTF-8',
          'X-Request-ID' => SecureRandom.uuid,
        }
        
        begin
          pp "Making request to: #{url}"
          pp "Headers: #{JSON.pretty_generate(headers)}"
          
          response = RestClient::Request.execute(
            method: :get,
            url: url,
            headers: headers,
            **data[:ssl_options]
          )
          puts "\n"
          pp "===================================================================="
          pp "response from get_oauth_authorization_status: #{response}"
          pp "===================================================================="
          puts "\n"
          
          data[:authorization_status] = JSON.parse(response.body)
        rescue RestClient::ExceptionWithResponse => e
          pp "HTTP Request failed with response code #{e.http_code}"
          pp "Response body: #{e.response.body}"
          pp "Request headers: #{headers}"
          data[:authorization_status] = nil
        rescue StandardError => e
          pp "An error occurred: #{e.message}"
          pp "Full error: #{e.class}: #{e.message}"
          pp e.backtrace.join("\n") if e.backtrace
          data[:authorization_status] = nil
        end
      end
      
      data
    end
    # Step to check authorization status
    step "get_oauth_authorization_status" do |data|
      if data[:authorization_id]
        url = "#{data[:base_url]}/oauth/authorisations/#{data[:authorization_id]}"
        
        headers = {
          'Accept' => 'application/hal+json;charset=UTF-8',
          'X-Request-ID' => SecureRandom.uuid,
        }
        
        begin
          pp "Making request to: #{url}"
          pp "Headers: #{JSON.pretty_generate(headers)}"
          
          response = RestClient::Request.execute(
            method: :get,
            url: url,
            headers: headers,
            **data[:ssl_options]
          )
          puts "\n"
          pp "===================================================================="
          pp "response from get_oauth_authorization_status: #{response}"
          pp "===================================================================="
          puts "\n"
          
          data[:authorization_status] = JSON.parse(response.body)
        rescue RestClient::ExceptionWithResponse => e
          pp "HTTP Request failed with response code #{e.http_code}"
          pp "Response body: #{e.response.body}"
          pp "Request headers: #{headers}"
          data[:authorization_status] = nil
        rescue StandardError => e
          pp "An error occurred: #{e.message}"
          pp "Full error: #{e.class}: #{e.message}"
          pp e.backtrace.join("\n") if e.backtrace
          data[:authorization_status] = nil
        end
      end
      
      data
    end
    # Step to check authorization status
    step "get_oauth_authorization_status" do |data|
      if data[:authorization_id]
        url = "#{data[:base_url]}/oauth/authorisations/#{data[:authorization_id]}"
        
        headers = {
          'Accept' => 'application/hal+json;charset=UTF-8',
          'X-Request-ID' => SecureRandom.uuid,
        }
        
        begin
          pp "Making request to: #{url}"
          pp "Headers: #{JSON.pretty_generate(headers)}"
          
          response = RestClient::Request.execute(
            method: :get,
            url: url,
            headers: headers,
            **data[:ssl_options]
          )
          puts "\n"
          pp "===================================================================="
          pp "response from get_oauth_authorization_status: #{response}"
          pp "===================================================================="
          puts "\n"
          
          data[:authorization_status] = JSON.parse(response.body)
        rescue RestClient::ExceptionWithResponse => e
          pp "HTTP Request failed with response code #{e.http_code}"
          pp "Response body: #{e.response.body}"
          pp "Request headers: #{headers}"
          data[:authorization_status] = nil
        rescue StandardError => e
          pp "An error occurred: #{e.message}"
          pp "Full error: #{e.class}: #{e.message}"
          pp e.backtrace.join("\n") if e.backtrace
          data[:authorization_status] = nil
        end
      end
      
      data
    end
    # Step to check authorization status
    step "get_oauth_authorization_status" do |data|
      if data[:authorization_id]
        url = "#{data[:base_url]}/oauth/authorisations/#{data[:authorization_id]}"
        
        headers = {
          'Accept' => 'application/hal+json;charset=UTF-8',
          'X-Request-ID' => SecureRandom.uuid,
        }
        
        begin
          pp "Making request to: #{url}"
          pp "Headers: #{JSON.pretty_generate(headers)}"
          
          response = RestClient::Request.execute(
            method: :get,
            url: url,
            headers: headers,
            **data[:ssl_options]
          )
          puts "\n"
          pp "===================================================================="
          pp "response from get_oauth_authorization_status: #{response}"
          pp "===================================================================="
          puts "\n"
          
          data[:authorization_status] = JSON.parse(response.body)
        rescue RestClient::ExceptionWithResponse => e
          pp "HTTP Request failed with response code #{e.http_code}"
          pp "Response body: #{e.response.body}"
          pp "Request headers: #{headers}"
          data[:authorization_status] = nil
        rescue StandardError => e
          pp "An error occurred: #{e.message}"
          pp "Full error: #{e.class}: #{e.message}"
          pp e.backtrace.join("\n") if e.backtrace
          data[:authorization_status] = nil
        end
      end
      
      data
    end
    # Step to check authorization status
    step "get_oauth_authorization_status" do |data|
      if data[:authorization_id]
        url = "#{data[:base_url]}/oauth/authorisations/#{data[:authorization_id]}"
        
        headers = {
          'Accept' => 'application/hal+json;charset=UTF-8',
          'X-Request-ID' => SecureRandom.uuid,
        }
        
        begin
          pp "Making request to: #{url}"
          pp "Headers: #{JSON.pretty_generate(headers)}"
          
          response = RestClient::Request.execute(
            method: :get,
            url: url,
            headers: headers,
            **data[:ssl_options]
          )
          puts "\n"
          pp "===================================================================="
          pp "response from get_oauth_authorization_status: #{response}"
          pp "===================================================================="
          puts "\n"
          
          data[:authorization_status] = JSON.parse(response.body)
        rescue RestClient::ExceptionWithResponse => e
          pp "HTTP Request failed with response code #{e.http_code}"
          pp "Response body: #{e.response.body}"
          pp "Request headers: #{headers}"
          data[:authorization_status] = nil
        rescue StandardError => e
          pp "An error occurred: #{e.message}"
          pp "Full error: #{e.class}: #{e.message}"
          pp e.backtrace.join("\n") if e.backtrace
          data[:authorization_status] = nil
        end
      end
      
      data
    end
    # Step to check authorization status
    step "get_oauth_authorization_status" do |data|
      if data[:authorization_id]
        url = "#{data[:base_url]}/oauth/authorisations/#{data[:authorization_id]}"
        
        headers = {
          'Accept' => 'application/hal+json;charset=UTF-8',
          'X-Request-ID' => SecureRandom.uuid,
        }
        
        begin
          pp "Making request to: #{url}"
          pp "Headers: #{JSON.pretty_generate(headers)}"
          
          response = RestClient::Request.execute(
            method: :get,
            url: url,
            headers: headers,
            **data[:ssl_options]
          )
          puts "\n"
          pp "===================================================================="
          pp "response from get_oauth_authorization_status: #{response}"
          pp "===================================================================="
          puts "\n"
          
          data[:authorization_status] = JSON.parse(response.body)
        rescue RestClient::ExceptionWithResponse => e
          pp "HTTP Request failed with response code #{e.http_code}"
          pp "Response body: #{e.response.body}"
          pp "Request headers: #{headers}"
          data[:authorization_status] = nil
        rescue StandardError => e
          pp "An error occurred: #{e.message}"
          pp "Full error: #{e.class}: #{e.message}"
          pp e.backtrace.join("\n") if e.backtrace
          data[:authorization_status] = nil
        end
      end
      
      data
    end
    # Step to check authorization status
    step "get_oauth_authorization_status" do |data|
      if data[:authorization_id]
        url = "#{data[:base_url]}/oauth/authorisations/#{data[:authorization_id]}"
        
        headers = {
          'Accept' => 'application/hal+json;charset=UTF-8',
          'X-Request-ID' => SecureRandom.uuid,
        }
        
        begin
          pp "Making request to: #{url}"
          pp "Headers: #{JSON.pretty_generate(headers)}"
          
          response = RestClient::Request.execute(
            method: :get,
            url: url,
            headers: headers,
            **data[:ssl_options]
          )
          puts "\n"
          pp "===================================================================="
          pp "response from get_oauth_authorization_status: #{response}"
          pp "===================================================================="
          puts "\n"
          
          data[:authorization_status] = JSON.parse(response.body)
        rescue RestClient::ExceptionWithResponse => e
          pp "HTTP Request failed with response code #{e.http_code}"
          pp "Response body: #{e.response.body}"
          pp "Request headers: #{headers}"
          data[:authorization_status] = nil
        rescue StandardError => e
          pp "An error occurred: #{e.message}"
          pp "Full error: #{e.class}: #{e.message}"
          pp e.backtrace.join("\n") if e.backtrace
          data[:authorization_status] = nil
        end
      end
      
      data
    end
    # Step to check authorization status
    step "get_oauth_authorization_status" do |data|
      if data[:authorization_id]
        url = "#{data[:base_url]}/oauth/authorisations/#{data[:authorization_id]}"
        
        headers = {
          'Accept' => 'application/hal+json;charset=UTF-8',
          'X-Request-ID' => SecureRandom.uuid,
        }
        
        begin
          pp "Making request to: #{url}"
          pp "Headers: #{JSON.pretty_generate(headers)}"
          
          response = RestClient::Request.execute(
            method: :get,
            url: url,
            headers: headers,
            **data[:ssl_options]
          )
          puts "\n"
          pp "===================================================================="
          pp "response from get_oauth_authorization_status: #{response}"
          pp "===================================================================="
          puts "\n"
          
          data[:authorization_status] = JSON.parse(response.body)
        rescue RestClient::ExceptionWithResponse => e
          pp "HTTP Request failed with response code #{e.http_code}"
          pp "Response body: #{e.response.body}"
          pp "Request headers: #{headers}"
          data[:authorization_status] = nil
        rescue StandardError => e
          pp "An error occurred: #{e.message}"
          pp "Full error: #{e.class}: #{e.message}"
          pp e.backtrace.join("\n") if e.backtrace
          data[:authorization_status] = nil
        end
      end
      
      data
    end
    # Step to check authorization status
    step "get_oauth_authorization_status" do |data|
      if data[:authorization_id]
        url = "#{data[:base_url]}/oauth/authorisations/#{data[:authorization_id]}"
        
        headers = {
          'Accept' => 'application/hal+json;charset=UTF-8',
          'X-Request-ID' => SecureRandom.uuid,
        }
        
        begin
          pp "Making request to: #{url}"
          pp "Headers: #{JSON.pretty_generate(headers)}"
          
          response = RestClient::Request.execute(
            method: :get,
            url: url,
            headers: headers,
            **data[:ssl_options]
          )
          puts "\n"
          pp "===================================================================="
          pp "response from get_oauth_authorization_status: #{response}"
          pp "===================================================================="
          puts "\n"
          
          data[:authorization_status] = JSON.parse(response.body)
        rescue RestClient::ExceptionWithResponse => e
          pp "HTTP Request failed with response code #{e.http_code}"
          pp "Response body: #{e.response.body}"
          pp "Request headers: #{headers}"
          data[:authorization_status] = nil
        rescue StandardError => e
          pp "An error occurred: #{e.message}"
          pp "Full error: #{e.class}: #{e.message}"
          pp e.backtrace.join("\n") if e.backtrace
          data[:authorization_status] = nil
        end
      end
      
      data
    end
    # Step to check authorization status
    step "get_oauth_authorization_status" do |data|
      if data[:authorization_id]
        url = "#{data[:base_url]}/oauth/authorisations/#{data[:authorization_id]}"
        
        headers = {
          'Accept' => 'application/hal+json;charset=UTF-8',
          'X-Request-ID' => SecureRandom.uuid,
        }
        
        begin
          pp "Making request to: #{url}"
          pp "Headers: #{JSON.pretty_generate(headers)}"
          
          response = RestClient::Request.execute(
            method: :get,
            url: url,
            headers: headers,
            **data[:ssl_options]
          )
          puts "\n"
          pp "===================================================================="
          pp "response from get_oauth_authorization_status: #{response}"
          pp "===================================================================="
          puts "\n"
          
          data[:authorization_status] = JSON.parse(response.body)
        rescue RestClient::ExceptionWithResponse => e
          pp "HTTP Request failed with response code #{e.http_code}"
          pp "Response body: #{e.response.body}"
          pp "Request headers: #{headers}"
          data[:authorization_status] = nil
        rescue StandardError => e
          pp "An error occurred: #{e.message}"
          pp "Full error: #{e.class}: #{e.message}"
          pp e.backtrace.join("\n") if e.backtrace
          data[:authorization_status] = nil
        end
      end
      
      data
    end
=end
    # Step to get OAuth token
    step "get_oauth_token" do |data|
      if data[:code] && data[:client_id]
        pp "======================================================================="
        pp "Getting OAuth token with:"
        pp "Authorization Code: #{data[:code]}"
        pp "Client ID: #{data[:client_id]}"
        pp "======================================================================="

        url = "#{data[:base_url].gsub('/v1', '')}/oauth/token"
        
        headers = {
          'Content-Type' => 'application/x-www-form-urlencoded'
        }
        
        payload = [
          "client_id=#{data[:client_id]}",
          "grant_type=authorization_code",
          "code=#{data[:code]}"
        ].join('&')

        begin
          pp "Making request to: #{url}"
          pp "Headers: #{headers}"
          pp "Payload: #{payload}"
          
          response = RestClient::Request.execute(
            method: :post,
            url: url,
            payload: payload,
            headers: headers,
            **data[:ssl_options]
          )
          
          data[:token_result] = JSON.parse(response.body)
        rescue RestClient::ExceptionWithResponse => e
          pp "HTTP Request failed with response code #{e.http_code}"
          pp "Response body: #{e.response.body}"
          pp "Request headers: #{headers}"
          pp "Request payload: #{payload}"
          data[:token_result] = nil
        rescue StandardError => e
          pp "An error occurred: #{e.message}"
          pp e.backtrace.join("\n") if e.backtrace
          data[:token_result] = nil
        end
      end
      
      data
    end
  end
  
  # Define error handling
  on_error do |error, data|
    pp "Error in LHV OAuth workflow: #{error.message}"
    data[:error] = {
      message: error.message,
      type: error.class.name
    }
    data
  end
end

# Simple example of usage if run directly
if __FILE__ == $0
  puts "LHV OAuth Workflow loaded successfully!"
  
  # Create an authorization
  puts "\n=== Step 1: Creating OAuth authorization ==="
  puts "\n === before function call === \n"
  
  result = Navesti.run(:lhv_oauth, {
    authentication_method_id: 'BIO'
  })
  
  pp "result: #{result}"
  pp "test"
  pp result[:authorization_result]
  puts "\n === after function call === \n"

  if result[:authorization_result]
    puts "\nAuthorization successful!"
    puts "Authorization ID: #{result[:authorization_result]['authorisationId']}"
    puts "Status: #{result[:authorization_result]['scaStatus']}"
    
    # Check status
    puts "\n=== Step 2: Checking authorization status ==="
    auth_id = result[:authorization_result]['authorisationId']
    status = Navesti.run(:lhv_oauth, {
      authorization_id: auth_id
    })
    
    if status[:authorization_status]
      puts "\nStatus check successful!"
      puts "Status: #{status[:authorization_status]['scaStatus']}"
      
      # If authorization is complete, get token
      if status[:authorization_status]['scaStatus'] == 'FINALISED' &&
         status[:authorization_status]['authorizationCode']
         
        puts "\n=== Step 3: Getting OAuth token ==="
        auth_code = status[:authorization_status]['authorizationCode']
        token = Navesti.run(:lhv_oauth, {
          code: auth_code,
          client_id: ENV['LHV_CLIENT_ID'] || 'PSDEE-LHVTEST-820163'
        })
        
        if token[:token_result]
          puts "\nToken retrieval successful!"
          puts "Access Token: #{token[:token_result]['access_token']}"
          puts "Expires In: #{token[:token_result]['expires_in']} seconds"
        else
          puts "\nToken retrieval FAILED"
          puts "Error: #{token[:error].inspect}" if token[:error]
        end
      else
        puts "\nAuthorization not yet completed"
        puts "Current status: #{status[:authorization_status]['scaStatus']}"
        puts "Waiting 10 seconds before checking again..."
        sleep 10
        status = Navesti.run(:lhv_oauth, {
          authorization_id: auth_id
        })
        puts "Current status: #{status[:authorization_status]['scaStatus']}"
        # If authorization is complete, get token
        if status[:authorization_status]['scaStatus'] == 'FINALISED' &&
          status[:authorization_status]['authorisationCode']
          
          puts "\n=== Step 3: Getting OAuth token ==="
          auth_code = status[:authorization_status]['authorisationCode']
          token = Navesti.run(:lhv_oauth, {
          code: auth_code,
          client_id: ENV['LHV_CLIENT_ID'] || 'PSDEE-LHVTEST-820163'
          })
        
          if token[:token_result]
            puts "\nToken retrieval successful!"
            puts "Access Token: #{token[:token_result]['access_token']}"
            puts "Expires In: #{token[:token_result]['expires_in']} seconds"
          else
            puts "\nToken retrieval FAILED"
            puts "Error: #{token[:error].inspect}" if token[:error]
          end 
        end
      end
    else
      puts "\nStatus check FAILED"
      puts "Error: #{status[:error].inspect}" if status[:error]
    end
  else
    puts "\nAuthorization FAILED"
    puts "Error: #{result[:error].inspect}" if result[:error]
    puts "SSL Error: #{result[:ssl_error]}" if result[:ssl_error]
  end
  
  puts "\n=== Workflow execution completed ==="
end
