require 'spec_helper'
require 'json'
require 'logger'
require 'jwt'
require 'launchy'

# Initialize logger with timestamp in filename
timestamp = Time.now.strftime('%Y%m%d_%H%M%S')
LOG_FILE = File.expand_path("../../test_results/accounts_tests_#{timestamp}.log", __FILE__)
FileUtils.mkdir_p(File.dirname(LOG_FILE))

# Clear the log file at start
File.write(LOG_FILE, "Starting Accounts Test Suite: #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}\n\n")

LOGGER = Logger.new(LOG_FILE).tap do |log|
  log.level = Logger::INFO
  log.formatter = proc do |severity, datetime, progname, msg|
    timestamp = datetime.strftime('%Y-%m-%d %H:%M:%S.%L')
    "[#{timestamp}] #{severity}\n#{msg}\n"
  end
end

RSpec.describe RevolutOBClient do
  let(:client) { described_class.new }
  let(:access_token) do
    access_token_path = File.expand_path('../test_results/access_token.json', __dir__)
    JSON.parse(File.read(access_token_path))['access_token']
  end
  let(:consent_id) do
    account_access_consent_path = File.expand_path('../test_results/account_access_consent.json', __dir__)
    JSON.parse(File.read(account_access_consent_path))['Data']['ConsentId']
  end
  let(:code) do
    code_path = File.expand_path('../test_results/code.json', __dir__)
    JSON.parse(File.read(code_path))['code']
  end
  let(:new_access_token) do
    new_access_token_path = File.expand_path('../test_results/new_access_token.json', __dir__)
    JSON.parse(File.read(new_access_token_path))['access_token']
  end
  let(:accounts) do
    accounts_path = File.expand_path('../test_results/accounts.json', __dir__)
    JSON.parse(File.read(accounts_path))
  end

  describe "#get_access_token" do
    it "returns a valid access token" do
      LOGGER.info("↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓")
      LOGGER.info("Getting access token...")
      puts "↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓"
      puts "Getting access token..."
      access_token = client.get_access_token
      LOGGER.info("Access token:\n#{JSON.pretty_generate(access_token)}")
      puts "Access token:\n#{JSON.pretty_generate(access_token)}"
      LOGGER.info("↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑")
      puts "↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑"

      expect(access_token).to be_a(Hash)
      expect(access_token).not_to be_empty
      expect(access_token).to have_key('access_token')
      expect(access_token).to have_key('token_type')
      expect(access_token).to have_key('expires_in')
      expect(access_token['token_type']).to eq('Bearer')

      # Save the access token and metadata to a file
      access_token_file = File.expand_path('../test_results/access_token.json', __dir__)
      File.write(access_token_file, JSON.pretty_generate({
        access_token: access_token['access_token'],
        token_type: access_token['token_type'],
        expires_in: access_token['expires_in']
      }))

      LOGGER.info("Access token saved to file: #{access_token_file}")
      LOGGER.info("Access token establishment completed successfully")
    end
  end

  describe "#create_an_account_access_consent" do
    it "returns a valid account access consent" do
      LOGGER.info("↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓")
      LOGGER.info("Creating account access consent...")
      puts "↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓"
      puts "Creating account access consent..."
      account_access_consent = client.create_an_account_access_consent(access_token: access_token)
      LOGGER.info("Account access consent:\n#{JSON.pretty_generate(account_access_consent)}")
      puts "Account access consent:\n#{JSON.pretty_generate(account_access_consent)}"
      LOGGER.info("↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑")
      puts "↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑"

      expect(account_access_consent).to be_a(Hash)
      expect(account_access_consent).not_to be_empty
      expect(account_access_consent).to have_key('Data')
      expect(account_access_consent['Data']).to have_key('Status')
      expect(account_access_consent['Data']['Status']).to eq('AwaitingAuthorisation')
      expect(account_access_consent['Data']).to have_key('ConsentId')
      expect(account_access_consent['Data']['ConsentId']).not_to be_empty
      expect(account_access_consent['Data']).to have_key('CreationDateTime')
      expect(account_access_consent['Data']['CreationDateTime']).not_to be_empty
      expect(account_access_consent['Data']).to have_key('StatusUpdateDateTime')
      expect(account_access_consent['Data']['StatusUpdateDateTime']).not_to be_empty
      expect(account_access_consent['Data']).to have_key('TransactionFromDateTime')
      expect(account_access_consent['Data']['TransactionFromDateTime']).not_to be_empty
      expect(account_access_consent['Data']).to have_key('TransactionToDateTime')
      expect(account_access_consent['Data']['TransactionToDateTime']).not_to be_empty
      expect(account_access_consent['Data']).to have_key('ExpirationDateTime')
      expect(account_access_consent['Data']['ExpirationDateTime']).not_to be_empty
      expect(account_access_consent['Data']).to have_key('Permissions')
      expect(account_access_consent['Data']['Permissions']).not_to be_empty
      expect(account_access_consent['Data']['Permissions']).to be_an(Array)
      expect(account_access_consent).to have_key('Risk')
      expect(account_access_consent['Risk']).to be_a(Hash)

      # Save the account access consent to a file
      account_access_consent_file = File.expand_path('../test_results/account_access_consent.json', __dir__)
      File.write(account_access_consent_file, JSON.pretty_generate(account_access_consent))

      LOGGER.info("Account access consent saved to file: #{account_access_consent_file}")
      LOGGER.info("Account access consent establishment completed successfully")
    end
  end

  describe "#retrieve_an_account_access_consent" do
    it "returns a valid account access consent" do
      LOGGER.info("↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓")
      LOGGER.info("Retrieving account access consent...")
      puts "↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓"
      puts "Retrieving account access consent..."
      account_access_consent = client.retrieve_an_account_access_consent(
        access_token: access_token, \
        consent_id: consent_id)
      LOGGER.info("Account access consent:\n#{JSON.pretty_generate(account_access_consent)}")
      puts "Account access consent:\n#{JSON.pretty_generate(account_access_consent)}"
      LOGGER.info("↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑")
      puts "↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑"

      expect(account_access_consent).to be_a(Hash)
      expect(account_access_consent).not_to be_empty
      expect(account_access_consent).to have_key('Data')
      expect(account_access_consent['Data']).to have_key('Status')
      expect(account_access_consent['Data']['Status']).to eq('AwaitingAuthorisation')
      expect(account_access_consent['Data']).to have_key('ConsentId')
      expect(account_access_consent['Data']['ConsentId']).not_to be_empty
      expect(account_access_consent['Data']).to have_key('CreationDateTime')
      expect(account_access_consent['Data']['CreationDateTime']).not_to be_empty
      expect(account_access_consent['Data']).to have_key('StatusUpdateDateTime')
      expect(account_access_consent['Data']['StatusUpdateDateTime']).not_to be_empty
      expect(account_access_consent['Data']).to have_key('TransactionFromDateTime')
      expect(account_access_consent['Data']['TransactionFromDateTime']).not_to be_empty
      expect(account_access_consent['Data']).to have_key('TransactionToDateTime')
      expect(account_access_consent['Data']['TransactionToDateTime']).not_to be_empty
      expect(account_access_consent['Data']).to have_key('ExpirationDateTime')
      expect(account_access_consent['Data']['ExpirationDateTime']).not_to be_empty
      expect(account_access_consent['Data']).to have_key('Permissions')
      expect(account_access_consent['Data']['Permissions']).not_to be_empty
      expect(account_access_consent['Data']['Permissions']).to be_an(Array)
      expect(account_access_consent).to have_key('Risk')
      expect(account_access_consent['Risk']).to be_a(Hash)
    end
  end
  
  describe "#get_consent_from_the_user" do
    it "returns a valid code" do
      auth_data = client.get_consent_from_the_user(access_token: access_token, consent_id: consent_id)
      LOGGER.info("Checking consent status after authorization")
      puts "Checking consent status after authorization"
      consent_status = client.retrieve_an_account_access_consent(access_token: access_token, consent_id: consent_id)
      LOGGER.info("Consent status: #{consent_status['Data']['Status']}")
      puts "Consent status: #{consent_status['Data']['Status']}"

      expect(consent_status['Data']['Status']).to eq('Authorised')

      LOGGER.info("Code: #{auth_data[:code]}")
      puts "Code: #{auth_data[:code]}"
      expect(auth_data[:code]).not_to be_empty
      expect(auth_data[:code]).to be_a(String)

      # Save the code to a file
      code_file = File.expand_path('../test_results/code.json', __dir__)
      File.write(code_file, JSON.pretty_generate(auth_data))

      LOGGER.info("Code saved to file: #{code_file}")
      LOGGER.info("Authorization completed successfully")
    end
  end

  describe "#exchange_code_for_access_token" do
    it "returns a valid access token" do
      LOGGER.info("↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓")
      LOGGER.info("Exchanging code for access token...")
      puts "↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓"
      puts "Exchanging code for access token..."
      access_token = client.exchange_code_for_access_token(code: code)
      LOGGER.info("Response: #{JSON.pretty_generate(access_token)}")
      puts "Response: #{JSON.pretty_generate(access_token)}"
      LOGGER.info("↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑")
      puts "↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑"
      expect(access_token).to be_a(Hash)
      expect(access_token).not_to be_empty
      expect(access_token).to have_key('access_token')
      expect(access_token['access_token']).not_to be_empty
      expect(access_token).to have_key('access_token_id')
      expect(access_token['access_token_id']).not_to be_empty
      expect(access_token).to have_key('id_token')
      expect(access_token['id_token']).not_to be_empty
      expect(access_token).to have_key('token_type')
      expect(access_token['token_type']).not_to be_empty
      expect(access_token).to have_key('expires_in')

      # Save the access token to a file
      access_token_file = File.expand_path('../test_results/new_access_token.json', __dir__)
      File.write(access_token_file, JSON.pretty_generate(access_token))

      LOGGER.info("Access token saved to file: #{access_token_file}")
      LOGGER.info("Access token establishment completed successfully")
    end
  end

  describe "#retrieve_all_accounts" do
    it "returns a valid list of accounts" do
      LOGGER.info("↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓")
      LOGGER.info("Retrieving all accounts...")
      puts "↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓"
      puts "Retrieving all accounts..."
      accounts = client.retrieve_all_accounts(access_token: new_access_token)
      LOGGER.info("Accounts:\n#{JSON.pretty_generate(accounts)}")
      puts "Accounts:\n#{JSON.pretty_generate(accounts)}"
      LOGGER.info("↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑")
      puts "↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑"
      expect(accounts).to be_a(Hash)
      expect(accounts).not_to be_empty
      expect(accounts).to have_key('Data')

      # Save the accounts to a file
      accounts_file = File.expand_path('../test_results/accounts.json', __dir__)
      File.write(accounts_file, JSON.pretty_generate(accounts))

      LOGGER.info("Accounts saved to file: #{accounts_file}")
      LOGGER.info("Accounts retrieval completed successfully")
    end
  end

  describe "#retrieve_an_account" do 
    it "returns a valid account" do
      LOGGER.info("↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓")
      LOGGER.info("Retrieving an account...")
      puts "↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓"
      puts "Retrieving an account..."
      account = client.retrieve_an_account(new_access_token: new_access_token, account_id: accounts['Data']['Account'][0]['AccountId'])
      LOGGER.info("Account:\n#{JSON.pretty_generate(account)}")
      puts "Account:\n#{JSON.pretty_generate(account)}"
      LOGGER.info("↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑")
      puts "↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑"
      expect(account).to be_a(Hash)
      expect(account).not_to be_empty
      expect(account).to have_key('Data')

      
    end
  end

  describe "#retrieve_an_account_balance" do
    it "returns a valid account balance" do
      LOGGER.info("↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓")
      LOGGER.info("Retrieving an account balance...")
      puts "↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓"
      puts "Retrieving an account balance..."
      account_balance = client.retrieve_an_account_balance(new_access_token: new_access_token, account_id: accounts['Data']['Account'][0]['AccountId'])
      LOGGER.info("Account balance:\n#{JSON.pretty_generate(account_balance)}")
      puts "Account balance:\n#{JSON.pretty_generate(account_balance)}"
      LOGGER.info("↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑")
      puts "↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑"
      expect(account_balance).to be_a(Hash)
      expect(account_balance).not_to be_empty
      expect(account_balance).to have_key('Data')
    end
  end

  describe "#retrieve_an_accounts_all_beneficiaries" do
    it "returns a valid list of beneficiaries" do
      LOGGER.info("↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓")
      LOGGER.info("Retrieving an account's all beneficiaries...")
      puts "↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓"
      puts "Retrieving an account's all beneficiaries..."
      beneficiaries = client.retrieve_an_accounts_all_beneficiaries(new_access_token: new_access_token, account_id: accounts['Data']['Account'][0]['AccountId'])
      LOGGER.info("Beneficiaries:\n#{JSON.pretty_generate(beneficiaries)}")
      puts "Beneficiaries:\n#{JSON.pretty_generate(beneficiaries)}"
      LOGGER.info("↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑")
      puts "↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑"
      expect(beneficiaries).to be_a(Hash)
      expect(beneficiaries).not_to be_empty
      expect(beneficiaries).to have_key('Data')
    end
  end
