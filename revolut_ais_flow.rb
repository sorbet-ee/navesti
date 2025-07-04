require 'date'
require 'time'
require 'uri'
require 'json'
require 'jwt'
require 'openssl'
require_relative 'navesti'
require_relative 'revolut_flow'

puts "Starting the Revolut Open Banking AIS workflow..."
begin
    #
    # :show_transactions
    #
    input_data = {
        base_url: "https://sandbox-oba-auth.revolut.com",
        client_id: "d099c903-2443-410e-844e-7282c6ec118f",
        scope: "accounts payments",
        grant_type: "client_credentials",
        ssl_options: {
            client_cert: OpenSSL::X509::Certificate.new(File.read(File.expand_path('./config/certs/transport.pem'))),
            client_key: OpenSSL::PKey::RSA.new(File.read(File.expand_path('./config/certs/private.key'))),
            verify: false
        },
        response_type: "code"
    }
    show_transactions_response = Navesti.run(:show_transactions, input_data)
    pp "Show Transactions Response:"
    pp show_transactions_response
rescue => e
    puts "An error occurred during workflow execution:"
    puts e.message
end
