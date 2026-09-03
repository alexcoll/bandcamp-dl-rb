require_relative 'spec_helper'

require 'zip'

RSpec.describe BandcampToPlex do
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

  describe '.load_cookies_from_file' do
    it 'parses a Netscape cookies.txt file and returns the identity cookie value' do
      content = <<~TXT
        # Netscape HTTP Cookie File
        .bandcamp.com	TRUE	/	TRUE	2000000000	identity	abc123XYZ
        .bandcamp.com	TRUE	/	FALSE	2000000000	other	ignoreme
      TXT
      file = Tempfile.new('cookies')
      file.write(content)
      file.close

      expect(described_class.load_cookies_from_file(file.path)).to eq('abc123XYZ')
    ensure
      file.unlink
    end

    it 'returns nil when there is no identity cookie' do
      content = <<~TXT
        .bandcamp.com	TRUE	/	TRUE	2000000000	session	x
      TXT
      file = Tempfile.new('cookies')
      file.write(content)
      file.close

      expect(described_class.load_cookies_from_file(file.path)).to be_nil
    ensure
      file.unlink
    end

    it 'returns nil when the file is empty' do
      file = Tempfile.new('cookies')
      file.close

      expect(described_class.load_cookies_from_file(file.path)).to be_nil
    ensure
      file.unlink
    end

    it 'ignores comment lines and blank lines' do
      content = <<~TXT
        # comment line

        .bandcamp.com	TRUE	/	TRUE	2000000000	identity	val42
      TXT
      file = Tempfile.new('cookies')
      file.write(content)
      file.close

      expect(described_class.load_cookies_from_file(file.path)).to eq('val42')
    ensure
      file.unlink
    end
  end

  describe BandcampToPlex::BandcampClient do
    let(:identity) { 'test-identity-value' }
    subject(:client) { described_class.new(identity) }

    it 'exposes the identity' do
      expect(client.identity).to eq(identity)
    end

    describe '#get_pagedata' do
      let(:ok_response) do
        Class.new do
          def body
            blob = { 'collection_count' => 1, 'fan_data' => { 'fan_id' => 4242 } }
            html = '<div id="pagedata" data-blob="%s"></div>' % CGI.escapeHTML(JSON.generate(blob))
            html
          end

          def is_a?(_klass)
            true
          end
        end.new
      end

      before do
        allow(client).to receive(:get).and_return(ok_response)
      end

      it 'parses the data-blob json from the pagedata div' do
        expect(client.get_pagedata('https://bandcamp.com/testuser'))
          .to eq('collection_count' => 1, 'fan_data' => { 'fan_id' => 4242 })
      end
    end

    describe '#get_pagedata with a non-success response' do
      it 'returns nil' do
        bad = Class.new { def is_a?(_k); false; end }.new
        allow(client).to receive(:get).and_return(bad)

        expect(client.get_pagedata('https://bandcamp.com/testuser')).to be_nil
      end
    end

    describe '.get_download_url' do
      let(:pagedata) do
        {
          'download_items' => [
            {
              'downloads' => {
                'flac'    => { 'url' => 'https://bcbits/flac.zip' },
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
        result = BandcampToPlex.get_download_url(client, 'https://bandcamp.com/foo', 'flac')
        expect(result).to eq(url: 'https://bcbits/flac.zip', format: 'flac')
      end

      it 'falls back to flac when requesting a missing format' do
        result = BandcampToPlex.get_download_url(client, 'https://bandcamp.com/foo', 'wav')
        expect(result).to eq(url: 'https://bcbits/flac.zip', format: 'flac')
      end

      it 'returns nil when no format is available' do
        pagedata['download_items'][0]['downloads'] = {}
        result = BandcampToPlex.get_download_url(client, 'https://bandcamp.com/foo', 'flac')
        expect(result).to be_nil
      end
    end

    describe '#get_collection' do
      let(:pagedata) do
        {
          'collection_count' => 2,
          'fan_data' => { 'fan_id' => 123 },
          'item_cache' => {
            'collection' => {
              'a100' => {
                'sale_item_type' => 'a',
                'sale_item_id' => 100,
                'band_name' => 'Artist One',
                'item_title' => 'Album One',
                'tralbum_type' => 'a',
                'featured_track' => {},
                'purchased' => '01 Jan 2025 00:00:00 GMT'
              }
            },
            'hidden' => {}
          },
          'collection_data' => {
            'item_count' => 2,
            'last_token' => nil,
            'redownload_urls' => { 'a100' => 'https://bandcamp.com/redownload/1' }
          },
          'hidden_data' => { 'item_count' => 0, 'last_token' => nil }
        }
      end

      before do
        allow(client).to receive(:get_pagedata).and_return(pagedata)
        allow(client).to receive(:fetch_collection_items).and_return(
          'items' => [{
            'sale_item_type' => 'a',
            'sale_item_id' => 200,
            'band_name' => 'Artist Two',
            'item_title' => 'Album Two',
            'tralbum_type' => 'a'
          }],
          'redownload_urls' => { 'a200' => 'https://bandcamp.com/redownload/2' },
          'last_token' => nil
        )
      end

      it 'returns items with redownload urls' do
        items = client.get_collection('testuser')
        expect(items.keys).to include('a100')
        expect(items['a100']['redownload_url']).to eq('https://bandcamp.com/redownload/1')
      end

      it 'returns empty hash when pagedata is missing' do
        allow(client).to receive(:get_pagedata).and_return(nil)
        expect(client.get_collection('nouser')).to eq({})
      end
    end
  end

  describe 'BandcampClient#get' do
    it 'sets the Cookie header from the identity' do
      client = BandcampToPlex::BandcampClient.new('cookieval')
      req = nil
      allow(Net::HTTP).to receive(:start) do |_host, _port, **_opts, &block|
        http = double('http')
        allow(http).to receive(:request) do |r|
          req = r
          instance_double(Net::HTTPSuccess, body: '{}')
        end
        block.call(http)
      end

      client.get('https://bandcamp.com/api/test')
      expect(req['Cookie']).to eq('identity=cookieval')
    end
  end

  # --- download_album integration tests (mocked HTTP/io) ---

  describe '.download_album' do
    let(:client) { BandcampToPlex::BandcampClient.new('ident') }
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
      client = BandcampToPlex::BandcampClient.new('ident')

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

  # --- CLI ---

  describe '.parse_args' do
    it 'parses library and username' do
      argv = ['--library', '/mnt/music', 'myuser']
      options = described_class.parse_args(argv)
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
  end

  describe '.run' do
    it 'returns exit code 1 when username and library are missing' do
      err = StringIO.new
      out = StringIO.new
      code = described_class.run([], out: out, err: err)
      expect(code).to eq(1)
    end
  end
end
