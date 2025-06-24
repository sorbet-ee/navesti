require 'date'
require 'time'
require 'uri'
require 'json'
require_relative 'navesti'
require_relative 'seb_flow'

puts "Starting the SEB Open Banking AIS workflow..."

begin
  #
  # :show_accounts
  #
  input_data = {
    base_url: "https://api-sandbox.sebgroup.com",
    client_id: "862ca6cbb1d844d8a10ed98008e73be0",
    client_secret: "f15048d4d5e841698e52b3c817f78f75",
    authorization_version: "v4",
    account_information_version: "v8",
    funds_confirmation_version: "v7",
    payment_initiation_version: "v8",
    scope: "psd2_accounts"
  }
  headers = {
    "Content-Type" => "application/json",
    "PSU-IP-Address" => "127.0.0.1"
  }
  final_data = input_data.merge(headers: headers)
  puts "Running workflow show_accounts..."
  puts "input_data:"
  pp JSON.pretty_generate(final_data)
  result = Navesti.run(:show_accounts, final_data)
  puts "Workflow show_accounts completed."
  puts "Final Result:"
  pp JSON.pretty_generate(result)
  #
  # :show_account
  #
  puts "Running workflow show_account..."
  result = Navesti.run(:show_account, final_data)
  puts "Workflow show_account completed."
  puts "Final Result:"
  pp JSON.pretty_generate(result)
  #
  # :show_account_balances
  #
  puts "Running workflow show_account_balances..."
  result = Navesti.run(:show_account_balances, final_data)
  puts "Workflow show_account_balances completed."
  puts "Final Result:"
  pp JSON.pretty_generate(result)
  #
  # :show_account_transactions
  #
  puts "Running workflow show_account_transactions..."
  result = Navesti.run(:show_account_transactions, final_data)
  puts "Workflow show_account_transactions completed."
  puts "Final Result:"
  pp JSON.pretty_generate(result)
  #
  # :show_account_transactions_details
  #
  puts "Running workflow show_account_transactions_details..."
  result = Navesti.run(:show_account_transactions_details, final_data)
  puts "Workflow show_account_transactions_details completed."
  puts "Final Result:"
  pp JSON.pretty_generate(result)
rescue => e
  puts "An error occurred during workflow execution:"
  puts e.message
end



#### TO RUN ####
# ruby ./src/seb_ais_flow_example.rb inside the navesti directory