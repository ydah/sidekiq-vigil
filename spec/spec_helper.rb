# frozen_string_literal: true

require "simplecov"

SimpleCov.start do
  enable_coverage :branch
  add_filter "/spec/"
  minimum_coverage 85 unless ENV["VIGIL_E2E"] == "1"
end

require "redis-client"
require "sidekiq_vigil"
require "webmock/rspec" unless ENV["VIGIL_E2E"] == "1"

Dir[File.join(__dir__, "support/**/*.rb")].each { |file| require file }

RSpec.configure do |config|
  config.example_status_persistence_file_path = ".rspec_status"
  config.disable_monkey_patching!
  config.order = :random
  config.filter_run_excluding(e2e: true) unless ENV["VIGIL_E2E"] == "1"

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.before do
    SidekiqVigil.reset!
  end
end
