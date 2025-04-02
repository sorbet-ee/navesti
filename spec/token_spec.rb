require 'spec_helper'
require 'json'
require 'logger'
require 'jwt'

# Initialize logger with timestamp in filename
timestamp = Time.now.strftime('%Y%m%d_%H%M%S')
LOG_FILE = File.expand_path("../../test_results/token_tests_#{timestamp}.log", __FILE__)
FileUtils.mkdir_p(File.dirname(LOG_FILE))

# Clear the log file at start
File.write(LOG_FILE, "Starting Token Test Suite: #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}\n\n")

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
    oauth_token_path = File.expand_path('../test_results/access_token.json', __dir__)
    JSON.parse(File.read(oauth_token_path))['access_token']
  end
  let(:consent_id) do
    account_access_consent_path = File.expand_path('../test_results/account_access_consent.json', __dir__)
    JSON.parse(File.read(account_access_consent_path))['Data']['ConsentId']
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
    it "returns a redirect URL" do
      redirect_url = client.get_consent_from_the_user(access_token: access_token, consent_id: consent_id)
      puts "Redirect URL: #{redirect_url}"
      LOGGER.info("Redirect URL: #{redirect_url}")
      # Open the URL in the default web browser
      system("xdg-open '#{redirect_url}'") if RUBY_PLATFORM.include?("linux")  # Linux
      #system("open -a Safari '#{redirect_url}'") if RUBY_PLATFORM.include?("darwin")  # Mac
      system("start #{redirect_url}") if RUBY_PLATFORM.include?("mswin")  # Windows
      sleep 30
      LOGGER.info("Checking consent status after authorization")
      puts "Checking consent status after authorization"
      consent_status = client.retrieve_an_account_access_consent(access_token: access_token, consent_id: consent_id)
      LOGGER.info("Consent status: #{consent_status['Data']['Status']}")
      puts "Consent status: #{consent_status['Data']['Status']}"
      expect(consent_status['Data']['Status']).to eq('Authorised')
    end
  end


  describe "#retrieve_all_accounts" do
    it "returns a valid list of accounts" do
      LOGGER.info("↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓")
      LOGGER.info("Retrieving all accounts...")
      puts "↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓"
      puts "Retrieving all accounts..."
      accounts = client.retrieve_all_accounts(access_token: access_token)
      LOGGER.info("Accounts:\n#{JSON.pretty_generate(accounts)}")
      puts "Accounts:\n#{JSON.pretty_generate(accounts)}"
      LOGGER.info("↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑")
      puts "↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑"
