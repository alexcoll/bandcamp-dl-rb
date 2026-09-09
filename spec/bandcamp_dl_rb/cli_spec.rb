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

    it 'parses a single --url' do
      options = described_class.parse_args([
                                             '--library', '/x', '--url', 'https://radiohead.bandcamp.com/album/in-rainbows'
                                           ])
      expect(options[:urls]).to eq(['https://radiohead.bandcamp.com/album/in-rainbows'])
      expect(options[:username]).to be_nil
    end

    it 'parses multiple --url flags' do
      options = described_class.parse_args([
                                             '--library', '/x',
                                             '--url', 'https://radiohead.bandcamp.com/album/in-rainbows',
                                             '--url', 'https://radiohead.bandcamp.com/album/ok-computer'
                                           ])
      expect(options[:urls]).to eq([
                                     'https://radiohead.bandcamp.com/album/in-rainbows',
                                     'https://radiohead.bandcamp.com/album/ok-computer'
                                   ])
    end

    it 'parses --items with comma-separated IDs' do
      options = described_class.parse_args(['--library', '/x', '--items', 'a100,t200', 'myuser'])
      expect(options[:items]).to eq('a100,t200')
      expect(options[:username]).to eq('myuser')
    end

    it 'still picks up a positional username in URL mode' do
      args = [
        '--library', '/x',
        '--url', 'https://radiohead.bandcamp.com/album/in-rainbows',
        'testuser'
      ]
      options = described_class.parse_args(args)
      expect(options[:username]).to eq('testuser')
    end

    it 'defaults urls to empty array and items to nil' do
      options = described_class.parse_args(['--library', '/x', 'u'])
      expect(options[:urls]).to eq([])
      expect(options[:items]).to be_nil
    end
  end

  describe '.run' do
    it 'returns exit code 1 when username and library are missing' do
      err = StringIO.new
      out = StringIO.new
      code = described_class.run([], out: out, err: err)
      expect(code).to eq(1)
    end

    it 'returns exit code 1 when library is missing' do
      err = StringIO.new
      out = StringIO.new
      code = described_class.run(['myuser'], out: out, err: err)
      expect(code).to eq(1)
    end

    it 'returns exit code 1 when --items is used without username' do
      err = StringIO.new
      out = StringIO.new
      code = described_class.run(['--library', '/x', '--items', 'a100'], out: out, err: err)
      expect(code).to eq(1)
    end
  end

  describe 'integration' do
    around do |example|
      Dir.mktmpdir do |dir|
        @library = dir
        example.run
      end
    end

    before do
      allow(BandcampDlRb::CookieExtractor).to receive(:get_identity_cookie).and_return('test-identity')
    end

    def success_response(body)
      Class.new do
        define_method(:body) { body }

        def is_a?(_klass)
          true
        end
      end.new
    end

    def stub_http(&router)
      allow(Net::HTTP).to receive(:start) do |_host, _port, **_opts, &block|
        http = double('http')
        allow(http).to receive(:request) { |req| router.call(req) }
        block.call(http)
      end
    end

    def capture_stderr
      prev = $stderr
      io = StringIO.new
      $stderr = io
      yield
      io.string
    ensure
      $stderr = prev
    end

    def run_cli(argv)
      err = StringIO.new
      stderr = capture_stderr do
        @exit_code = described_class.run(argv, out: StringIO.new, err: err)
      end
      @err_string = stderr
    end

    describe 'URL mode end to end' do
      let(:album_url) { 'https://radiohead.bandcamp.com/album/in-rainbows' }
      let(:tralbum_html) do
        tralbum = { 'artist' => 'Radiohead', 'current' => { 'title' => 'In Rainbows' },
                    'id' => 2_162_872_411, 'item_type' => 'album' }
        "<div data-tralbum='#{CGI.escapeHTML(JSON.generate(tralbum))}'></div>"
      end
      let(:collection_html) do
        blob = {
          'collection_count' => 1,
          'fan_data' => { 'fan_id' => 123 },
          'item_cache' => {
            'collection' => {
              'a2162872411' => {
                'sale_item_type' => 'a', 'sale_item_id' => 2_162_872_411,
                'band_name' => 'Radiohead', 'item_title' => 'In Rainbows', 'tralbum_type' => 'a'
              }
            },
            'hidden' => {}
          },
          'collection_data' => {
            'item_count' => 1, 'last_token' => nil,
            'redownload_urls' => {
              'a2162872411' => 'https://bandcamp.com/download/album?id=2162872411'
            }
          },
          'hidden_data' => { 'item_count' => 0, 'last_token' => nil }
        }
        %(<div id="pagedata" data-blob="#{CGI.escapeHTML(JSON.generate(blob))}"></div>)
      end

      before do
        stub_http do |req|
          if req.uri.to_s.include?('radiohead.bandcamp.com/album/in-rainbows')
            success_response(tralbum_html)
          elsif req.uri.to_s.include?('bandcamp.com/testuser')
            success_response(collection_html)
          else
            raise "Unexpected request: #{req.uri}"
          end
        end
      end

      it 'downloads a single album from a URL through the full run' do
        downloaded = nil
        allow(BandcampDlRb::Downloader).to receive(:download_album) do |_client, item, _lib, _fmt, **_kw|
          downloaded = item
          :downloaded
        end

        run_cli(['--library', @library, '--url', album_url, 'testuser'])

        expect(@exit_code).to eq(0)
        expect(@err_string).to include('Found 1 downloadable item(s).')
        expect(@err_string).to include('Downloaded:  1')
        expect(downloaded['band_name']).to eq('Radiohead')
        expect(downloaded['item_title']).to eq('In Rainbows')
        expect(downloaded['sale_item_id']).to eq(2_162_872_411)
        expect(downloaded['redownload_url']).to eq('https://bandcamp.com/download/album?id=2162872411')

        state_file = File.join(@library, '.bandcamp-sync.json')
        expect(File).to exist(state_file)
        expect(JSON.parse(File.read(state_file))['item_ids']).to eq(['a2162872411'])
      end

      it 'exits with code 1 when the album is not in the collection' do
        allow(BandcampDlRb::Downloader).to receive(:download_album)

        tralbum = { 'artist' => 'Somebody', 'current' => { 'title' => 'Not Owned' },
                    'id' => 999, 'item_type' => 'album' }
        not_owned_html = "<div data-tralbum='#{CGI.escapeHTML(JSON.generate(tralbum))}'></div>"
        stub_http do |req|
          if req.uri.to_s.include?('somebody.bandcamp.com')
            success_response(not_owned_html)
          elsif req.uri.to_s.include?('bandcamp.com/testuser')
            success_response(collection_html)
          else
            raise "Unexpected request: #{req.uri}"
          end
        end

        run_cli(['--library', @library, '--url', 'https://somebody.bandcamp.com/album/not-owned', 'testuser'])

        expect(@exit_code).to eq(1)
        expect(@err_string).to include('Not found in collection or no download available')
        expect(@err_string).to include('No downloadable items found.')
      end
    end

    describe 'items mode end to end' do
      let(:collection_html) do
        blob = {
          'collection_count' => 3,
          'fan_data' => { 'fan_id' => 123 },
          'item_cache' => {
            'collection' => {
              'a100' => {
                'sale_item_type' => 'a', 'sale_item_id' => 100,
                'band_name' => 'Radiohead', 'item_title' => 'Kid A', 'tralbum_type' => 'a'
              },
              'a200' => {
                'sale_item_type' => 'a', 'sale_item_id' => 200,
                'band_name' => 'Radiohead', 'item_title' => 'Amnesiac', 'tralbum_type' => 'a'
              },
              't300' => {
                'sale_item_type' => 't', 'sale_item_id' => 300,
                'band_name' => 'Aphex Twin', 'item_title' => 'Windowlicker', 'tralbum_type' => 't'
              }
            },
            'hidden' => {}
          },
          'collection_data' => {
            'item_count' => 3, 'last_token' => nil,
            'redownload_urls' => {
              'a100' => 'https://bandcamp.com/download/album?id=100',
              'a200' => 'https://bandcamp.com/download/album?id=200',
              't300' => 'https://bandcamp.com/download/track?id=300'
            }
          },
          'hidden_data' => { 'item_count' => 0, 'last_token' => nil }
        }
        %(<div id="pagedata" data-blob="#{CGI.escapeHTML(JSON.generate(blob))}"></div>)
      end

      before do
        stub_http do |req|
          raise "Unexpected request: #{req.uri}" unless req.uri.to_s.include?('bandcamp.com/testuser')

          success_response(collection_html)
        end
      end

      it 'downloads only the requested items by ID' do
        downloaded_keys = []
        allow(BandcampDlRb::Downloader).to receive(:download_album) do |_client, item, _lib, _fmt, **_kw|
          downloaded_keys << "#{item['sale_item_type']}#{item['sale_item_id']}"
          :downloaded
        end

        run_cli(['--library', @library, '--items', 'a100,t300', 'testuser'])

        expect(@exit_code).to eq(0)
        expect(@err_string).to include('Matched 2 item(s) from collection.')
        expect(@err_string).to include('Downloaded:  2')
        expect(downloaded_keys).to contain_exactly('a100', 't300')
      end

      it 'downloads nothing when requested IDs do not match the collection' do
        allow(BandcampDlRb::Downloader).to receive(:download_album)

        run_cli(['--library', @library, '--items', 'a999', 'testuser'])

        expect(@exit_code).to eq(1)
        expect(@err_string).to include('No matching items found for: a999')
        expect(@err_string).to include('Available item IDs: a100, a200, t300')
      end
    end
  end

  describe '#print_dry_run' do
    it 'prints each item with its ID, size, and the total size' do
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
            [a1] Radiohead - Kid A (1.1 MB)
            [a2] Radiohead - Amnesiac (781.2 KB)

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
            [a1] Artist - Album (1.1 MB)
            [a2] Artist - Mystery (unknown size)

          Total: 2 items, 1.1 MB (+1 unknown) would be downloaded
        OUT
      ).to_stderr
    end

    it 'shows track IDs correctly' do
      cli = described_class.new(out: StringIO.new, err: StringIO.new)
      items = {
        't500' => { 'band_name' => 'Aphex Twin', 'item_title' => 'Windowlicker',
                    'redownload_url' => 'https://bandcamp.com/redownload/5' }
      }
      allow(cli).to receive(:download_size_for).and_return(5_000_000)

      expect { cli.send(:print_dry_run, double('client'), items, 'flac') }.to output(
        <<~OUT
          \n--- Dry Run ---
            [t500] Aphex Twin - Windowlicker (4.8 MB)

          Total: 1 items, 4.8 MB would be downloaded
        OUT
      ).to_stderr
    end
  end

  describe '#resolve_url_items' do
    let(:cli) { described_class.new(out: StringIO.new, err: StringIO.new) }
    let(:client) { instance_double(BandcampDlRb::Client) }

    before do
      allow(client).to receive(:get_html).and_return('<html></html>')
      allow(client).to receive(:parse_tralbum).and_return(
        'band_name' => 'Radiohead',
        'item_title' => 'In Rainbows',
        'sale_item_id' => 2_162_872_411,
        'sale_item_type' => 'a'
      )
      allow(client).to receive(:get_collection).and_return(
        'a2162872411' => {
          'sale_item_type' => 'a',
          'sale_item_id' => 2_162_872_411,
          'band_name' => 'Radiohead',
          'item_title' => 'In Rainbows',
          'redownload_url' => 'https://bandcamp.com/download/album?id=2162872411'
        }
      )
      allow(client).to receive(:find_item_in_collection).and_return(
        'sale_item_type' => 'a',
        'sale_item_id' => 2_162_872_411,
        'band_name' => 'Radiohead',
        'item_title' => 'In Rainbows',
        'redownload_url' => 'https://bandcamp.com/download/album?id=2162872411'
      )
    end

    it 'resolves a URL to a collection item' do
      options = {
        urls: ['https://radiohead.bandcamp.com/album/in-rainbows'],
        username: 'testuser',
        include_hidden: false
      }
      items = cli.send(:resolve_url_items, client, options)
      expect(items.length).to eq(1)
      expect(items.values.first['band_name']).to eq('Radiohead')
    end

    it 'returns empty hash when page fetch fails' do
      allow(client).to receive(:get_html).and_return(nil)
      options = {
        urls: ['https://radiohead.bandcamp.com/album/in-rainbows'],
        username: 'testuser',
        include_hidden: false
      }
      items = cli.send(:resolve_url_items, client, options)
      expect(items).to eq({})
    end

    it 'returns empty hash when tralbum parsing fails' do
      allow(client).to receive(:parse_tralbum).and_return(nil)
      options = {
        urls: ['https://radiohead.bandcamp.com/album/in-rainbows'],
        username: 'testuser',
        include_hidden: false
      }
      items = cli.send(:resolve_url_items, client, options)
      expect(items).to eq({})
    end

    it 'returns empty hash when item not found in collection' do
      allow(client).to receive(:find_item_in_collection).and_return(nil)
      options = {
        urls: ['https://radiohead.bandcamp.com/album/in-rainbows'],
        username: 'testuser',
        include_hidden: false
      }
      items = cli.send(:resolve_url_items, client, options)
      expect(items).to eq({})
    end

    it 'returns empty hash when no username is provided' do
      options = {
        urls: ['https://radiohead.bandcamp.com/album/in-rainbows'],
        username: nil,
        include_hidden: false
      }
      items = cli.send(:resolve_url_items, client, options)
      expect(items).to eq({})
    end

    it 'resolves multiple URLs' do
      call_count = 0
      allow(client).to receive(:get_html) do
        call_count += 1
        '<html></html>'
      end
      allow(client).to receive(:parse_tralbum) do
        { 'band_name' => "Artist #{call_count}", 'item_title' => "Album #{call_count}",
          'sale_item_id' => call_count, 'sale_item_type' => 'a' }
      end
      allow(client).to receive(:find_item_in_collection) do |_items, tralbum|
        { 'sale_item_type' => tralbum['sale_item_type'],
          'sale_item_id' => tralbum['sale_item_id'],
          'band_name' => tralbum['band_name'],
          'item_title' => tralbum['item_title'],
          'redownload_url' => "https://bandcamp.com/download/#{tralbum['sale_item_id']}" }
      end

      options = {
        urls: [
          'https://radiohead.bandcamp.com/album/in-rainbows',
          'https://aphextwin.bandcamp.com/album/syro'
        ],
        username: 'testuser',
        include_hidden: false
      }
      items = cli.send(:resolve_url_items, client, options)
      expect(items.length).to eq(2)
    end
  end

  describe '#filter_collection_items' do
    let(:cli) { described_class.new(out: StringIO.new, err: StringIO.new) }
    let(:client) { instance_double(BandcampDlRb::Client) }

    before do
      allow(client).to receive(:get_collection).and_return(
        'a100' => {
          'sale_item_type' => 'a', 'sale_item_id' => 100,
          'band_name' => 'Radiohead', 'item_title' => 'Kid A',
          'redownload_url' => 'https://bandcamp.com/redownload/1'
        },
        'a200' => {
          'sale_item_type' => 'a', 'sale_item_id' => 200,
          'band_name' => 'Radiohead', 'item_title' => 'Amnesiac',
          'redownload_url' => 'https://bandcamp.com/redownload/2'
        },
        't300' => {
          'sale_item_type' => 't', 'sale_item_id' => 300,
          'band_name' => 'Aphex Twin', 'item_title' => 'Windowlicker',
          'redownload_url' => 'https://bandcamp.com/redownload/3'
        }
      )
      allow(client).to receive(:filter_by_ids) do |items, ids|
        ids_str = ids.is_a?(Array) ? ids.join(',') : ids
        keys = ids_str.split(',').map(&:strip)
        items.slice(*keys)
      end
    end

    it 'filters collection by item IDs' do
      options = { username: 'testuser', items: 'a100,t300', include_hidden: false }
      items = cli.send(:filter_collection_items, client, options)
      expect(items.keys).to contain_exactly('a100', 't300')
    end

    it 'returns nil when no items match' do
      options = { username: 'testuser', items: 'a999', include_hidden: false }
      items = cli.send(:filter_collection_items, client, options)
      expect(items).to be_nil
    end

    it 'returns nil when collection is empty' do
      allow(client).to receive(:get_collection).and_return({})
      options = { username: 'testuser', items: 'a100', include_hidden: false }
      items = cli.send(:filter_collection_items, client, options)
      expect(items).to be_nil
    end
  end
end
