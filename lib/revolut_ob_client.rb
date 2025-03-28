require 'json'
require 'rest-client'
require 'securerandom'
require 'pp'
require 'jwt'

class RevolutOBClient
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

  def get_access_token
    url = "#{@BASE_URL}/token"

    headers = {
      'Content-Type' => 'application/x-www-form-urlencoded'
    }

    payload = URI.encode_www_form(
      'grant_type' => 'client_credentials',
      'scope' => 'accounts',
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
          'ReadAccountsDetail'
        ],
        'ExpirationDateTime' => '2022-12-02T00:00:00+00:00',
        'TransactionFromDateTime' => '2022-09-03T00:00:00+00:00',
        'TransactionToDateTime' => '2022-12-03T00:00:00+00:00'
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

  def get_consent_from_the_user(access_token:, consent_id:)
    header = {
      "alg": "PS256",
      "kid": "007"
    }

    payload = URI.encode_www_form({
      'response_type' => 'code id_token',
      'client_id' => @client_id,
      'redirect_uri' => 'https://example.com',
      'aud' => 'https://sandbox-oba-auth.revolut.com',
      'scope' => 'accounts',
      'state' => "#{SecureRandom.uuid}",
      'nbf' => 1738158653,
      'exp' => 1738161953,
      'claims' => {
        'id_token' => {
          'openbanking_intent_id' => {
            'value' => "#{consent_id}"
          }
        }
      }
    })

    jwt = JWT.encode(payload, @ssl_options[:ssl_client_key], 'PS256', header)
    revolut_url = "https://sandbox-oba.revolut.com/ui/index.html?response_type=code%20id_token&scope=accounts&redirect_uri=https://example.com&client_id=d099c903-2443-410e-844e-7282c6ec118f&request=#{jwt}"
  end

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
end
