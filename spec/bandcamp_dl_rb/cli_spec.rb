# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe BandcampDlRb::CLI do
  describe '.parse_args' do
    it 'parses library and username' do
      options = described_class.parse_args(['--library', '/mnt/music', 'myuser'])
      expect(options[:library]).to eq('/mnt/music')
      expect(options[:username]).to eq('myuser')
    end

    it 'defaults format to flac' do
      options = described_class.parse_args(['--library', '/x', 'u'])
      expect(options[:format]).to eq('flac')
    end

    it 'accepts a custom format' do
      options = described_class.parse_args(['--library', '/x', '--format', 'wav', 'u'])
      expect(options[:format]).to eq('wav')
    end

    it 'parses include-hidden flag' do
      options = described_class.parse_args(['--library', '/x', '--include-hidden', 'u'])
      expect(options[:include_hidden]).to eq(true)
    end

    it 'parses since/until dates' do
      options = described_class.parse_args(['--library', '/x', '--since', '2024-01-01', 'u'])
      expect(options[:since]).to eq(Date.new(2024, 1, 1))
    end

    it 'parses the browser option' do
      options = described_class.parse_args(['--library', '/x', '--browser', 'chrome', 'u'])
      expect(options[:browser]).to eq('chrome')
    end

    it 'accepts safari as a browser option' do
      options = described_class.parse_args(['--library', '/x', '--browser', 'safari', 'u'])
      expect(options[:browser]).to eq('safari')
    end

    it 'defaults browser to auto' do
      options = described_class.parse_args(['--library', '/x', 'u'])
      expect(options[:browser]).to eq('auto')
    end
  end

  describe '.run' do
    it 'returns exit code 1 when username and library are missing' do
      err = StringIO.new
      out = StringIO.new
      code = described_class.run([], out: out, err: err)
      expect(code).to eq(1)
    end
  end

  describe '#print_dry_run' do
    it 'prints each item with its size and the total size' do
      cli = described_class.new(out: StringIO.new, err: StringIO.new)
      items = {
        'a1' => { 'band_name' => 'Radiohead', 'item_title' => 'Kid A',
                  'redownload_url' => 'https://bandcamp.com/redownload/1' },
        'a2' => { 'band_name' => 'Radiohead', 'item_title' => 'Amnesiac',
                  'redownload_url' => 'https://bandcamp.com/redownload/2' }
      }
      allow(cli).to receive(:download_size_for).and_return(1_200_000, 800_000)

      expect { cli.send(:print_dry_run, double('client'), items, 'flac') }.to output(
        <<~OUT
          \n--- Dry Run ---
            Radiohead - Kid A (1.1 MB)
            Radiohead - Amnesiac (781.2 KB)

          Total: 2 items, 1.9 MB would be downloaded
        OUT
      ).to_stderr
    end

    it 'marks unknown sizes and sums only known ones' do
      cli = described_class.new(out: StringIO.new, err: StringIO.new)
      items = {
        'a1' => { 'band_name' => 'Artist', 'item_title' => 'Album',
                  'redownload_url' => 'https://bandcamp.com/redownload/1' },
        'a2' => { 'band_name' => 'Artist', 'item_title' => 'Mystery',
                  'redownload_url' => 'https://bandcamp.com/redownload/2' }
      }
      allow(cli).to receive(:download_size_for).and_return(1_200_000, nil)

      expect { cli.send(:print_dry_run, double('client'), items, 'flac') }.to output(
        <<~OUT
          \n--- Dry Run ---
            Artist - Album (1.1 MB)
            Artist - Mystery (unknown size)

          Total: 2 items, 1.1 MB (+1 unknown) would be downloaded
        OUT
      ).to_stderr
    end
  end
end
