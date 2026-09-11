# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe 'man/bandcamp_dl_rb.1' do
  let(:source) { File.read(File.expand_path('../../man/bandcamp_dl_rb.1', __dir__)) }
  let(:manpage) { source.gsub('\\', '') }

  let(:documented_flags) do
    %w[
      --library --format --browser --cookie-file --url --items --filter
      --include-hidden --since --until --force --dry-run --verbose --help --version
    ].freeze
  end

  it 'exists with a NAME section' do
    expect(manpage).to include('.TH BANDCAMP_DL_RB 1')
    expect(manpage).to include('.SH NAME')
  end

  it 'documents every CLI long option' do
    documented_flags.each do |flag|
      expect(manpage).to include(flag), "manpage is missing #{flag}"
    end
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
