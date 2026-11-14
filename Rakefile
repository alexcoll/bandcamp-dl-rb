# frozen_string_literal: true

require 'rspec/core/rake_task'

$LOAD_PATH.unshift File.expand_path('lib', __dir__)
require 'bandcamp_dl_rb'

RSpec::Core::RakeTask.new(:spec)

namespace :completions do
  desc 'Regenerate shell completion scripts from the CLI OptionParser'
  task :generate, [:output_dir] do |_task, args|
    require 'bandcamp_dl_rb'
    output_dir = args[:output_dir] || ENV.fetch('OUTPUT_DIR', nil) || ENV.fetch('DIR', nil) || 'completions'
    BandcampDlRb::CompletionsGenerator.generate(output_dir: output_dir)
    puts "Generated shell completions in #{output_dir}"
  end
end

task default: :spec
