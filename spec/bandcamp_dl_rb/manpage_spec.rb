# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe 'man/bandcamp_dl_rb.1' do
  subject(:manpage) { source.gsub('\\', '') }

  let(:source) { File.read(File.expand_path('../../man/bandcamp_dl_rb.1', __dir__)) }

  let(:cli_help) { BandcampDlRb::CLI.parse_args([])[:parser].to_s }

  # Extract the long options actually defined by the CLI's OptionParser, so
  # this check cannot drift from the real option set.
  let(:cli_long_options) do
    cli_help.scan(/^\s*(?:-[A-Za-z], )?--([a-z][a-z0-9-]*)/).flatten.uniq.map { |name| "--#{name}" }
  end

  let(:options_section) { manpage[/\.SH OPTIONS(.*?)\.SH FORMATS/m, 1] }

  let(:manpage_option_flags) do
    options_section.scan(/--([a-z][a-z0-9-]*)/).flatten.uniq.map { |name| "--#{name}" }
  end

  describe 'the header' do
    it 'names the manual page' do
      expect(manpage).to include('.TH BANDCAMP_DL_RB 1')
    end

    it 'has a NAME section' do
      expect(manpage).to include('.SH NAME')
    end
  end

  describe 'the OPTIONS section' do
    %w[SYNOPSIS DESCRIPTION AUTHENTICATION OPTIONS FORMATS EXAMPLES FILES].each do |section|
      context "for .SH #{section}" do
        it 'is documented' do
          expect(manpage).to include(".SH #{section}")
        end
      end
    end

    context 'for .SH EXIT STATUS' do
      it 'is documented' do
        expect(manpage).to include('.SH EXIT STATUS')
      end
    end
  end

  describe 'option coverage' do
    it 'documents every CLI long option' do
      missing = cli_long_options.reject { |flag| manpage.include?(flag) }
      expect(missing).to be_empty, "manpage is missing #{missing.join(', ')}"
    end

    it 'documents no options the CLI lacks' do
      extras = manpage_option_flags - cli_long_options
      expect(extras).to be_empty, "manpage documents unknown options: #{extras.join(', ')}"
    end
  end

  describe 'packaging' do
    it 'ships in the built gem' do
      spec = Gem::Specification.load(File.expand_path('../../bandcamp-dl-rb.gemspec', __dir__))
      expect(spec.files).to include('man/bandcamp_dl_rb.1')
    end
  end
end
