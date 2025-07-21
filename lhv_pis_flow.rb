require_relative 'navesti'
require_relative 'lhv_flow'

puts "Starting the LHV Open Banking PIS workflow..."
begin
    #
    # :sepa_payment
    #
    input_data = {
        base_url: 'https://api.sandbox.lhv.eu/psd2/v1',
        psu_id: 'Liis-MariMnnik',
        psu_corporate_id: 'EE47101010033',
        authentication_method_id: 'BIO',
        sca_authentication_data: '306955503400',
        client_id: 'PSDEE-LHVTEST-820163',
        psu_ip_address: '1.2.3.4',
        tpp_redirect_uri: 'http://lhv-redirect',
        tpp_redirect_preferred: 'true',
        debtor_iban: 'EE717700771001735865',
        creditor_iban: 'EE717700771001735865',
        creditor_name: 'John Doe',
        remittance_info: 'Test payment',
        currency: 'EUR',
        amount: '25.55',
        ssl_options: {
            client_cert: OpenSSL::X509::Certificate.new(File.read(File.expand_path('config/client-cert.pem'))),
            client_key: OpenSSL::PKey::RSA.new(File.read(File.expand_path('config/client-key.pem'))),
            ca_file: File.expand_path('config/ca-chain.pem'),
            verify: false,
            version: 'TLSv1_2'
        }
    }
    sepa_payment_response = Navesti.run(:sepa_payment, input_data)
    pp "Sepa Payment Response:"
    pp sepa_payment_response
rescue => e
    puts "An error occurred during workflow execution:"
    puts e.message
end
