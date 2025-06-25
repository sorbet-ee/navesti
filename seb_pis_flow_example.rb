require 'date'
require 'time'
require 'uri'
require 'json'
require_relative 'navesti'
require_relative 'seb_flow'

puts "Starting the SEB Open Banking PIS workflow..."

begin
  #
  # :payment_initiation
  #
  input_data = {
    base_url: "https://api-sandbox.sebgroup.com",
    client_id: "862ca6cbb1d844d8a10ed98008e73be0",
    client_secret: "f15048d4d5e841698e52b3c817f78f75",
    authorization_version: "v4",
    account_information_version: "v8",
    funds_confirmation_version: "v7",
    payment_initiation_version: "v8",
    scope: "psd2_payments"
  }
  headers = {
    "Content-Type" => "application/json",
    "PSU-IP-Address" => "127.0.0.1"
  }
  final_data = input_data.merge(headers: headers)
  puts "Running workflow payment_initiation..."
  pp "final_data:"
  pp JSON.pretty_generate(final_data)
  result = Navesti.run(:payment_initiation, final_data)
  puts "Workflow payment_initiation completed."
  puts "Final Result:"
  pp JSON.pretty_generate(result)
rescue => e
  puts "An error occurred during workflow execution:"
  puts e.message
end


