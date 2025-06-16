require 'date'
require 'time'
require 'uri'
require 'json'
require_relative 'navesti'
require_relative 'swedbank_flow'

puts "Starting the Swedbank Open Banking AIS workflow..."

input_data = {
  access_token: "dummyToken",
  tpp_redirect_preferred: "true",
  frequency_per_day: "1",
  recurring_indicator: false,
  iban: nil,
  base_url: "https://psd2.api.swedbank.com:443",
  bic: "SANDEE2X",
  app_id: "l7276866044e8c45d2856ae3f64fdd3d74"
}
url = "#{input_data[:base_url]}/sandbox/v5/consents?bic=#{input_data[:bic]}&app-id=#{input_data[:app_id]}"
input_data[:url] = url
payload = {
    "access" => {
      "availableAccounts" => "allAccounts"
    },
    "combinedServiceIndicator" => false,
    "frequencyPerDay" => 1,
    "recurringIndicator" => input_data[:recurring_indicator],
    "validUntil" => Date.today.to_s
  }
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
final_data = input_data.merge(payload: payload, headers: headers)
begin
  puts "Running workflow with input:"
  puts final_data.inspect

  # Execute the workflow using the SorbetFlow DSL
  result = Navesti.run(:show_accounts, final_data)
  puts "Workflow completed successfully!"
  puts "Final Result:"
  pp JSON.pretty_generate(result)
rescue => e
  puts "An error occurred during workflow execution:"
  puts e.message
end
  

#### TO RUN ####
# ruby ./src/swedbank_flow_example.rb inside the navesti directory