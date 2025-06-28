require 'json'
require_relative 'navesti'
require_relative 'boc_flow'

puts 'Starting the BOC Open Banking AIS workflow...'

begin
  data = {
    base_url: 'https://sandbox-apis.bankofcyprus.com/df-boc-org-sb/sb/psd2',
    client_id: '62a04ef10e18b8bdec1e1301b4c828f2',
    client_secret: '2edb0a48a6e959d53fcf636132dfb3c5',
    scope: 'TPPOAuth2Security',
    grant_type: 'client_credentials',
    headers: {
      'Content-Type' => 'application/x-www-form-urlencoded',
      'Accept' => 'application/json'
    }
  }

  result = Navesti.run(:show_account_transactions, data)
  puts 'Workflow show_account_transactions completed.'
  puts 'Final Result:'
  pp JSON.pretty_generate(result)
rescue => e
  puts 'An error occurred during workflow execution:'
  puts e.message
end
