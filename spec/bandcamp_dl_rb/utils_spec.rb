# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe BandcampDlRb::Utils do
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

  describe '.human_size' do
    it 'formats zero as 0 B' do
      expect(described_class.human_size(0)).to eq('0 B')
    end

    it 'formats nil as 0 B' do
      expect(described_class.human_size(nil)).to eq('0 B')
    end

    it 'formats bytes' do
      expect(described_class.human_size(512)).to eq('512.0 B')
    end

    it 'formats kilobytes' do
      expect(described_class.human_size(800_000)).to eq('781.2 KB')
    end

    it 'formats megabytes' do
      expect(described_class.human_size(1_200_000)).to eq('1.1 MB')
    end

    it 'formats gigabytes' do
      expect(described_class.human_size(1_073_741_824)).to eq('1.0 GB')
    end
  end
end
