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
              'flac' => { 'url' => 'https://bcbits/flac.zip', 'size_mb' => '1.2GB' },
              'mp3-320' => { 'url' => 'https://bcbits/mp3.zip', 'size_mb' => '250MB' }
            }
          }
        ]
      }
    end

    before do
      allow(client).to receive(:get_pagedata).and_return(pagedata)
    end

    it 'returns the requested format url and size' do
      result = described_class.get_download_url(client, 'https://bandcamp.com/foo', 'flac')
      expect(result).to eq(url: 'https://bcbits/flac.zip', format: 'flac', size_mb: '1.2GB')
    end

    it 'falls back to flac when requesting a missing format' do
      result = described_class.get_download_url(client, 'https://bandcamp.com/foo', 'wav')
      expect(result).to eq(url: 'https://bcbits/flac.zip', format: 'flac', size_mb: '1.2GB')
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

  describe '.size_bytes' do
    it 'parses megabytes' do
      expect(described_class.size_bytes(size_mb: '495.5MB')).to eq((495.5 * 1024 * 1024).to_i)
    end

    it 'parses gigabytes' do
      expect(described_class.size_bytes(size_mb: '2GB')).to eq(2 * 1024 * 1024 * 1024)
    end

    it 'parses gigabytes with a decimal' do
      expect(described_class.size_bytes(size_mb: '1.2GB')).to eq((1.2 * 1024 * 1024 * 1024).to_i)
    end

    it 'returns nil when the size is missing' do
      expect(described_class.size_bytes({})).to be_nil
    end

    it 'returns nil when the size is unparseable' do
      expect(described_class.size_bytes(size_mb: 'nope')).to be_nil
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

  describe '.download_size' do
    def response_double(redirects:, success:, partial:, headers: {})
      response = double('response')
      { Net::HTTPRedirection => redirects, Net::HTTPSuccess => success,
        Net::HTTPPartialContent => partial }.each do |klass, value|
        allow(response).to receive(:is_a?).with(klass).and_return(value)
      end
      allow(response).to receive(:[]).and_return(nil)
      headers.each { |key, value| allow(response).to receive(:[]).with(key).and_return(value) }
      response
    end

    def stub_http(&request_handler)
      allow(Net::HTTP).to receive(:start) do |host, _port, **_opts, &block|
        http = double('http')
        allow(http).to receive(:request) { request_handler.call(host) }
        block.call(http)
      end
    end

    it 'reads the total from a partial content response' do
      stub_http do
        response_double(redirects: false, success: true, partial: true,
                        headers: { 'content-range' => 'bytes 0-0/12345' })
      end
      expect(described_class.download_size(client, 'https://bcbits/file.flac')).to eq(12_345)
    end

    it 'falls back to content-length when the server ignores the range' do
      stub_http do
        response_double(redirects: false, success: true, partial: false,
                        headers: { 'content-length' => '2048' })
      end
      expect(described_class.download_size(client, 'https://bcbits/file.flac')).to eq(2048)
    end

    it 'follows redirects before reading the size' do
      stub_http do |host|
        if host == 'final.example'
          response_double(redirects: false, success: true, partial: true,
                          headers: { 'content-range' => 'bytes 0-0/99' })
        else
          response_double(redirects: true, success: false, partial: false,
                          headers: { 'location' => 'https://final.example/file.flac' })
        end
      end
      expect(described_class.download_size(client, 'https://bcbits/start')).to eq(99)
    end

    it 'returns nil when no size header is present' do
      stub_http { response_double(redirects: false, success: true, partial: true) }
      expect(described_class.download_size(client, 'https://bcbits/file.flac')).to be_nil
    end

    it 'returns nil when the request fails' do
      allow(Net::HTTP).to receive(:start).and_raise(StandardError, 'boom')
      expect(described_class.download_size(client, 'https://bcbits/file.flac')).to be_nil
    end
  end
end
