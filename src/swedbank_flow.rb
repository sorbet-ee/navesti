require_relative 'navesti'

Navesti.define :swedbank_openbanking_ais do
  format :json

  source :create_consent_parameters do
    map :tpp_redirect_preferred, to: :tpp_redirect_preferred
    map :frequency_per_day, to: :frequency_per_day
    map :recurring_indicator, to: :recurring_indicator
    map :iban, to: :iban
  end

  workflow do


    BASE_URL = "https://psd2.api.swedbank.com:443/sandbox/v5"
    BIC = "SANDEE2X"
    APP_ID = "l7276866044e8c45d2856ae3f64fdd3d74"


    step "Create Consent" do |data|
      Navesti::ExternalServices.post(
        "#{BASE_URL}/consents?bic=#{BIC}&app-id=#{APP_ID}",
        data[:payload],
        data[:headers],
        :json
      )
    end


  end
end