=begin
      expect(accounts).to be_a(Hash)
      expect(accounts).not_to be_empty
      expect(accounts).to have_key('Data')
      expect(accounts['Data']).to be_an(Array)
      expect(accounts['Data']).not_to be_empty
      expect(accounts['Data'][0]).to have_key('Id')
      expect(accounts['Data'][0]['Id']).not_to be_empty
      expect(accounts['Data'][0]).to have_key('Status')
      expect(accounts['Data'][0]['Status']).not_to be_empty
      expect(accounts['Data'][0]).to have_key('CreationDateTime')
      expect(accounts['Data'][0]['CreationDateTime']).not_to be_empty
      expect(accounts['Data'][0]).to have_key('StatusUpdateDateTime')
      expect(accounts['Data'][0]['StatusUpdateDateTime']).not_to be_empty
      expect(accounts['Data'][0]).to have_key('Account')
      expect(accounts['Data'][0]['Account']).to be_a(Hash)
      expect(accounts['Data'][0]['Account']).not_to be_empty
      expect(accounts['Data'][0]['Account']).to have_key('SchemeName')
      expect(accounts['Data'][0]['Account']['SchemeName']).not_to be_empty
      expect(accounts['Data'][0]['Account']).to have_key('Identification')
      expect(accounts['Data'][0]['Account']['Identification']).not_to be_empty
      expect(accounts['Data'][0]['Account']).to have_key('Name')
      expect(accounts['Data'][0]['Account']['Name']).not_to be_empty
      expect(accounts['Data'][0]['Account']).to have_key('Currency')
      expect(accounts['Data'][0]['Account']['Currency']).not_to be_empty
      expect(accounts['Data'][0]['Account']).to have_key('AccountType')
      expect(accounts['Data'][0]['Account']['AccountType']).not_to be_empty
      expect(accounts['Data'][0]['Account']).to have_key('AccountSubType')
      expect(accounts['Data'][0]['Account']['AccountSubType']).not_to be_empty
      expect(accounts['Data'][0]['Account']).to have_key('AccountNumber')
      expect(accounts['Data'][0]['Account']['AccountNumber']).not_to be_empty
      expect(accounts['Data'][0]['Account']).to have_key('Iban')
      expect(accounts['Data'][0]['Account']['Iban']).not_to be_empty
      expect(accounts['Data'][0]['Account']).to have_key('Bic')
      expect(accounts['Data'][0]['Account']['Bic']).not_to be_empty
      expect(accounts['Data'][0]['Account']).to have_key('BankId')
      expect(accounts['Data'][0]['Account']['BankId']).not_to be_empty
      expect(accounts['Data'][0]['Account']).to have_key('BankName')
      expect(accounts['Data'][0]['Account']['BankName']).not_to be_empty
      expect(accounts['Data'][0]['Account']).to have_key('BankCountry')
      expect(accounts['Data'][0]['Account']['BankCountry']).not_to be_empty
      expect(accounts['Data'][0]['Account']).to have_key('BankCountrySubDivision')
      expect(accounts['Data'][0]['Account']['BankCountrySubDivision']).not_to be_empty
      expect(accounts['Data'][0]['Account']).to have_key('BankAddress')
      expect(accounts['Data'][0]['Account']['BankAddress']).to be_a(Hash)
      expect(accounts['Data'][0]['Account']['BankAddress']).not_to be_empty
      expect(accounts['Data'][0]['Account']['BankAddress']).to have_key('AddressLine')
      expect(accounts['Data'][0]['Account']['BankAddress']['AddressLine']).not_to be_empty
      expect(accounts['Data'][0]['Account']).to have_key('BankAddress')
      expect(accounts['Data'][0]['Account']['BankAddress']).to be_a(Hash)
      expect(accounts['Data'][0]['Account']['BankAddress']).not_to be_empty
      expect(accounts['Data'][0]['Account']['BankAddress']).to have_key('AddressLine')
      expect(accounts['Data'][0]['Account']['BankAddress']['AddressLine']).not_to be_empty
      expect(accounts['Data'][0]['Account']).to have_key('BankAddress')
      expect(accounts['Data'][0]['Account']['BankAddress']).to be_a(Hash)
      expect(accounts['Data'][0]['Account']['BankAddress']).not_to be_empty
      expect(accounts['Data'][0]['Account']['BankAddress']).to have_key('AddressLine')
      expect(accounts['Data'][0]['Account']['BankAddress']['AddressLine']).not_to be_empty
      expect(accounts['Data'][0]['Account']).to have_key('BankAddress')
      expect(accounts['Data'][0]['Account']['BankAddress']).to be_a(Hash)
      expect(accounts['Data'][0]['Account']['BankAddress']).not_to be_empty
      expect(accounts['Data'][0]['Account']['BankAddress']).to have_key('AddressLine')
      expect(accounts['Data'][0]['Account']['BankAddress']['AddressLine']).not_to be_empty
      expect(accounts['Data'][0]['Account']).to have_key('BankAddress')
      expect(accounts['Data'][0]['Account']['BankAddress']).to be_a(Hash)
      expect(accounts['Data'][0]['Account']['BankAddress']).not_to be_empty
      expect(accounts['Data'][0]['Account']['BankAddress']).to have_key('AddressLine')
      expect(accounts['Data'][0]['Account']['BankAddress']['AddressLine']).not_to be_empty
      expect(accounts['Data'][0]['Account']).to have_key('BankAddress')
      expect(accounts['Data'][0]['Account']['BankAddress']).to be_a(Hash)
      expect(accounts['Data'][0]['Account']['BankAddress']).not_to be_empty
      expect(accounts['Data'][0]['Account']['BankAddress']).to have_key('AddressLine')
      expect(accounts['Data'][0]['Account']['BankAddress']['AddressLine']).not_to be_empty
      expect(accounts['Data'][0]['Account']).to have_key('BankAddress')
      expect(accounts['Data'][0]['Account']['BankAddress']).to be_a(Hash)
      expect(accounts['Data'][0]['Account']['BankAddress']).not_to be_empty
      expect(accounts['Data'][0]['Account']['BankAddress']).to have_key('AddressLine')
      expect(accounts['Data'][0]['Account']['BankAddress']['AddressLine']).not_to be_empty
      expect(accounts['Data'][0]['Account']).to have_key('BankAddress')
      expect(accounts['Data'][0]['Account']['BankAddress']).to be_a(Hash)
      expect(accounts['Data'][0]['Account']['BankAddress']).not_to be_empty
      expect(accounts['Data'][0]['Account']['BankAddress']).to have_key('AddressLine')
      expect(accounts['Data'][0]['Account']['BankAddress']['AddressLine']).not_to be_empty
      expect(accounts['Data'][0]['Account']).to have_key('BankAddress')
      expect(accounts['Data'][0]['Account']['BankAddress']).to be_a(Hash)
      expect(accounts['Data'][0]['Account']['BankAddress']).not_to be_empty
      expect(accounts['Data'][0]['Account']['BankAddress']).to have_key('AddressLine')
      expect(accounts['Data'][0]['Account']['BankAddress']['AddressLine']).not_to be_empty
      expect(accounts['Data'][0]['Account']).to have_key('BankAddress')
      expect(accounts['Data'][0]['Account']['BankAddress']).to be_a(Hash)
      expect(accounts['Data'][0]['Account']['BankAddress']).not_to be_empty
=end
    end
  end
end