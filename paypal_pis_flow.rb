require_relative 'navesti'
require_relative 'paypal_flow'

puts "Starting the PayPal Open Banking PIS workflow..."
begin
    #
    # :order
    #
    input_data = {
        base_url: "https://api-m.sandbox.paypal.com",
        client_id: "AcE-ZydM9YUjzpbEByyHtVXeA5gQMIsmiqemlx8tlRJjRzPxX_-oBBqKodayrPqVffOpcgSKvJ9vmQl0",
        client_secret: "EOo0jkkPAE8qIfWJQ1D56FGmkEM95fJZN4EBPnAJBB0-31B_9TTF13EBVLytekrn8eQvgdpyew_HcaYP"
    }
    order_response = Navesti.run(:order, input_data)
    pp "Order Response:"
    pp order_response
rescue => e
    puts "An error occurred during workflow execution:"
    puts e.message
end
