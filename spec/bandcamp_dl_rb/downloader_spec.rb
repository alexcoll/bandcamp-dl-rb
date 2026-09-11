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
            },
            'art_id' => 12_345
          }
        ]
      }
    end

    before do
      allow(client).to receive(:get_pagedata).and_return(pagedata)
    end

    it 'returns the requested format url and size' do
      result = described_class.get_download_url(client, 'https://bandcamp.com/foo', 'flac')
      expect(result).to eq(url: 'https://bcbits/flac.zip', format: 'flac', size_mb: '1.2GB',
                           art_id: 12_345)
    end

    it 'falls back to flac when requesting a missing format' do
      result = described_class.get_download_url(client, 'https://bandcamp.com/foo', 'wav')
      expect(result).to eq(url: 'https://bcbits/flac.zip', format: 'flac', size_mb: '1.2GB',
                           art_id: 12_345)
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

    it 'uses pre-fetched pagedata to avoid a redundant HTTP request' do
      expect(client).not_to receive(:get_pagedata)
      result = described_class.get_download_url(client, 'https://bandcamp.com/foo', 'flac',
                                                pagedata: pagedata)
      expect(result).to eq(url: 'https://bcbits/flac.zip', format: 'flac', size_mb: '1.2GB',
                           art_id: 12_345)
    end

    it 'includes art_id from pagedata top level when not in download_items' do
      pagedata['download_items'][0].delete('art_id')
      pagedata['art_id'] = 99_999
      result = described_class.get_download_url(client, 'https://bandcamp.com/foo', 'flac')
      expect(result[:art_id]).to eq(99_999)
    end

    it 'omits art_id when not present in pagedata' do
      pagedata['download_items'][0].delete('art_id')
      result = described_class.get_download_url(client, 'https://bandcamp.com/foo', 'flac')
      expect(result).not_to have_key(:art_id)
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

  describe '.album_dir_for' do
    around do |example|
      Dir.mktmpdir do |dir|
        @dest = dir
        example.run
      end
    end

    it 'builds Artist/Album under the destination dir' do
      item = { 'band_name' => 'Radiohead', 'item_title' => 'Kid A' }
      expect(described_class.album_dir_for(item, @dest))
        .to eq(File.join(@dest, 'Radiohead', 'Kid A'))
    end

    it 'keeps a dotdot band name inside the destination dir' do
      item = { 'band_name' => '..', 'item_title' => 'Kid A' }
      expect(described_class.album_dir_for(item, @dest))
        .to start_with(@dest + File::SEPARATOR)
    end

    it 'keeps a dotdot item title inside the destination dir' do
      item = { 'band_name' => 'Radiohead', 'item_title' => '..' }
      expect(described_class.album_dir_for(item, @dest))
        .to start_with(@dest + File::SEPARATOR)
    end

    it 'keeps a dotdot band name and title together inside the destination dir' do
      item = { 'band_name' => '. .', 'item_title' => '..' }
      expect(described_class.album_dir_for(item, @dest))
        .to start_with(@dest + File::SEPARATOR)
    end

    it 'falls back to placeholder names and warns when the path would escape' do
      item = { 'band_name' => 'Radiohead', 'item_title' => 'Kid A' }
      allow(described_class).to receive(:contained_in?).and_return(false)
      expect(BandcampDlRb).to receive(:log_verbose).with(/escapes library root/)

      result = described_class.album_dir_for(item, @dest)
      expect(result).to eq(File.join(@dest, 'Unknown Artist', 'Unknown Album'))
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
      pagedata = {
        'download_items' => [
          { 'downloads' => { 'flac' => { 'url' => 'https://bcbits/track.flac', 'size_mb' => '10MB' } } }
        ]
      }
      allow(client).to receive(:get_pagedata).and_return(pagedata)

      allow(described_class).to receive(:download_file) do |_c, _url, dest|
        File.write(dest, 'flacdata')
        true
      end

      expect(described_class.download_album(client, item, @dest, 'flac')).to eq(:downloaded)

      extracted = File.join(@dest, 'Radiohead', 'Kid A')
      expect(Dir.glob(File.join(extracted, '*.flac'))).not_to be_empty
    end

    it 'returns :unavailable when no format is available' do
      allow(client).to receive(:get_pagedata).and_return('download_items' => [])
      expect(described_class.download_album(client, item, @dest, 'flac')).to eq(:unavailable)
    end

    it 'returns :failed when the download fails' do
      pagedata = {
        'download_items' => [
          { 'downloads' => { 'flac' => { 'url' => 'https://bcbits/kida.zip', 'size_mb' => '10MB' } } }
        ]
      }
      allow(client).to receive(:get_pagedata).and_return(pagedata)
      allow(described_class).to receive(:download_file).and_return(false)

      expect(described_class.download_album(client, item, @dest, 'flac')).to eq(:failed)
    end

    it 'saves cover.jpg from CDN when art_id is present' do
      pagedata = {
        'download_items' => [
          {
            'downloads' => { 'flac' => { 'url' => 'https://bcbits/track.flac', 'size_mb' => '1MB' } },
            'art_id' => 12_345
          }
        ]
      }
      allow(client).to receive(:get_pagedata).and_return(pagedata)

      allow(described_class).to receive(:download_file) do |_c, url, dest, **_kw|
        if url.include?('f4.bcbits.com/img')
          File.binwrite(dest, 'coverdata')
        else
          File.write(dest, 'flacdata')
        end
        true
      end

      expect(described_class.download_album(client, item, @dest, 'flac')).to eq(:downloaded)

      cover = File.join(@dest, 'Radiohead', 'Kid A', 'cover.jpg')
      expect(File.exist?(cover)).to be true
      expect(File.read(cover)).to eq('coverdata')
    end

    it 'writes album.json when pagedata contains metadata' do
      pagedata = {
        'album_release_date' => '1 Oct 2000',
        'download_items' => [
          {
            'downloads' => { 'flac' => { 'url' => 'https://bcbits/track.flac', 'size_mb' => '1MB' } },
            'trackinfo' => [
              { 'title' => 'Everything In Its Right Place', 'duration' => 251, 'track_num' => 1 }
            ]
          }
        ]
      }
      allow(client).to receive(:get_pagedata).and_return(pagedata)

      allow(described_class).to receive(:download_file) do |_c, _url, dest|
        File.write(dest, 'flacdata')
        true
      end

      expect(described_class.download_album(client, item, @dest, 'flac')).to eq(:downloaded)

      info_path = File.join(@dest, 'Radiohead', 'Kid A', 'album.json')
      expect(File.exist?(info_path)).to be true
      info = JSON.parse(File.read(info_path))
      expect(info['release_date']).to eq('1 Oct 2000')
      expect(info['tracklist'].first['title']).to eq('Everything In Its Right Place')
    end

    it 'does not rewrite cover.jpg if the CDN download already saved it' do
      album_dir = File.join(@dest, 'Radiohead', 'Kid A')
      FileUtils.mkdir_p(album_dir)
      File.write(File.join(album_dir, 'cover.jpg'), 'existing-cover')

      pagedata = {
        'download_items' => [
          {
            'downloads' => { 'flac' => { 'url' => 'https://bcbits/track.flac', 'size_mb' => '1MB' } },
            'art_id' => 12_345
          }
        ]
      }
      allow(client).to receive(:get_pagedata).and_return(pagedata)

      allow(described_class).to receive(:download_file) do |_c, url, dest, **_kw|
        if url.include?('bcbits.com')
          File.write(dest, 'flacdata')
          true
        else
          # Cover should not be re-downloaded since file exists
          false
        end
      end

      described_class.download_album(client, item, @dest, 'flac')
      expect(File.read(File.join(album_dir, 'cover.jpg'))).to eq('existing-cover')
    end
  end

  describe '.extract_album_metadata' do
    it 'maps trackinfo to a tracklist with durations and track numbers' do
      pagedata = {
        'album_release_date' => '1 Oct 2000',
        'label' => 'XL Recordings',
        'download_items' => [
          {
            'artist' => 'Radiohead',
            'title' => 'Kid A',
            'trackinfo' => [
              { 'title' => 'Everything In Its Right Place', 'duration' => 251, 'track_num' => 1 },
              { 'title' => 'Kid A', 'duration' => 285, 'track_num' => 2 }
            ],
            'credits' => 'Written by Radiohead'
          }
        ]
      }

      info = described_class.extract_album_metadata(pagedata)
      expect(info['artist']).to eq('Radiohead')
      expect(info['title']).to eq('Kid A')
      expect(info['release_date']).to eq('1 Oct 2000')
      expect(info['label']).to eq('XL Recordings')
      expect(info['credits']).to eq('Written by Radiohead')
      expect(info['tracklist']).to eq([
                                        { 'title' => 'Everything In Its Right Place', 'duration' => 251,
                                          'track_num' => 1 },
                                        { 'title' => 'Kid A', 'duration' => 285, 'track_num' => 2 }
                                      ])
    end

    it 'falls back to pagedata-level trackinfo when download_items has none' do
      pagedata = {
        'trackinfo' => [{ 'title' => 'Windowlicker', 'duration' => 377 }],
        'download_items' => [{ 'downloads' => {} }]
      }
      info = described_class.extract_album_metadata(pagedata)
      expect(info['tracklist']).to eq([{ 'title' => 'Windowlicker', 'duration' => 377 }])
    end

    it 'omits absent optional fields' do
      info = described_class.extract_album_metadata('download_items' => [{}])
      expect(info).to eq({})
    end

    it 'returns an empty hash when pagedata is nil' do
      expect(described_class.extract_album_metadata(nil)).to eq({})
    end
  end

  describe '.save_cover' do
    around do |example|
      Dir.mktmpdir do |dir|
        @dest = dir
        example.run
      end
    end

    it 'downloads the CDN cover when art_id is present' do
      allow(described_class).to receive(:download_file) do |_c, url, dest, **_kw|
        expect(url).to eq('https://f4.bcbits.com/img/a12345_10.jpg')
        File.binwrite(dest, 'coverdata')
        true
      end

      described_class.save_cover(client, { art_id: 12_345 }, @dest)
      expect(File.read(File.join(@dest, 'cover.jpg'))).to eq('coverdata')
    end

    it 'does nothing when art_id is absent' do
      expect(described_class).not_to receive(:download_file)
      described_class.save_cover(client, {}, @dest)
      expect(Dir.glob(File.join(@dest, '*'))).to be_empty
    end

    it 'removes a partial file when the download fails' do
      allow(described_class).to receive(:download_file) do |_c, _url, dest, **_kw|
        File.binwrite(dest, 'partial')
        false
      end

      described_class.save_cover(client, { art_id: 1 }, @dest)
      expect(File).not_to exist(File.join(@dest, 'cover.jpg'))
    end

    it 'does not overwrite an existing cover.jpg' do
      File.write(File.join(@dest, 'cover.jpg'), 'existing')
      allow(described_class).to receive(:download_file).and_return(true)
      described_class.save_cover(client, { art_id: 1 }, @dest)
      expect(File.read(File.join(@dest, 'cover.jpg'))).to eq('existing')
    end
  end

  describe '.extract_zip' do
    around do |example|
      Dir.mktmpdir do |dir|
        @dest = dir
        example.run
      end
    end

    it 'extracts audio and cover image entries, skipping dotfiles' do
      zip_path = File.join(@dest, 'album.zip')
      Zip::File.open(zip_path, create: true) do |zip|
        zip.get_output_stream('Radiohead - Kid A/01 Track.flac') { |f| f.write('audio') }
        zip.get_output_stream('Radiohead - Kid A/cover.jpg') { |f| f.write('zipcover') }
        zip.get_output_stream('Radiohead - Kid A/.hidden') { |f| f.write('skip') }
        zip.get_output_stream('Radiohead - Kid A/__MACOSX/._01') { |f| f.write('skip') }
      end

      result = described_class.extract_zip(zip_path, @dest)
      expect(result).to be true
      expect(File.read(File.join(@dest, '01 Track.flac'))).to eq('audio')
      expect(File.read(File.join(@dest, 'cover.jpg'))).to eq('zipcover')
      expect(File).not_to exist(File.join(@dest, '.hidden'))
      expect(File).not_to exist(File.join(@dest, '._01'))
    end

    it 'skips a zip cover when cover.jpg already exists' do
      File.write(File.join(@dest, 'cover.jpg'), 'cdn-cover')
      zip_path = File.join(@dest, 'album.zip')
      Zip::File.open(zip_path, create: true) do |zip|
        zip.get_output_stream('cover.jpg') { |f| f.write('zipcover') }
        zip.get_output_stream('01.flac') { |f| f.write('audio') }
      end

      described_class.extract_zip(zip_path, @dest)
      expect(File.read(File.join(@dest, 'cover.jpg'))).to eq('cdn-cover')
      expect(File.exist?(File.join(@dest, '01.flac'))).to be true
    end

    it 'returns false when the zip is unreadable' do
      bad_zip = File.join(@dest, 'bad.zip')
      File.write(bad_zip, 'not a zip')
      expect(described_class.extract_zip(bad_zip, @dest)).to be false
    end
  end

  describe '.download_file' do
    def redirect_double(location)
      redirect = double('redirect')
      allow(redirect).to receive(:is_a?).with(Net::HTTPRedirection).and_return(true)
      allow(redirect).to receive(:is_a?).with(Net::HTTPSuccess).and_return(false)
      allow(redirect).to receive(:[]).with('location').and_return(location)
      redirect
    end

    def success_double(body = 'FLA-CONTENT')
      success = double('success')
      allow(success).to receive(:is_a?).with(Net::HTTPRedirection).and_return(false)
      allow(success).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
      allow(success).to receive(:body).and_return(body)
      success
    end

    def capture_requests(url, first_response, second_response)
      requests = {}
      allow(Net::HTTP).to receive(:start) do |host, _port, **_opts, &block|
        http = double('http')
        allow(http).to receive(:request) do |r|
          requests[host] = r['Cookie']
          requests.size == 1 ? first_response : second_response
        end
        block.call(http)
      end

      Dir.mktmpdir do |dir|
        dest = File.join(dir, 'out.flac')
        result = described_class.download_file(client, url, dest, max_retries: 3)
        [result, requests]
      end
    end

    it 'follows redirects and downloads the response body to the destination' do
      success = success_double
      redirect = redirect_double('https://final.example/file.flac')

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

    it 'keeps the cookie when redirecting to bcbits.com hosts' do
      result, requests = capture_requests(
        'https://bandcamp.com/start',
        redirect_double('https://d1.bcbits.com/final.zip'),
        success_double
      )
      expect(result).to eq(true)
      expect(requests).to eq(
        'bandcamp.com' => 'identity=ident',
        'd1.bcbits.com' => 'identity=ident'
      )
    end

    it 'drops the cookie when a redirect points off-allowlist' do
      result, requests = capture_requests(
        'https://bandcamp.com/start',
        redirect_double('https://example.com/file.flac'),
        success_double
      )
      expect(result).to eq(true)
      expect(requests).to eq(
        'bandcamp.com' => 'identity=ident',
        'example.com' => nil
      )
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

    it 'keeps the cookie when a size-check redirect stays on bcbits.com' do
      requests = {}
      allow(Net::HTTP).to receive(:start) do |host, _port, **_opts, &block|
        http = double('http')
        allow(http).to receive(:request) do |r|
          requests[host] = r['Cookie']
          if host == 'd1.bcbits.com'
            response_double(redirects: false, success: true, partial: true,
                            headers: { 'content-range' => 'bytes 0-0/99' })
          else
            response_double(redirects: true, success: false, partial: false,
                            headers: { 'location' => 'https://d1.bcbits.com/file.flac' })
          end
        end
        block.call(http)
      end

      expect(described_class.download_size(client, 'https://bcbits.com/start')).to eq(99)
      expect(requests).to eq(
        'bcbits.com' => 'identity=ident',
        'd1.bcbits.com' => 'identity=ident'
      )
    end

    it 'drops the cookie when a size-check redirect points off-allowlist' do
      requests = {}
      allow(Net::HTTP).to receive(:start) do |host, _port, **_opts, &block|
        http = double('http')
        allow(http).to receive(:request) do |r|
          requests[host] = r['Cookie']
          if host == 'example.com'
            response_double(redirects: false, success: true, partial: true,
                            headers: { 'content-range' => 'bytes 0-0/99' })
          else
            response_double(redirects: true, success: false, partial: false,
                            headers: { 'location' => 'https://example.com/file.flac' })
          end
        end
        block.call(http)
      end

      expect(described_class.download_size(client, 'https://bcbits.com/start')).to eq(99)
      expect(requests).to eq(
        'bcbits.com' => 'identity=ident',
        'example.com' => nil
      )
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
