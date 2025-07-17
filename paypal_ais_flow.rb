require_relative 'navesti'
require_relative 'paypal_flow'
require 'time'

puts "Starting the PayPal Open Banking AIS workflow..."
begin
    #
    # :show_balances
    #
    input_data = {
        base_url: "https://api-m.sandbox.paypal.com",
        client_id: "AcE-ZydM9YUjzpbEByyHtVXeA5gQMIsmiqemlx8tlRJjRzPxX_-oBBqKodayrPqVffOpcgSKvJ9vmQl0",
        client_secret: "EOo0jkkPAE8qIfWJQ1D56FGmkEM95fJZN4EBPnAJBB0-31B_9TTF13EBVLytekrn8eQvgdpyew_HcaYP",
        start_date: (Time.now - (60*60*60*24)).utc.iso8601(3),
        end_date: (Time.now - (30*60*60*24)).utc.iso8601(3)
    }
    show_balances_response = Navesti.run(:show_balances, input_data)
    pp "Show Balances Response:"
    pp show_balances_response
rescue => e
    puts "An error occurred during workflow execution:"
    puts e.message
end
