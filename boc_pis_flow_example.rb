require 'date'
require 'time'
require 'uri'
require 'json'
require_relative 'navesti'
require_relative 'boc_flow'

puts "Starting the BOC Open Banking PIS workflow..."
begin
    input_data = {
        base_url: "https://sandbox-apis.bankofcyprus.com/df-boc-org-sb/sb/psd2",
        client_id: "62a04ef10e18b8bdec1e1301b4c828f2",
        client_secret: "2edb0a48a6e959d53fcf636132dfb3c5",
        scope: "TPPOAuth2Security",
        grant_type: "client_credentials"
    }
    headers = {
        "Content-Type" => "application/x-www-form-urlencoded",
        "Accept" => "application/json"
    }
    final_data = input_data.merge(headers: headers)
    puts "Running workflow payment_initiation..."
    pp "Runnin workflow with initial final data:"
    pp JSON.pretty_generate(final_data)
    result = Navesti.run(:payment_initiation, final_data)
    puts "Workflow payment_initiation completed."
    #puts "Final Result:"
    #pp JSON.pretty_generate(result)
rescue => e
    puts "An error occurred during workflow execution:"
    puts e.message
end

    