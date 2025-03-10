# run_wise_flow_example.rb
#
# This script demonstrates how to run the Wise Open Banking PISP workflow
# defined in the Sorbet Flow DSL. It prints informative messages before,
# during, and after the execution, so that developers can easily see what’s
# happening.
#
# To run this example, simply execute:
#   ruby run_wise_flow_example.rb

require_relative 'wise_flow_example'  # Loads the workflow definition from wise_flow_example.rb

puts "Starting the Wise Open Banking PISP workflow..."

# Sample input data for the workflow
input_data = {
  transaction_id: "txn_001",
  amount: "100.0",
  currency: "gbp",
  payer_account: "A123",
  beneficiary_account: "B456",
  payment_status: "pending"  # This will trigger the branch for 'pending'
}

begin
  puts "Running workflow with input:"
  puts input_data.inspect

  # Execute the workflow using the SorbetFlow DSL
  result = SorbetFlow.run(:wise_openbanking_pisp, input_data)

  puts "Workflow completed successfully!"
  puts "Final Result:"
  puts result.inspect
rescue => e
  puts "An error occurred during workflow execution:"
  puts e.message
end
