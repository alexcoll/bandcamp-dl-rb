# frozen_string_literal: true

require 'simplecov'

# The coverage floor describes the whole suite, so only enforce it on a full
# run. A scoped run -- `rspec spec/bandcamp_dl_rb/manpage_spec.rb`, which the
# manpage-parity CI job does -- never loads most of lib/, so the floor would
# measure how few files that one spec happens to require rather than how well
# the suite covers the code. ARGV holds the command line: no bare argument
# means no path was scoped to.
scoped_run = ARGV.any? { |arg| !arg.start_with?('-') }

SimpleCov.start do
  skip '/spec/'
  skip '/vendor/'
  unless scoped_run
    minimum_coverage 95
    maximum_coverage_drop 5
  end
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
