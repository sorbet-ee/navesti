.PHONY: test test_accounts clean

# Default test directory
SPEC_DIR = spec
TEST_RESULTS_DIR = test_results

# RSpec command with common options
RSPEC = bundle exec rspec --format documentation

# Create test results directory if it doesn't exist
$(TEST_RESULTS_DIR):
	mkdir -p $(TEST_RESULTS_DIR)

# Clean test results
clean:
	rm -rf $(TEST_RESULTS_DIR)/*

# Run Token Tests only
test_accounts: $(TEST_RESULTS_DIR)
	@echo "Running Accounts Tests..."
	$(RSPEC) $(SPEC_DIR)/accounts_spec.rb
	@echo "Accounts Tests completed."

# Run Transactions Tests only
test_transactions: $(TEST_RESULTS_DIR)
	@echo "Running Transactions Tests..."
	$(RSPEC) $(SPEC_DIR)/transactions_spec.rb
	@echo "Transactions Tests completed."

# Run all tests in sequence
test_all: clean test_token
	@echo "All tests completed."

# Default target
test: test_all
