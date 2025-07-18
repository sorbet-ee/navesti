require_relative 'navesti'
require_relative 'lhv_flow'


puts "Starting the LHV Open Banking AIS workflow..."
begin
    #
    # :show_account
    #
    input_data = {
        base_url: 'https://api.sandbox.lhv.eu/psd2/v1',
        psu_id: 'Liis-MariMnnik',
        psu_corporate_id: 'EE47101010033',
        authentication_method_id: 'BIO',
        client_id: 'PSDEE-LHVTEST-820163',
        psu_ip_address: '1.2.3.4',
        tpp_redirect_uri: 'http://lhv-redirect',
        iban: 'EE717700771001735865',
        tpp_redirect_preferred: 'true',
        ssl_options: {
            client_cert: OpenSSL::X509::Certificate.new(File.read(File.expand_path('config/client-cert.pem'))),
            client_key: OpenSSL::PKey::RSA.new(File.read(File.expand_path('config/client-key.pem'))),
            ca_file: File.expand_path('config/ca-chain.pem'),
            verify: false,
            version: 'TLSv1_2'
        }
    }
    show_account_response = Navesti.run(:show_account, input_data)
    pp "Show Account Response:"
    pp show_account_response
rescue => e
    puts "An error occurred during workflow execution:"
    puts e.message
end
        