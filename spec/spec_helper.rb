# frozen_string_literal: true

require "navesti"
require "json"

Dir[File.join(__dir__, "support", "**", "*.rb")].each { |f| require f }

RSpec.configure do |config|
  config.expect_with(:rspec) { |c| c.syntax = :expect }
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed

  # Live sandbox tests hit LHV and are opt-in only (CLAUDE.md / docs/12).
  # They never run in the normal suite or in CI.
  config.filter_run_excluding(:live) unless ENV["LHV_LIVE"] == "1"
end
