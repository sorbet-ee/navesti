.PHONY: test test_token clean

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
test_token: $(TEST_RESULTS_DIR)
	@echo "Running Token Tests..."
	$(RSPEC) $(SPEC_DIR)/token_spec.rb
	@echo "Token Tests completed."

# Run all tests in sequence
test_all: clean test_token
	@echo "All tests completed."

# Default target
test: test_all
