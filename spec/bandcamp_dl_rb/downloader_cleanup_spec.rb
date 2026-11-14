# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe BandcampDlRb::Downloader do
  describe '.cleanup_old_partial_downloads' do
    subject(:cleanup) { described_class.cleanup_old_partial_downloads(base) }

    let(:base) { Dir.mktmpdir }
    let(:keep) { File.join(base, 'keep') }
    let(:stale) { File.join(base, 'bc123') }
    let(:missing_base?) { false }

    before do
      next if missing_base?

      FileUtils.mkdir_p(keep)
      FileUtils.mkdir_p(stale)
    end

    after { FileUtils.rm_rf(base) }

    it 'removes stale bc* entries' do
      cleanup
      expect(Dir.exist?(stale)).to be false
    end

    it 'leaves non-bc entries alone' do
      cleanup
      expect(Dir.exist?(keep)).to be true
    end

    context 'when the base directory is missing' do
      let(:base) { '/no/such/path' }
      let(:missing_base?) { true }

      it 'does not raise' do
        expect { cleanup }.not_to raise_error
      end
    end
  end
end
