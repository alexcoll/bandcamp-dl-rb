# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe BandcampDlRb::CLI do
  subject(:cli) { described_class.new(out: out, err: err) }

  let(:out) { StringIO.new }
  let(:err) { StringIO.new }

  include BandcampFixtures

  include_context 'with a temporary directory'

  # --help and --version exit rather than returning. Swallow the SystemExit so
  # the status and whatever was printed can be asserted on separately, one
  # expectation at a time.
  def exit_status_from
    yield
    nil
  rescue SystemExit => e
    e
  end

  def swallow_error
    yield
  rescue StandardError
    nil
  end

  describe '.parse_args' do
    subject(:options) { described_class.parse_args(args) }

    let(:args) { ['--library', '/mnt/music', 'myuser'] }

    context 'with a username' do
      it 'sets the library' do
        expect(options).to include(library: '/mnt/music')
      end

      it 'sets the username' do
        expect(options).to include(username: 'myuser')
      end

      it 'defaults the format to flac' do
        expect(options).to include(format: 'flac')
      end

      it 'defaults the browser to auto' do
        expect(options).to include(browser: 'auto')
      end

      it 'defaults the page size' do
        expect(options).to include(page_size: BandcampDlRb::DEFAULT_PAGE_SIZE)
      end

      it 'defaults jobs to 1' do
        expect(options).to include(jobs: 1)
      end

      it 'defaults unzip to true' do
        expect(options).to include(unzip: true)
      end

      it 'defaults progress to true' do
        expect(options).to include(progress: true)
      end

      it 'defaults filter to nil' do
        expect(options).to include(filter: nil)
      end

      it 'defaults urls to an empty array' do
        expect(options).to include(urls: [])
      end

      it 'defaults items to nil' do
        expect(options).to include(items: nil)
      end

      it 'defaults include_hidden to false' do
        expect(options).to include(include_hidden: false)
      end
    end

    context 'with a format' do
      let(:args) { ['--library', '/x', '--format', 'wav', 'u'] }

      it { is_expected.to include(format: 'wav') }
    end

    context 'with --include-hidden' do
      let(:args) { ['--library', '/x', '--include-hidden', 'u'] }

      it { is_expected.to include(include_hidden: true) }
    end

    context 'with --no-unzip' do
      let(:args) { ['--library', '/x', '--no-unzip', 'u'] }

      it { is_expected.to include(unzip: false) }
    end

    context 'with --no-progress' do
      let(:args) { ['--library', '/x', '--no-progress', 'u'] }

      it { is_expected.to include(progress: false) }
    end

    context 'with --since' do
      let(:args) { ['--library', '/x', '--since', '2024-01-01', 'u'] }

      it { is_expected.to include(since: Date.new(2024, 1, 1)) }
    end

    context 'with --until' do
      let(:args) { ['--library', '/x', '--until', '2024-12-31', 'u'] }

      it { is_expected.to include(until_date: Date.new(2024, 12, 31)) }
    end

    context 'with --browser' do
      let(:args) { ['--library', '/x', '--browser', 'firefox', 'u'] }

      it { is_expected.to include(browser: 'firefox') }
    end

    context 'with --page-size' do
      let(:args) { ['--library', '/x', '--page-size', '250', 'u'] }

      it { is_expected.to include(page_size: 250) }
    end

    context 'with --jobs' do
      let(:args) { ['--library', '/x', '--jobs', '3', 'u'] }

      it { is_expected.to include(jobs: 3) }
    end

    context 'with --filter' do
      let(:args) { ['--library', '/x', '--filter', 'amd', 'u'] }

      it { is_expected.to include(filter: 'amd') }
    end

    context 'with --cookie-file' do
      let(:args) { ['--library', '/x', '--cookie-file', '/tmp/cookies.txt', 'u'] }

      it { is_expected.to include(cookie_file: '/tmp/cookies.txt') }
    end

    context 'with --entry-encoding' do
      let(:args) { ['--library', '/x', '--entry-encoding', 'CP932', 'u'] }

      it { is_expected.to include(entry_encoding: 'CP932') }
    end

    context 'with --state-file' do
      let(:args) { ['--library', '/x', '--state-file', '/tmp/state.json', 'u'] }

      it { is_expected.to include(state_file: '/tmp/state.json') }
    end

    context 'with --no-state-file' do
      let(:args) { ['--library', '/x', '--no-state-file', 'u'] }

      it { is_expected.to include(state_file: false) }
    end

    context 'with neither flag' do
      let(:args) { ['--library', '/x', 'u'] }

      # nil is the "use the default under the library root" sentinel, which is
      # why write_state_file tests against false rather than truthiness.
      it { is_expected.to include(state_file: nil) }
    end

    context 'with --items' do
      let(:args) { ['--library', '/x', '--items', 'a100,t200', 'myuser'] }

      it { is_expected.to include(items: 'a100,t200') }
    end

    context 'with a single --url' do
      let(:args) { ['--library', '/x', '--url', 'https://radiohead.bandcamp.com/album/in-rainbows'] }

      it 'collects the url' do
        expect(options).to include(urls: ['https://radiohead.bandcamp.com/album/in-rainbows'])
      end

      it 'leaves the username unset' do
        expect(options).to include(username: nil)
      end
    end

    context 'with several --url flags' do
      let(:args) do
        ['--library', '/x',
         '--url', 'https://radiohead.bandcamp.com/album/in-rainbows',
         '--url', 'https://radiohead.bandcamp.com/album/ok-computer']
      end

      it 'collects both urls in order' do
        expect(options[:urls]).to eq(
          ['https://radiohead.bandcamp.com/album/in-rainbows',
           'https://radiohead.bandcamp.com/album/ok-computer']
        )
      end
    end

    context 'with --url and a positional username' do
      let(:args) { ['--library', '/x', '--url', 'https://radiohead.bandcamp.com/album/in-rainbows', 'testuser'] }

      it { is_expected.to include(username: 'testuser') }
    end

    context 'with --help' do
      let(:args) { ['--help'] }

      # .parse_args builds its own CLI writing to $stdout, so the banner is
      # captured through this instance instead.
      # --help exits rather than returning, so the status has to be caught
      # before anything else can be asserted about it.
      it 'exits successfully' do
        expect(exit_status_from { cli.parse_args(args) }.status).to eq(0)
      end

      it 'prints the usage banner' do
        exit_status_from { cli.parse_args(args) }
        expect(out.string).to include('Usage:')
      end
    end
  end

  describe '.run' do
    subject(:exit_code) { described_class.run(args, out: out, err: err) }

    let(:args) { [] }

    context 'with no arguments' do
      it { is_expected.to eq(1) }
    end

    context 'with a username but no library' do
      let(:args) { ['myuser'] }

      it { is_expected.to eq(1) }
    end

    context 'with --items but no username' do
      let(:args) { ['--library', '/x', '--items', 'a100'] }

      it { is_expected.to eq(1) }
    end

    context 'with --filter but no username' do
      let(:args) { ['--library', '/x', '--filter', 'amd'] }

      it { is_expected.to eq(1) }
    end

    context 'with --jobs above the cap' do
      let(:args) { ['--library', '/x', '--jobs', '17', 'u'] }

      it { is_expected.to eq(1) }

      it 'explains the allowed range' do
        exit_code
        expect(err.string).to include('--jobs must be between 1 and 16')
      end
    end

    context 'with --jobs below 1' do
      let(:args) { ['--library', '/x', '--jobs', '0', 'u'] }

      it { is_expected.to eq(1) }
    end

    context 'with --page-size above the cap' do
      let(:args) { ['--library', '/x', '--page-size', '9999', 'u'] }

      it { is_expected.to eq(1) }

      it 'explains the allowed range' do
        exit_code
        expect(err.string).to include('--page-size must be between 1 and 500')
      end
    end

    context 'with --page-size below 1' do
      let(:args) { ['--library', '/x', '--page-size', '0', 'u'] }

      it { is_expected.to eq(1) }
    end

    context 'when no identity cookie can be found' do
      let(:args) { ['--library', dest, 'testuser'] }

      before { allow(BandcampDlRb::CookieExtractor).to receive(:get_identity_cookie).and_return(nil) }

      it { is_expected.to eq(1) }

      it 'says so' do
        exit_code
        expect(err.string).to include('Could not find Bandcamp identity cookie')
      end

      it 'tells the user how to fix it' do
        exit_code
        expect(err.string).to include('To fix this, try one of:')
      end
    end

    context 'with --version' do
      let(:args) { ['--version'] }

      it 'exits successfully' do
        expect(exit_status_from { exit_code }.status).to eq(0)
      end

      it 'prints the version' do
        exit_status_from { exit_code }
        expect(out.string).to eq("bandcamp_dl_rb #{BandcampDlRb::VERSION}\n")
      end
    end
  end

  describe '#authenticate' do
    subject(:identity) { cli.send(:authenticate, options) }

    let(:options) { { browser: 'auto', cookie_file: nil } }

    context 'when a cookie can be read' do
      before { allow(BandcampDlRb::CookieExtractor).to receive(:get_identity_cookie).and_return('test-id') }

      it { is_expected.to eq('test-id') }
    end

    context 'when no cookie can be read' do
      before { allow(BandcampDlRb::CookieExtractor).to receive(:get_identity_cookie).and_return(nil) }

      it { is_expected.to be_nil }

      it 'reports the failure' do
        identity
        expect(err.string).to include('Could not find Bandcamp identity cookie.')
      end

      it 'offers next steps' do
        identity
        expect(err.string).to include('To fix this, try one of:')
      end
    end
  end

  # End-to-end runs through CLI#run, Client and the real HTTP stack, with only
  # Bandcamp's own endpoints stubbed. These are the tests that would catch a
  # wiring mistake between the option parser, the client and the downloader.
  describe 'end-to-end runs' do
    let(:profile_url) { 'https://bandcamp.com/testuser' }
    let(:collection_page) { pagedata_page(collection_blob(collection_items)) }
    let(:collection_items) do
      [
        sale_item(id: 100, artist: 'Radiohead', title: 'Kid A'),
        sale_item(id: 200, artist: 'Radiohead', title: 'Amnesiac'),
        sale_item(id: 300, artist: 'Aphex Twin', title: 'Windowlicker', type: 't')
      ]
    end

    before do
      allow(BandcampDlRb::CookieExtractor).to receive(:get_identity_cookie).and_return('test-identity')
      stub_request(:get, profile_url).to_return(body: collection_page)
    end

    # BandcampDlRb.log writes with `warn`, so a faithful capture has to take
    # over $stderr as well as the stream passed in as err:.
    def run_cli(argv)
      err_io = StringIO.new
      warnings = StringIO.new
      previous = $stderr
      begin
        $stderr = warnings
        code = described_class.run(argv, out: StringIO.new, err: err_io)
      ensure
        $stderr = previous
      end
      { exit_code: code, output: warnings.string + err_io.string }
    end

    def recording_downloader(result = :downloaded)
      downloaded = []
      allow(BandcampDlRb::Downloader).to receive(:download_album) do |_client, item, *_args, **_kwargs|
        downloaded << { key: "#{item['sale_item_type']}#{item['sale_item_id']}", item: item }
        result
      end
      downloaded
    end

    context 'when running in URL mode' do
      let(:album_url) { 'https://radiohead.bandcamp.com/album/in-rainbows' }
      let(:owned) do
        [sale_item(id: 403_398_974, artist: 'Radiohead', title: 'In Rainbows', type: 'p',
                   'tralbum_id' => 2_162_872_411, 'tralbum_type' => 'a')]
      end

      before do
        stub_request(:get, profile_url).to_return(body: pagedata_page(collection_blob(owned)))
        stub_request(:get, album_url)
          .to_return(body: tralbum_page(artist: 'Radiohead', title: 'In Rainbows', id: 2_162_872_411))
      end

      it 'downloads the album behind the url' do
        downloaded = recording_downloader
        run_cli(['--library', dest, '--url', album_url, 'testuser'])
        expect(downloaded.map { |d| d[:item]['item_title'] }).to eq(['In Rainbows'])
      end

      it 'attaches the redownload url' do
        downloaded = recording_downloader
        run_cli(['--library', dest, '--url', album_url, 'testuser'])
        expect(downloaded.first[:item]['redownload_url']).to eq(redownload_url('p403398974'))
      end

      it 'reports success' do
        recording_downloader
        expect(run_cli(['--library', dest, '--url', album_url, 'testuser'])[:exit_code]).to eq(0)
      end

      it 'records the synced item ids' do
        recording_downloader
        run_cli(['--library', dest, '--url', album_url, 'testuser'])
        state = JSON.parse(File.read(File.join(dest, '.bandcamp-sync.json')))
        expect(state['item_ids']).to eq(['p403398974'])
      end

      context 'when the album is not in the collection' do
        let(:unowned_url) { 'https://somebody.bandcamp.com/album/not-owned' }

        before do
          stub_request(:get, unowned_url)
            .to_return(body: tralbum_page(artist: 'Somebody', title: 'Not Owned', id: 999))
        end

        it 'exits with 1' do
          recording_downloader
          expect(run_cli(['--library', dest, '--url', unowned_url, 'testuser'])[:exit_code]).to eq(1)
        end

        it 'says why' do
          recording_downloader
          expect(run_cli(['--library', dest, '--url', unowned_url, 'testuser'])[:output])
            .to include('Not found in collection or no download available')
        end
      end
    end

    context 'when running in items mode' do
      let(:received) { [] }

      # Records [sale_item_id, unzip] for each album the run asks for.
      before do
        allow(BandcampDlRb::Downloader).to receive(:download_album) do |_client, item, *_a, **kwargs|
          received << [item['sale_item_id'], kwargs[:unzip]]
          :downloaded
        end
      end

      it 'downloads only the requested ids' do
        downloaded = recording_downloader
        run_cli(['--library', dest, '--items', 'a100,t300', 'testuser'])
        expect(downloaded.map { |d| d[:key] }).to contain_exactly('a100', 't300')
      end

      it 'reports the match count' do
        recording_downloader
        expect(run_cli(['--library', dest, '--items', 'a100,t300', 'testuser'])[:output])
          .to include('Matched 2 item(s) from collection.')
      end

      it 'passes unzip: false with --no-unzip' do
        run_cli(['--library', dest, '--no-unzip', '--items', 'a100', 'testuser'])

        expect(received).to eq([[100, false]])
      end

      it 'reports failure when nothing matches' do
        recording_downloader
        expect(run_cli(['--library', dest, '--items', 'a999', 'testuser'])[:exit_code]).to eq(1)
      end

      describe 'progress bars' do
        # The real renderer is kept so log lines still land in the captured
        # stderr; only the two lifecycle calls are spied on.
        let(:renderer) { BandcampDlRb::Progress.current }
        # Building the client is outside the per-item rescue, so raising there
        # aborts the run the way a crash mid-sync would.
        let(:failing_run) { -> { run_cli(['--library', dest, '--items', 'a100', 'testuser']) } }

        before do
          allow(renderer).to receive(:enabled=).and_call_original
          allow(renderer).to receive(:close).and_call_original
          allow(BandcampDlRb::Downloader).to receive(:download_album).and_return(:downloaded)
        end

        context 'with a normal run' do
          it 'enables progress by default' do
            run_cli(['--library', dest, '--items', 'a100', 'testuser'])
            expect(renderer).to have_received(:enabled=).with(true)
          end

          # The bars are drawn on stderr alongside the log, so they must be
          # wiped before the summary or the cursor is left inside the block.
          it 'clears the block before the run ends' do
            run_cli(['--library', dest, '--items', 'a100', 'testuser'])
            expect(renderer).to have_received(:close)
          end

          it 'draws nothing when stderr is redirected' do
            result = run_cli(['--library', dest, '--items', 'a100', 'testuser'])
            expect(result[:output]).not_to include("\e[")
          end
        end

        context 'with --no-progress' do
          it 'disables progress' do
            run_cli(['--library', dest, '--no-progress', '--items', 'a100', 'testuser'])
            expect(renderer).to have_received(:enabled=).with(false)
          end
        end

        context 'with a run that dies partway' do
          it 'lets the error out' do
            allow(BandcampDlRb::Client).to receive(:new).and_raise('boom')
            expect { failing_run.call }.to raise_error('boom')
          end

          it 'clears the block even so' do
            allow(BandcampDlRb::Client).to receive(:new).and_raise('boom')
            swallow_error { failing_run.call }
            expect(renderer).to have_received(:close)
          end
        end
      end

      it 'lists the available ids' do
        recording_downloader
        expect(run_cli(['--library', dest, '--items', 'a999', 'testuser'])[:output])
          .to include('Available item IDs: a100, a200, t300')
      end
    end

    context 'when running in filter mode' do
      it 'downloads only the matching items' do
        downloaded = recording_downloader
        run_cli(['--library', dest, '--filter', 'radiohead', 'testuser'])
        expect(downloaded.map { |d| d[:key] }).to contain_exactly('a100', 'a200')
      end

      # A filter matching nothing exits 1 -- already covered by the items-mode
      # example above. Only the malformed-regex path is unique here.
      it 'exits with 1 on an invalid regex' do
        recording_downloader
        expect(run_cli(['--library', dest, '--filter', '[', 'testuser'])[:exit_code]).to eq(1)
      end
    end

    context 'with no mode flags' do
      let(:downloaded) { Queue.new }

      before do
        allow(BandcampDlRb::Downloader).to receive(:download_album) do |_client, item, *_a, **_kw|
          downloaded << "#{item['sale_item_type']}#{item['sale_item_id']}"
          :downloaded
        end
      end

      it 'downloads the whole collection serially' do
        downloaded = recording_downloader
        run_cli(['--library', dest, 'testuser'])
        expect(downloaded.length).to eq(3)
      end

      it 'reports the download count' do
        recording_downloader
        expect(run_cli(['--library', dest, 'testuser'])[:output]).to include('Downloaded:  3')
      end

      it 'records the synced item ids' do
        recording_downloader
        run_cli(['--library', dest, 'testuser'])
        state = JSON.parse(File.read(File.join(dest, '.bandcamp-sync.json')))
        expect(state['item_ids']).to contain_exactly('a100', 'a200', 't300')
      end

      context 'with --state-file' do
        let(:custom) { File.join(dest, 'state', 'custom.json') }

        before do
          recording_downloader
          run_cli(['--library', dest, '--state-file', custom, 'testuser'])
        end

        it 'writes the state file to the given path' do
          expect(File.exist?(custom)).to be(true)
        end

        # The library root is the only directory #run creates, so an explicit
        # path elsewhere would raise ENOENT without this.
        it 'creates a missing parent directory' do
          expect(File.directory?(File.dirname(custom))).to be(true)
        end

        it 'records the synced item ids there' do
          expect(JSON.parse(File.read(custom))['item_ids']).to contain_exactly('a100', 'a200', 't300')
        end

        it 'leaves the default location alone' do
          expect(File.exist?(File.join(dest, '.bandcamp-sync.json'))).to be(false)
        end
      end

      context 'with --no-state-file' do
        # No recording_downloader here: the outer before already records into
        # +downloaded+, and re-stubbing would shadow that Queue.
        before { run_cli(['--library', dest, '--no-state-file', 'testuser']) }

        it 'writes no state file in the library' do
          expect(File.exist?(File.join(dest, '.bandcamp-sync.json'))).to be(false)
        end

        # The flag suppresses bookkeeping, not the downloads themselves.
        it 'still downloads everything' do
          expect(downloaded.size).to eq(3)
        end
      end

      it 'downloads in parallel with --jobs' do
        run_cli(['--library', dest, '--jobs', '2', 'testuser'])
        expect(downloaded.size).to eq(3)
      end

      context 'when the collection is empty' do
        let(:collection_page) { pagedata_page(collection_blob([])) }

        it 'exits with 1' do
          expect(run_cli(['--library', dest, 'testuser'])[:exit_code]).to eq(1)
        end

        it 'says nothing was found' do
          expect(run_cli(['--library', dest, 'testuser'])[:output]).to include('No downloadable items found')
        end
      end
    end

    context 'with --dry-run' do
      let(:downloads_page) do
        pagedata_page(
          'download_items' => [{ 'downloads' => { 'flac' => { 'url' => 'https://bcbits/a.zip',
                                                              'size_mb' => '10MB' } } }]
        )
      end

      before { stub_request(:get, 'https://bandcamp.com/redownload/a100').to_return(body: downloads_page) }

      it 'exits successfully' do
        expect(run_cli(['--library', dest, '--dry-run', '--items', 'a100', 'testuser'])[:exit_code]).to eq(0)
      end

      it 'prints a dry run banner' do
        expect(run_cli(['--library', dest, '--dry-run', '--items', 'a100', 'testuser'])[:output])
          .to include('--- Dry Run ---')
      end

      it 'downloads nothing' do
        recording_downloader
        run_cli(['--library', dest, '--dry-run', '--items', 'a100', 'testuser'])
        expect(BandcampDlRb::Downloader).not_to have_received(:download_album)
      end
    end

    context 'when a download raises in parallel mode' do
      it 'still exits successfully' do
        allow(BandcampDlRb::Downloader).to receive(:download_album).and_raise(StandardError, 'boom')
        expect(run_cli(['--library', dest, '--jobs', '2', '--items', 'a100,t300', 'testuser'])[:exit_code]).to eq(0)
      end

      it 'logs the error' do
        allow(BandcampDlRb::Downloader).to receive(:download_album).and_raise(StandardError, 'boom')
        output = run_cli(['--library', dest, '--jobs', '2', '--items', 'a100,t300', 'testuser'])[:output]
        expect(output).to include('Error downloading', 'boom')
      end

      it 'counts the items as failed' do
        allow(BandcampDlRb::Downloader).to receive(:download_album).and_raise(StandardError, 'boom')
        output = run_cli(['--library', dest, '--jobs', '2', '--items', 'a100,t300', 'testuser'])[:output]
        expect(output).to include('Failed:      2')
      end
    end
  end

  describe '#print_dry_run' do
    subject(:printed) { cli.send(:print_dry_run, client, items, 'flac') }

    let(:client) { instance_double(BandcampDlRb::Client) }
    let(:items) do
      {
        'a1' => { 'band_name' => 'Radiohead', 'item_title' => 'Kid A',
                  'redownload_url' => 'https://bandcamp.com/redownload/1' },
        'a2' => { 'band_name' => 'Radiohead', 'item_title' => 'Amnesiac',
                  'redownload_url' => 'https://bandcamp.com/redownload/2' }
      }
    end

    context 'when every size is known' do
      before do
        allow(cli).to receive(:download_size_for).and_return(1_200_000, 800_000) # rubocop:disable RSpec/SubjectStub -- the dry-run table is the subject here, not the probe
        allow(BandcampDlRb).to receive(:log)
      end

      it 'lists the first item with its size' do
        printed
        expect(BandcampDlRb).to have_received(:log).with('  [a1] Radiohead - Kid A (1.1 MB)')
      end

      it 'lists the second item with its size' do
        printed
        expect(BandcampDlRb).to have_received(:log).with('  [a2] Radiohead - Amnesiac (781.2 KB)')
      end

      it 'sums the sizes into a total' do
        printed
        expect(BandcampDlRb).to have_received(:log).with(/\nTotal: 2 items, 1\.9 MB would be downloaded/)
      end
    end

    context 'when a size is unknown' do
      before do
        allow(cli).to receive(:download_size_for).and_return(1_200_000, nil) # rubocop:disable RSpec/SubjectStub -- the dry-run table is the subject here, not the probe
        allow(BandcampDlRb).to receive(:log)
      end

      it 'marks the item as unknown size' do
        printed
        expect(BandcampDlRb).to have_received(:log).with('  [a2] Radiohead - Amnesiac (unknown size)')
      end

      it 'counts the unknown sizes in the total' do
        printed
        expect(BandcampDlRb).to have_received(:log).with(/Total: 2 items, 1\.1 MB \(\+1 unknown\)/)
      end
    end

    context 'with a track item' do
      let(:items) do
        {
          't500' => { 'band_name' => 'Aphex Twin', 'item_title' => 'Windowlicker',
                      'redownload_url' => 'https://bandcamp.com/redownload/5' }
        }
      end

      before do
        allow(cli).to receive(:download_size_for).and_return(5_000_000) # rubocop:disable RSpec/SubjectStub -- the dry-run table is the subject here, not the probe
        allow(BandcampDlRb).to receive(:log)
      end

      it 'keys the line on the collection id' do
        printed
        expect(BandcampDlRb).to have_received(:log).with('  [t500] Aphex Twin - Windowlicker (4.8 MB)')
      end
    end
  end

  describe '#resolve_url_items' do
    subject(:items) { cli.send(:resolve_url_items, client, options) }

    let(:client) { BandcampDlRb::Client.new('ident') }
    let(:album_url) { 'https://radiohead.bandcamp.com/album/in-rainbows' }
    let(:profile_url) { 'https://bandcamp.com/testuser' }
    let(:options) { { urls: [album_url], username: 'testuser', include_hidden: false } }
    let(:owned) do
      [sale_item(id: 403_398_974, artist: 'Radiohead', title: 'In Rainbows', type: 'p',
                 'tralbum_id' => 2_162_872_411, 'tralbum_type' => 'a')]
    end

    before do
      stub_request(:get, profile_url).to_return(body: pagedata_page(collection_blob(owned)))
      stub_request(:get, album_url)
        .to_return(body: tralbum_page(artist: 'Radiohead', title: 'In Rainbows', id: 2_162_872_411))
    end

    context 'when the album is owned' do
      it 'resolves one item' do
        expect(items.length).to eq(1)
      end

      it 'carries the artist through' do
        expect(items.values.first['band_name']).to eq('Radiohead')
      end

      it 'carries the download url through' do
        expect(items.values.first['redownload_url']).to eq(redownload_url('p403398974'))
      end
    end

    context 'when the album is not owned' do
      let(:owned) { [] }

      it { is_expected.to eq({}) }
    end

    context 'when the page cannot be fetched' do
      before { stub_request(:get, album_url).to_return(status: 404) }

      it { is_expected.to eq({}) }
    end

    context 'when the tralbum cannot be parsed' do
      before { stub_request(:get, album_url).to_return(body: '<html>no data here</html>') }

      it { is_expected.to eq({}) }
    end

    context 'without a username' do
      let(:options) { { urls: [album_url], username: nil, include_hidden: false } }

      it { is_expected.to eq({}) }
    end

    context 'with several urls' do
      let(:second_url) { 'https://aphextwin.bandcamp.com/track/windowlicker' }
      let(:options) { { urls: [album_url, second_url], username: 'testuser', include_hidden: false } }

      before do
        stub_request(:get, second_url)
          .to_return(body: tralbum_page(artist: 'Aphex Twin', title: 'Windowlicker', id: 777, item_type: 'track'))
      end

      it 'resolves both' do
        expect(items.length).to eq(1)
      end

      it 'fetches the collection only once' do
        items
        expect(a_request(:get, profile_url)).to have_been_made.once
      end
    end

    context 'with a differing include_hidden flag' do
      it 'refetches the collection' do
        cli.send(:resolve_url_items, client, { urls: [album_url], username: 'testuser', include_hidden: true })
        cli.send(:resolve_url_items, client, { urls: [album_url], username: 'testuser', include_hidden: false })
        expect(a_request(:get, profile_url)).to have_been_made.twice
      end
    end
  end

  describe '#filter_collection_items' do
    subject(:items) { cli.send(:filter_collection_items, client, options) }

    let(:client) { BandcampDlRb::Client.new('ident') }
    let(:profile_url) { 'https://bandcamp.com/testuser' }
    let(:options) { { username: 'testuser', items: 'a100,t300', include_hidden: false } }
    let(:collection_page) do
      pagedata_page(
        collection_blob(
          [
            sale_item(id: 100, artist: 'Radiohead', title: 'Kid A'),
            sale_item(id: 200, artist: 'Radiohead', title: 'Amnesiac'),
            sale_item(id: 300, artist: 'Aphex Twin', title: 'Windowlicker', type: 't')
          ]
        )
      )
    end

    before { stub_request(:get, profile_url).to_return(body: collection_page) }

    context 'with ids the collection holds' do
      it 'returns just those' do
        expect(items.keys).to contain_exactly('a100', 't300')
      end
    end

    context 'with an id the collection does not hold' do
      let(:options) { { username: 'testuser', items: 'a999', include_hidden: false } }

      it { is_expected.to be_nil }
    end

    context 'with an empty collection' do
      let(:collection_page) { pagedata_page(collection_blob([])) }

      it { is_expected.to be_nil }
    end
  end

  describe '#filter_collection_by_regex' do
    subject(:items) { cli.send(:filter_collection_by_regex, client, options) }

    let(:client) { BandcampDlRb::Client.new('ident') }
    let(:profile_url) { 'https://bandcamp.com/testuser' }
    let(:options) { { username: 'testuser', filter: 'amnesiac', include_hidden: false } }
    let(:collection_page) do
      pagedata_page(
        collection_blob(
          [
            sale_item(id: 100, artist: 'Radiohead', title: 'Kid A'),
            sale_item(id: 200, artist: 'Radiohead', title: 'Amnesiac'),
            sale_item(id: 300, artist: 'Aphex Twin', title: 'Windowlicker', type: 't')
          ]
        )
      )
    end

    before { stub_request(:get, profile_url).to_return(body: collection_page) }

    context 'with a title pattern' do
      it { expect(items.keys).to eq(['a200']) }
    end

    context 'with an artist pattern' do
      let(:options) { { username: 'testuser', filter: 'aphex', include_hidden: false } }

      it { expect(items.keys).to eq(['t300']) }
    end

    context 'with a pattern nothing matches' do
      let(:options) { { username: 'testuser', filter: 'zzzz', include_hidden: false } }

      it { is_expected.to be_nil }
    end

    context 'with an empty collection' do
      let(:collection_page) { pagedata_page(collection_blob([])) }

      it { is_expected.to be_nil }
    end

    context 'with an invalid regex' do
      let(:options) { { username: 'testuser', filter: '[', include_hidden: false } }

      it { is_expected.to be_nil }
    end
  end

  describe '#download_size_for' do
    subject(:size) { cli.send(:download_size_for, client, item, 'flac') }

    let(:client) { BandcampDlRb::Client.new('ident') }
    let(:item) { { 'redownload_url' => 'https://bandcamp.com/redownload/1' } }

    context 'when the download url cannot be resolved' do
      before { allow(BandcampDlRb::Downloader).to receive(:get_download_url).and_return(nil) }

      it { is_expected.to be_nil }
    end

    context 'when the page advertises a size' do
      before do
        allow(BandcampDlRb::Downloader).to receive(:get_download_url)
          .and_return(url: 'https://bcbits/file.flac', format: 'flac', size_mb: '10MB')
      end

      it 'reads it from size_bytes' do
        allow(BandcampDlRb::Downloader).to receive(:size_bytes).and_return(10_485_760)
        expect(size).to eq(10_485_760)
      end

      it 'does not probe the file' do
        allow(BandcampDlRb::Downloader).to receive(:size_bytes).and_return(10_485_760)
        allow(BandcampDlRb::Downloader).to receive(:download_size)
        size
        expect(BandcampDlRb::Downloader).not_to have_received(:download_size)
      end
    end

    context 'when the page advertises no size' do
      before do
        allow(BandcampDlRb::Downloader).to receive(:get_download_url)
          .and_return(url: 'https://bcbits/file.flac', format: 'flac')
      end

      it 'probes the file instead' do
        allow(BandcampDlRb::Downloader).to receive_messages(size_bytes: nil, download_size: 5000)
        expect(size).to eq(5000)
      end
    end
  end
end