=begin
  describe "#retrieve_an_accounts_all_direct_debits" do
    it "returns a valid list of direct debits" do
      LOGGER.info("↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓")
      LOGGER.info("Retrieving an account's all direct debits...")
      puts "↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓"
      puts "Retrieving an account's all direct debits..."
      direct_debits = client.retrieve_an_accounts_all_direct_debits(new_access_token: new_access_token, account_id: accounts['Data']['Account'][0]['AccountId'])
      LOGGER.info("Direct debits:\n#{JSON.pretty_generate(direct_debits)}")
      puts "Direct debits:\n#{JSON.pretty_generate(direct_debits)}"
      LOGGER.info("↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑")
      puts "↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑"
      expect(direct_debits).to be_a(Hash)
      expect(direct_debits).not_to be_empty
      expect(direct_debits).to have_key('Data')
    end
  end
=end
  describe "#retrieve_an_accounts_all_standing_orders" do
    it "returns a valid list of standing orders" do
      LOGGER.info("↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓")
      LOGGER.info("Retrieving an account's all standing orders...")
      puts "↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓"
      puts "Retrieving an account's all standing orders..."
      standing_orders = client.retrieve_an_accounts_all_standing_orders(new_access_token: new_access_token, account_id: accounts['Data']['Account'][0]['AccountId'])
      LOGGER.info("Standing orders:\n#{JSON.pretty_generate(standing_orders)}")
      puts "Standing orders:\n#{JSON.pretty_generate(standing_orders)}"
      LOGGER.info("↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑")
      puts "↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑"
      expect(standing_orders).to be_a(Hash)
      expect(standing_orders).not_to be_empty
      expect(standing_orders).to have_key('Data')
    end
  end

  describe "#retrieve_an_accounts_all_transactions" do
    it "returns a valid list of transactions" do
      LOGGER.info("↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓")
      LOGGER.info("Retrieving an account's all transactions...")
      puts "↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓"
      puts "Retrieving an account's all transactions..."
      transactions = client.retrieve_an_accounts_all_transactions(new_access_token: new_access_token, account_id: accounts['Data']['Account'][0]['AccountId'])
      LOGGER.info("Transactions:\n#{JSON.pretty_generate(transactions)}")
      puts "Transactions:\n#{JSON.pretty_generate(transactions)}"
      LOGGER.info("↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑")
      puts "↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑"
      expect(transactions).to be_a(Hash)
      expect(transactions).not_to be_empty
      expect(transactions).to have_key('Data')
    end
  end

end