# navesti

**navesti** is a powerful, declarative DSL for data mapping and workflow orchestration, inspired by the fluidity of the Estonian river Navesti. Built for modern financial systems, navesti allows you to define complex integrations in a clear, human‑readable way while leveraging the full power of Ruby.

---

## Table of Contents

- [Overview](#overview)
- [Key Features](#key-features)
- [Design Philosophy](#design-philosophy)
- [Installation](#installation)
- [Usage](#usage)
  - [Defining a Workflow](#defining-a-workflow)
  - [Running a Workflow](#running-a-workflow)
- [Networking and Data Formats](#networking-and-data-formats)
- [Integration Examples](#integration-examples)
- [Testing](#testing)
- [Deployment](#deployment)
- [Contributing](#contributing)
- [License](#license)
- [Contact](#contact)

---

## Overview

In today’s fast‑paced financial world, integrating disparate systems—from Open Banking APIs to cutting‑edge ledger solutions like TigerBeetle—can be a daunting challenge. **navesti** simplifies these complexities by offering a declarative, Ruby‑based DSL that abstracts data mapping and workflow logic into a minimal set of intuitive commands.

Whether you’re building payment initiation flows, managing account information services, or orchestrating multi‑step financial transactions, navesti provides a consistent and expressive interface to define and execute these processes.

---

## Key Features

- **Declarative Field Mapping:**  
  Define how internal fields map to external API formats using a concise `map` syntax with built‑in transformation support.

- **Workflow Orchestration:**  
  Build multi‑step workflows with `step` and `check` constructs that enable sequential processing and validations, ensuring data integrity throughout the flow.

- **Conditional Branching:**  
  Use the `branch` construct to handle complex decision trees based on data values.

- **Global Error Handling:**  
  Define a centralized error handler with `on_error` to capture and log exceptions during workflow execution.

- **Pluggable Networking:**  
  Interact with external services using Faraday. Easily switch between JSON and XML data formats by specifying the format (e.g., `format :json` or `format :xml`).

- **Modular & Extensible:**  
  Packaged as a standalone gem, navesti is designed to be integrated across projects in the Sorbet ecosystem, promoting reuse and consistency.

---

## Design Philosophy

**navesti** is built on a few core principles:

- **Minimalism:**  
  With a small vocabulary (`map`, `step`, `check`, `branch`, `on_error`, and `format`), the DSL remains accessible and easy to learn while still being powerful enough to express complex logic.

- **Declarativeness:**  
  Express the *what* of your integration—data mappings and workflow logic—without worrying about the underlying *how*.

- **Seamless Ruby Integration:**  
  Leveraging Ruby’s metaprogramming, navesti allows you to embed custom blocks, lambdas, or method references for advanced logic, keeping the DSL clean and concise.

- **Flow and Fluidity:**  
  Inspired by the Navesti river, the DSL enables data to flow smoothly between systems, making integration elegant and maintainable.

---

## Installation

Add navesti to your Gemfile:

```ruby
gem 'navesti', '~> 1.0'

Then run:

bundle install

Or install it directly:

gem install navesti

Usage
Defining a Workflow

Create a workflow definition file (for example, wise_flow_example.rb):

# wise_flow_example.rb
# Example Workflow for Wise Open Banking PISP Flow using navesti DSL

navesti.define :wise_openbanking_pisp do
  # Set the expected data format; choose :json or :xml.
  format :json

  # Define the source type and field mappings.
  source :payment_initiation do
    map :transaction_id,        to: :transactionId
    map :amount,                to: :instructedAmount, transform: ->(amt){ amt.to_f }
    map :currency,              to: :currency, transform: :upcase
    map :payer_account,         to: :fromAccount
    map :beneficiary_account,   to: :toAccount
  end

  # Define the workflow steps.
  workflow do
    check "Amount must be > 0" do |data|
      data[:amount] > 0
    end

    step "Round amount" do |data|
      data.merge(amount: data[:amount].round(2))
    end

    step "Initiate Payment" do |data|
      ExternalServices.initiate_payment(data, :json)
    end

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

    on_error do |error, context|
      ExternalServices.log_error(error, context)
      raise error
    end
  end
end

Running a Workflow

Create an execution script (for example, run_wise_flow_example.rb):

# run_wise_flow_example.rb
#
# This script demonstrates running the Wise Open Banking PISP workflow defined
# in wise_flow_example.rb using navesti. It prints out informative messages during
# the execution to help you understand the process.

require_relative 'wise_flow_example'

puts "Starting Wise Open Banking PISP workflow using navesti..."

# Sample input data for the workflow.
input_data = {
  transaction_id: "txn_001",
  amount: "100.0",
  currency: "gbp",
  payer_account: "A123",
  beneficiary_account: "B456",
  payment_status: "pending"  # This triggers the 'pending' branch.
}

begin
  puts "Input Data:"
  puts input_data.inspect

  result = navesti.run(:wise_openbanking_pisp, input_data)

  puts "Workflow completed successfully!"
  puts "Final Output:"
  puts result.inspect
rescue => e
  puts "An error occurred during workflow execution:"
  puts e.message
end

Networking and Data Formats

navesti’s networking layer is powered by Faraday and supports both JSON and XML:

    JSON:
    Requests are encoded as JSON, and responses are parsed into Ruby hashes using Faraday’s middleware.

    XML:
    Requests are URL-encoded, and responses are parsed using Nokogiri, providing an XML document for further processing.

Specify the desired format in your workflow using the format method (e.g., format :json or format :xml), and navesti will configure the connection accordingly.
Integration Examples

navesti is versatile and designed for modern financial integrations:

    Open Banking (AIS/PIS):
    Easily map internal payment requests to external API formats.
    Ledger Systems:
    Transform data to work with systems like TigerBeetle.
    Custom Integrations:
    Use the DSL to build workflows that interact with any third-party API, regardless of whether the backend is JSON or XML based.

For a complete integration example, see the wise_flow_example.rb file included in the repository.
Testing

We use RSpec for testing workflows defined with navesti. To run the test suite:

    Prepare your test database:

rails db:test:prepare

Run the tests:

    bundle exec rspec

Tests cover:

    Field mapping accuracy.
    Workflow step execution.
    Branching logic.
    Global error handling.

Deployment

Before deploying, ensure your environment is properly configured:

    Environment Variables:
    Ensure variables such as DATABASE_URL, API keys, and other secrets are set.

    Database Setup:
    Run database creation and migrations:

rails db:create
rails db:migrate RAILS_ENV=production
rails db:seed

### Asset Precompilation:

Precompile assets:

rails assets:precompile RAILS_ENV=production

### Deployment Using Kamal:

If using Kamal, build and deploy with:

    kamal build
    kamal deploy
    kamal run rails db:migrate


## Contributing

Contributions are welcome! Please follow these guidelines:

    Fork the repository and create a feature branch.
    Write tests for your changes.
    Follow the project's coding style.
    Submit a pull request with a detailed explanation of your changes.

For more details, see CONTRIBUTING.md.

## License

This project is licensed under the MIT License.

## Contact

For questions, feedback, or support, please contact the Sorbet Payments team at info@sorbet.ee.com or visit our GitHub repository.

Sorbet is committed to empowering developers to build seamless, maintainable, and scalable financial integrations. Dive in, explore, and help us shape the future of financial data orchestration!


