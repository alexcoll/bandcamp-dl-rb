# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe BandcampToPlex::Utils do
  describe '.sanitize_path' do
    it 'replaces forward slashes with dashes' do
      expect(described_class.sanitize_path('AC/DC')).to eq('AC-DC')
    end

    it 'replaces backslashes with dashes' do
      expect(described_class.sanitize_path('Foo\\Bar')).to eq('Foo-Bar')
    end

    it 'replaces forbidden filename characters' do
      expect(described_class.sanitize_path('A:B*C?D"E<F>G|H')).to eq('A-B-C-D-E-F-G-H')
    end

    it 'strips leading and trailing whitespace' do
      expect(described_class.sanitize_path('  Artist Name  ')).to eq('Artist Name')
    end

    it 'leaves normal names unchanged' do
      expect(described_class.sanitize_path('Radiohead')).to eq('Radiohead')
    end

    it 'handles empty string' do
      expect(described_class.sanitize_path('')).to eq('')
    end
  end
end