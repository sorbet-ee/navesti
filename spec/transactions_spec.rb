require 'spec_helper'
require 'json'
require 'logger'

# Initialize logger with timestamp in filename
timestamp = Time.now.strftime('%Y%m%d_%H%M%S')
LOG_FILE = File.expand_path("../../test_results/transactions_tests_#{timestamp}.log", __FILE__)
FileUtils.mkdir_p(File.dirname(LOG_FILE))

# Clear the log file at start
File.write(LOG_FILE, "Starting Transactions Test Suite: #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}\n\n")

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
  let(:transaction_consent_code) do
    transaction_code_path = File.expand_path('../test_results/transaction_consent_code.json', __dir__)
    JSON.parse(File.read(transaction_code_path))['code']
  end
  let(:new_access_token) do
    new_access_token_path = File.expand_path('../test_results/new_access_token.json', __dir__)
    JSON.parse(File.read(new_access_token_path))['access_token']
  end
  let(:accounts) do
    accounts_path = File.expand_path('../test_results/accounts.json', __dir__)
    JSON.parse(File.read(accounts_path))
  end
  let(:domestic_payment_consent) do
    domestic_payment_consent_path = File.expand_path('../test_results/domestic_payment_consent.json', __dir__)
    JSON.parse(File.read(domestic_payment_consent_path))
  end
  let(:domestic_payment_consent_id) do
    domestic_payment_consent_path = File.expand_path('../test_results/domestic_payment_consent.json', __dir__)
    JSON.parse(File.read(domestic_payment_consent_path))['Data']['ConsentId']
  end

  describe "#create_a_domestic_payment_consent" do
    it "returns a valid domestic payment consent" do
      LOGGER.info("↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓")
      LOGGER.info("Creating domestic payment consent...")
      puts "↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓"
      puts "Creating domestic payment consent..."
      
      domestic_payment_consent = client.create_a_domestic_payment_consent(access_token: access_token)
      LOGGER.info("Domestic payment consent:\n#{JSON.pretty_generate(domestic_payment_consent)}")
      puts "Domestic payment consent:\n#{JSON.pretty_generate(domestic_payment_consent)}"
      LOGGER.info("↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑")
      puts "↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑"

      expect(domestic_payment_consent).to be_a(Hash)
      expect(domestic_payment_consent).not_to be_empty
      expect(domestic_payment_consent).to have_key('Data')
      expect(domestic_payment_consent['Data']).to have_key('Status')
      expect(domestic_payment_consent['Data']['Status']).to eq('AwaitingAuthorisation')
      expect(domestic_payment_consent['Data']).to have_key('ConsentId')
      expect(domestic_payment_consent['Data']['ConsentId']).not_to be_empty

      # Save the domestic payment consent to a file
      domestic_payment_consent_file = File.expand_path('../test_results/domestic_payment_consent.json', __dir__)
      File.write(domestic_payment_consent_file, JSON.pretty_generate(domestic_payment_consent))

      LOGGER.info("Domestic payment consent saved to file: #{domestic_payment_consent_file}")
      LOGGER.info("Domestic payment consent establishment completed successfully")
    end
  end

  describe "#retrieve_a_domestic_payment_consent" do
    it "returns a valid domestic payment consent" do
      LOGGER.info("↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓")
      LOGGER.info("Retrieving domestic payment consent...")
      puts "↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓"
      puts "Retrieving domestic payment consent..."
      
      domestic_payment_consent = client.retrieve_a_domestic_payment_consent(access_token: access_token, consent_id: domestic_payment_consent_id)
      LOGGER.info("Domestic payment consent:\n#{JSON.pretty_generate(domestic_payment_consent)}")
      puts "Domestic payment consent:\n#{JSON.pretty_generate(domestic_payment_consent)}"
      LOGGER.info("↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑")
      puts "↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑"

      expect(domestic_payment_consent).to be_a(Hash)
      expect(domestic_payment_consent).not_to be_empty
      expect(domestic_payment_consent).to have_key('Data')
      expect(domestic_payment_consent['Data']).to have_key('Status')
      expect(domestic_payment_consent['Data']['Status']).to eq('AwaitingAuthorisation')
      expect(domestic_payment_consent['Data']).to have_key('ConsentId')
      expect(domestic_payment_consent['Data']['ConsentId']).not_to be_empty
    end
  end

  describe "#get_consent_from_the_user" do
    it "returns a valid consent from the user" do
      LOGGER.info("↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓")
      LOGGER.info("Getting consent from the user...")
      puts "↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓"
      puts "Getting consent from the user..."
      
      auth_data = client.get_domestic_payment_consent_from_the_user(access_token: access_token, consent_id: domestic_payment_consent_id)
      LOGGER.info("Checking consent status after authorization")
      puts "Checking consent status after authorization"
      consent_status = client.retrieve_a_domestic_payment_consent(access_token: access_token, consent_id: domestic_payment_consent_id)
      LOGGER.info("Consent status: #{consent_status['Data']['Status']}")
      puts "Consent status: #{consent_status['Data']['Status']}"

      expect(consent_status['Data']['Status']).to eq('Authorised')

      LOGGER.info("Code: #{auth_data[:code]}")
      puts "Code: #{auth_data[:code]}"
      expect(auth_data[:code]).not_to be_empty
      expect(auth_data[:code]).to be_a(String)

      # Save the code to a file
      code_file = File.expand_path('../test_results/transaction_consent_code.json', __dir__)
      File.write(code_file, JSON.pretty_generate(auth_data))

      LOGGER.info("Code saved to file: #{code_file}")
      LOGGER.info("Authorization completed successfully")
      LOGGER.info("↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑")
      puts "↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑"
    end
  end

  describe "#exchange_code_for_access_token" do
    it "returns a valid access token" do
      LOGGER.info("↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓")
      LOGGER.info("Exchanging code for access token...")
      puts "↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓"
      puts "Exchanging code for access token..."
      access_token = client.exchange_code_for_access_token(code: transaction_consent_code)
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

  describe "#get_funds_confirmation_for_a_domestic_payment_consent" do
    it "returns a valid funds confirmation for a domestic payment consent" do
      LOGGER.info("↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓")
      LOGGER.info("Getting funds confirmation for a domestic payment consent...")
      puts "↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓"
      puts "Getting funds confirmation for a domestic payment consent..."
      
      funds_confirmation = client.get_funds_confirmation_for_a_domestic_payment_consent(access_token: new_access_token, consent_id: domestic_payment_consent_id)
      LOGGER.info("Funds confirmation:\n#{JSON.pretty_generate(funds_confirmation)}")
      puts "Funds confirmation:\n#{JSON.pretty_generate(funds_confirmation)}"
      LOGGER.info("↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑")
      puts "↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑"

      expect(funds_confirmation).to be_a(Hash)
      expect(funds_confirmation).not_to be_empty
      expect(funds_confirmation).to have_key('Data')

      # Save the funds confirmation to a file
      funds_confirmation_file = File.expand_path('../test_results/funds_confirmation.json', __dir__)
      File.write(funds_confirmation_file, JSON.pretty_generate(funds_confirmation))

      LOGGER.info("Funds confirmation saved to file: #{funds_confirmation_file}")
      LOGGER.info("Funds confirmation completed successfully")
    end
  end

  describe "#create_a_domestic_payment" do
    it "returns a valid domestic payment" do
      LOGGER.info("↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓")
      LOGGER.info("Creating a domestic payment...")
      puts "↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓"
      puts "Creating a domestic payment..."
      
      domestic_payment = client.create_a_domestic_payment(access_token: new_access_token, consent_id: domestic_payment_consent_id)
      LOGGER.info("Domestic payment:\n#{JSON.pretty_generate(domestic_payment)}")
      puts "Domestic payment:\n#{JSON.pretty_generate(domestic_payment)}"
      LOGGER.info("↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑")
      puts "↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑"

      # Save the domestic payment to a file
      domestic_payment_file = File.expand_path('../test_results/domestic_payment.json', __dir__)
      File.write(domestic_payment_file, JSON.pretty_generate(domestic_payment))

      LOGGER.info("Domestic payment saved to file: #{domestic_payment_file}")
      LOGGER.info("Domestic payment establishment completed successfully")
    end
  end
=begin
# DOES NOT WORK CAUSE WE DONT HAVE A DOMESTIC PAYMENT ID BECAUSE WE DONT HAVE BALANCE
  describe "#retrieve_a_domestic_payment" do
    it "returns a valid domestic payment" do
      LOGGER.info("↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓")
      LOGGER.info("Retrieving a domestic payment...")
      puts "↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓"
      puts "Retrieving a domestic payment..."
      
      domestic_payment = client.retrieve_a_domestic_payment(access_token: new_access_token, domestic_payment_id: domestic_payment_id)
      LOGGER.info("Domestic payment:\n#{JSON.pretty_generate(domestic_payment)}")
      puts "Domestic payment:\n#{JSON.pretty_generate(domestic_payment)}"
      LOGGER.info("↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑")
      puts "↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑"

      expect(domestic_payment).to be_a(Hash)
      expect(domestic_payment).not_to be_empty
      expect(domestic_payment).to have_key('Data')
      expect(domestic_payment['Data']).to have_key('Status')
    end
  end 
=end
end