# wise_flow_example.rb
#
# Example Workflow for Wise Open Banking PISP Flow
#
# This example demonstrates how to define a workflow using the Sorbet Flow DSL.
# It maps internal fields to the external API's expected fields, performs data validations,
# processes steps such as data transformations and API calls, and handles branching logic
# based on the payment status.
#
# To run this workflow:
#   result = SorbetFlow.run(:wise_openbanking_pisp, {
#     transaction_id: "txn_001",
#     amount: "100.0",
#     currency: "gbp",
#     payer_account: "A123",
#     beneficiary_account: "B456",
#     payment_status: "pending"
#   })
#   puts result

require 'navesti'

SorbetFlow.define :wise_openbanking_pisp do
  # Set the expected response format to JSON.
  format :json

  # Define the source type and field mappings.
  source :payment_initiation do
    map :transaction_id, to: :transactionId
    map :amount,         to: :instructedAmount, transform: ->(amt){ amt.to_f }
    map :currency,       to: :currency, transform: :upcase
    map :payer_account,  to: :fromAccount
    map :beneficiary_account, to: :toAccount
  end

  # Define the workflow steps.
  workflow do
    # Validate that the amount is greater than 0.
    check "Amount must be > 0" do |data|
      data[:amount] > 0
    end

    # Round the amount to two decimal places.
    step "Round amount" do |data|
      data.merge(amount: data[:amount].round(2))
    end

    # Initiate the payment by calling the external API.
    step "Initiate Payment" do |data|
      ExternalServices.initiate_payment(data, :json)
    end

    # Define branching logic based on payment status.
    branch :payment_status do
      when 'pending' do
        step "Retry Payment" do |data|
          sleep 5  # Simple retry delay.
          ExternalServices.initiate_payment(data, :json)
        end
      end

      when 'failed' do
        step "Notify Failure" do |data|
          ExternalServices.notify("Payment #{data[:transaction_id]} failed")
          data
        end
      end
    end

    # Global error handler for the workflow.
    on_error do |error, context|
      ExternalServices.log_error(error, context)
      raise error
    end
  end
end
