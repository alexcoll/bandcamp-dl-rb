# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe 'man/bandcamp_dl_rb.1' do
  let(:source) { File.read(File.expand_path('../../man/bandcamp_dl_rb.1', __dir__)) }
  let(:manpage) { source.gsub('\\', '') }

  let(:cli_help) { BandcampDlRb::CLI.parse_args([])[:parser].to_s }

  # Extract the long options actually defined by the CLI's OptionParser, so
  # this check cannot drift from the real option set.
  let(:cli_long_options) do
    cli_help.scan(/^\s*(?:-[A-Za-z], )?--([a-z][a-z0-9-]*)/).flatten.uniq.map { |name| "--#{name}" }
  end

  let(:manpage_option_flags) do
    options_section = manpage[/\.SH OPTIONS(.*?)\.SH FORMATS/m, 1]
    options_section.scan(/--([a-z][a-z0-9-]*)/).flatten.uniq.map { |name| "--#{name}" }
  end

  it 'exists with a NAME section' do
    expect(manpage).to include('.TH BANDCAMP_DL_RB 1')
    expect(manpage).to include('.SH NAME')
  end

  it 'documents every CLI long option' do
    cli_long_options.each do |flag|
      expect(manpage).to include(flag), "manpage is missing #{flag}"
    end
  end

  it 'does not document options the CLI does not have' do
    extras = manpage_option_flags - cli_long_options
    expect(extras).to be_empty, "manpage documents unknown options: #{extras.join(', ')}"
  end

  it 'documents the required sections' do
    required = ['SYNOPSIS', 'DESCRIPTION', 'AUTHENTICATION', 'OPTIONS',
                'FORMATS', 'EXAMPLES', 'FILES', 'EXIT STATUS']
    required.each do |section|
      expect(manpage).to include(".SH #{section}")
    end
  end

  it 'is included in the built gem' do
    spec = Gem::Specification.load('bandcamp-dl-rb.gemspec')
    expect(spec.files).to include('man/bandcamp_dl_rb.1')
  end
end
