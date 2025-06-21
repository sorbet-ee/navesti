require 'date'
require 'time'
require 'uri'
require 'json'
require_relative 'navesti'
require_relative 'swedbank_flow'

puts "Starting the Swedbank Open Banking PIS workflow..."

begin
  #
  # :initiate_payment
  #
  input_data = {
    access_token: "dummyToken",
    tpp_redirect_preferred: "true",
    recurring_indicator: true,
    base_url: "https://psd2.api.swedbank.com:443",
    bic: "SANDEE2X",
    app_id: "l7276866044e8c45d2856ae3f64fdd3d74"
  }
  url = "#{input_data[:base_url]}/sandbox/v5/payments/sepa-credit-transfers?bic=#{input_data[:bic]}&app-id=#{input_data[:app_id]}"
  input_data[:url] = url
  headers = {
    'Content-Type' => 'application/json',
    'Accept' => 'application/hal+json;charset=UTF-8',
    'X-Request-ID' => SecureRandom.uuid,
    'Authorization' => "Bearer #{input_data[:access_token]}",
    'Date' => Time.now.utc.httpdate,
    'PSU-IP-Address' => '127.0.0.1',
    'PSU-User-Agent' => 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:137.0) Gecko/20100101 Firefox/137.0',
    'TPP-Redirect-Preferred' => input_data[:tpp_redirect_preferred],
    'TPP-Redirect-URI' => 'https://google.com',
    'TPP-Explicit-Authorisation-Preferred' => 'false'
  }
  input_data[:debtor_iban] = "EE872200221001012135"
  input_data[:amount] = '1'
  input_data[:creditor_iban] = 'SE12345678901234567890'
  input_data[:creditor_name] = 'John Doe'
  input_data[:remittance_info] = 'Test payment'
  input_data[:execution_date] = Date.today.to_s
  payload = {
    debtorAccount: { iban: input_data[:debtor_iban] },
    instructedAmount: { currency: "EUR", amount: input_data[:amount] },
    creditorAccount: { iban: input_data[:creditor_iban] },
    creditorName: input_data[:creditor_name],
    remittanceInformationUnstructured: input_data[:remittance_info],
    requestedExecutionDate: input_data[:execution_date],
    endToEndIdentification: '1234567890'
  }
  final_data = input_data.merge(payload: payload, headers: headers)
  puts "Running workflow initiate_payment..."
  result = Navesti.run(:initiate_payment, final_data)
  puts "Workflow initiate_payment completed successfully!"
  puts "Final Result:"
  pp JSON.pretty_generate(result)
rescue => e
  puts "An error occurred during workflow execution:"
  puts e.message
end