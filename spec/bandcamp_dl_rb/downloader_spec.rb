# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe BandcampDlRb::Downloader do
  let(:client) { BandcampDlRb::Client.new('ident') }

  describe '.get_download_url' do
    let(:pagedata) do
      {
        'download_items' => [
          {
            'downloads' => {
              'flac' => { 'url' => 'https://bcbits/flac.zip' },
              'mp3-320' => { 'url' => 'https://bcbits/mp3.zip' }
            }
          }
        ]
      }
    end

    before do
      allow(client).to receive(:get_pagedata).and_return(pagedata)
    end

    it 'returns the requested format url' do
      result = described_class.get_download_url(client, 'https://bandcamp.com/foo', 'flac')
      expect(result).to eq(url: 'https://bcbits/flac.zip', format: 'flac')
    end

    it 'falls back to flac when requesting a missing format' do
      result = described_class.get_download_url(client, 'https://bandcamp.com/foo', 'wav')
      expect(result).to eq(url: 'https://bcbits/flac.zip', format: 'flac')
    end

    it 'returns nil when no format is available' do
      pagedata['download_items'][0]['downloads'] = {}
      result = described_class.get_download_url(client, 'https://bandcamp.com/foo', 'flac')
      expect(result).to be_nil
    end

    it 'returns nil when pagedata has no download items' do
      allow(client).to receive(:get_pagedata).and_return('download_items' => [])
      expect(described_class.get_download_url(client, 'https://bandcamp.com/foo', 'flac')).to be_nil
    end
  end

  describe '.download_album' do
    let(:item) do
      {
        'sale_item_type' => 'a',
        'sale_item_id' => 7,
        'band_name' => 'Radiohead',
        'item_title' => 'Kid A',
        'tralbum_type' => 'a',
        'redownload_url' => 'https://bandcamp.com/redownload/7'
      }
    end

    around do |example|
      Dir.mktmpdir do |dir|
        @dest = dir
        example.run
      end
    end

    it 'returns :skipped when the album already exists and not force' do
      FileUtils.mkdir_p(File.join(@dest, 'Radiohead', 'Kid A'))
      FileUtils.touch(File.join(@dest, 'Radiohead', 'Kid A', '01.flac'))

      expect(described_class.download_album(client, item, @dest, 'flac')).to eq(:skipped)
    end

    it 'copies a single-track download into Artist/Album structure' do
      allow(described_class).to receive(:get_download_url) do |_c, _url, format|
        { url: 'https://bcbits/track.flac', format: format }
      end

      allow(described_class).to receive(:download_file) do |_c, _url, dest|
        File.write(dest, 'flacdata')
        true
      end

      expect(described_class.download_album(client, item, @dest, 'flac')).to eq(:downloaded)

      extracted = File.join(@dest, 'Radiohead', 'Kid A')
      expect(Dir.glob(File.join(extracted, '*.flac'))).not_to be_empty
    end

    it 'returns :unavailable when no format is available' do
      allow(described_class).to receive(:get_download_url).and_return(nil)
      expect(described_class.download_album(client, item, @dest, 'flac')).to eq(:unavailable)
    end

    it 'returns :failed when the download fails' do
      allow(described_class).to receive(:get_download_url) do |_c, _url, format|
        { url: 'https://bcbits/kida.zip', format: format }
      end
      allow(described_class).to receive(:download_file).and_return(false)

      expect(described_class.download_album(client, item, @dest, 'flac')).to eq(:failed)
    end
  end

  describe '.download_file' do
    it 'follows redirects and downloads the response body to the destination' do
      success = double('success')
      allow(success).to receive(:is_a?).with(Net::HTTPRedirection).and_return(false)
      allow(success).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
      allow(success).to receive(:body).and_return('FLA-CONTENT')

      redirect = double('redirect')
      allow(redirect).to receive(:is_a?).with(Net::HTTPRedirection).and_return(true)
      allow(redirect).to receive(:is_a?).with(Net::HTTPSuccess).and_return(false)
      allow(redirect).to receive(:[]).with('location').and_return('https://final.example/file.flac')

      allow(Net::HTTP).to receive(:start) do |host, _port, **_opts, &block|
        http = double('http')
        allow(http).to receive(:request) do
          host == 'final.example' ? success : redirect
        end
        block.call(http)
      end

      Dir.mktmpdir do |dir|
        dest = File.join(dir, 'out.flac')
        result = described_class.download_file(client, 'https://bcbits/start', dest, max_retries: 3)
        expect(result).to eq(true)
        expect(File.read(dest)).to eq('FLA-CONTENT')
      end
    end
  end
end
