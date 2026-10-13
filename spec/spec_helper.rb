# frozen_string_literal: true

require 'simplecov'
SimpleCov.start do
  skip '/spec/'
  skip '/vendor/'
  minimum_coverage 95
  maximum_coverage_drop 5
end

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'bandcamp_dl_rb'
require 'tmpdir'
require 'fileutils'
require 'stringio'
require 'net/http'
require 'tempfile'

Dir[File.expand_path('support/**/*.rb', __dir__)].each { |file| require file }

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.syntax = :expect
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.syntax = :expect
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.disable_monkey_patching!
  config.filter_run_when_matching :focus
  config.example_status_persistence_file_path = 'tmp/rspec_examples.txt'
  config.order = :random
  Kernel.srand config.seed
end
