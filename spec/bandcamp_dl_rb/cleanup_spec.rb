# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe BandcampDlRb::Downloader do
  describe '.cleanup_old_partial_downloads' do
    it 'removes bc* entries under the given base' do
      base = Dir.mktmpdir
      keep = File.join(base, 'keep')
      stale = File.join(base, 'bc123')
      FileUtils.mkdir_p(keep)
      FileUtils.mkdir_p(stale)

      described_class.cleanup_old_partial_downloads(base)

      expect(Dir.exist?(stale)).to be false
      expect(Dir.exist?(keep)).to be true
    ensure
      FileUtils.rm_rf(base)
    end

    it 'is a no-op for a missing base' do
      expect { described_class.cleanup_old_partial_downloads('/no/such/path') }.not_to raise_error
    end
  end
end