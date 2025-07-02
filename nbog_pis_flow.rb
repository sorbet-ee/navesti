require 'date'
require 'time'
require 'uri'
require 'json'
require_relative 'navesti'
require_relative 'nbog_flow'

puts "Starting the NBOG Open Banking PIS workflow..."

begin
    #
    # :payment_initiation
    #
    input_data = {
        base_accounts_url: "https://apis.nbg.gr/sandbox/bg.openbanking.accounts/oauth2/v1",
        base_payments_url: "https://apis.nbg.gr/sandbox/bg.openbanking.payments/oauth2/v1",
        client_id: "FBF3FB60-F0D4-45A4-B7A1-C111DA8D50F5",
        client_secret: "AF8A61F4-6F34-4E8E-8735-71848123E293",
        scope: "sandbox-bg-ob-accounts offline_access",
        grant_type: "authorization_code",
        response_type: "code",
        redirect_uri: "https://developer.nbg.gr/oauth2/redoc-callback",
        psu_ip_address: "127.0.0.1"
    }
    payment_initiation_response = Navesti.run(:payment_initiation, input_data)
    pp "Payment Initiation Response:"
    pp payment_initiation_response
rescue => e
    puts "An error occurred during workflow execution:"
    puts e.message
end
