# frozen_string_literal: true

require_relative '../spec_helper'

# Builds a zip archive by hand so entries can carry raw non-UTF-8 name bytes
# with the UTF-8 general-purpose flag (bit 11) clear, which is what a
# Shift-JIS/CP932 archive written on Japanese Windows looks like. rubyzip
# always writes valid UTF-8 names, so it cannot produce this fixture.
module RawZipFixture
  LOCAL_FIXED = 30
  CENTRAL_FIXED = 46
  EOCD_FIXED = 22

  module_function

  def build_zip(path, entries)
    io = StringIO.new(+''.b)
    central = entries.map { |name, payload| write_local_entry(io, name, payload) }
    cd_offset = io.size
    central.each { |c| write_central_entry(io, c) }
    write_eocd(io, central.length, io.size - cd_offset, cd_offset)
    File.binwrite(path, io.string)
    path
  end

  # version, flags, method, modtime, moddate, crc, csize, usize, namelen, extralen
  def write_local_entry(io, name, payload)
    offset = io.size
    io.write("PK\x03\x04".b)
    io.write([20, 0, 0, 0, 0, 0, payload.bytesize, payload.bytesize,
              name.bytesize, 0].pack('vvvvvVVVvv'))
    io.write(name)
    io.write(payload)
    [name, offset, payload.bytesize]
  end

  # made-by, version, flags, method, modtime, moddate, crc, csize, usize,
  # namelen, extralen, commentlen, disk, internal, external, offset
  def write_central_entry(io, central)
    name, offset, len = central
    io.write("PK\x01\x02".b)
    io.write([20, 20, 0, 0, 0, 0, 0, len, len, name.bytesize, 0, 0, 0, 0, 0,
              offset].pack('vvvvvvVVVvvvvvVV'))
    io.write(name)
  end

  def write_eocd(io, count, cd_size, cd_offset)
    io.write("PK\x05\x06".b)
    io.write([0, 0, count, count, cd_size, cd_offset, 0].pack('vvvvVVv'))
  end
end

# CP932 bytes, as written by Japanese Windows tooling.
CP932_TRACK = "01 \x83e\x83X\x83g - \x83T\x83O\x83b\x83L.flac".b.freeze
# CP437 bytes for a DOS-era accented title. 0xE9 is Theta, not e-acute.
CP437_TRACK = "01 Caf\xe9 - Track.mp3".b.freeze
# An archive of real, UTF-8-clean entries, served to the download code the way
# Bandcamp would serve it.
def zip_bytes(entries)
  buffer = Zip::OutputStream.write_buffer do |zip|
    entries.each do |name, body|
      zip.put_next_entry(name)
      zip.write(body)
    end
  end
  buffer.string
end

RSpec.describe BandcampDlRb::Downloader do
  let(:client) { BandcampDlRb::Client.new('ident') }

  # Baseline for the "leaves no bc temp dir behind" examples. let! snapshots
  # this before each example runs, so the comparison is against the machine's
  # starting state rather than an assumption that it began clean.
  let!(:bc_temp_dirs_before) { Dir.glob(File.join(Dir.tmpdir, 'bc*')) }

  include RawZipFixture

  # Guards the hand-rolled archive: a malformed fixture would make every
  # encoding example below pass or fail for the wrong reason.
  describe 'the raw-encoding zip fixture' do
    include_context 'with a temporary directory'

    it 'round-trips through rubyzip' do
      path = build_zip(File.join(dest, 'a.zip'), [[CP932_TRACK, 'audio'], ['cover.jpg'.b, 'cover']])
      seen = {}
      Zip::File.open(path) { |z| z.each { |e| seen[e.name] = e.get_input_stream.read } }
      expect(seen.keys.map(&:encoding)).to all(eq(Encoding::ASCII_8BIT))
    end

    it 'round-trips a CP932 payload' do
      path = build_zip(File.join(dest, 'a.zip'), [[CP932_TRACK, 'audio']])
      expect(Zip::File.open(path) { |z| z.first.get_input_stream.read }).to eq('audio')
    end

    it 'round-trips a plain payload' do
      path = build_zip(File.join(dest, 'a.zip'), [['cover.jpg'.b, 'cover']])
      expect(Zip::File.open(path) { |z| z.first.get_input_stream.read }).to eq('cover')
    end

    it 'uses the correct fixed header sizes' do
      name = 'x.flac'.b
      raw = File.binread(build_zip(File.join(dest, 'b.zip'), [[name, 'y']]))
      n = name.bytesize
      expect(raw.bytesize)
        .to eq(RawZipFixture::LOCAL_FIXED + n + 1 + RawZipFixture::CENTRAL_FIXED + n +
               RawZipFixture::EOCD_FIXED)
    end
  end

  describe '.get_download_url' do
    subject(:download) { described_class.get_download_url(client, album_url, format, **extra) }

    let(:album_url) { 'https://bandcamp.com/foo' }
    let(:format) { 'flac' }
    let(:extra) { {} }
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

    before { allow(client).to receive(:get_pagedata).and_return(pagedata) }

    context 'with the requested format' do
      it 'resolves the url and size' do
        expect(download).to include(url: 'https://bcbits/flac.zip', format: 'flac', size_mb: '1.2GB')
      end
      it 'carries the art id' do
        expect(download[:art_id]).to eq(12_345)
      end
    end

    context 'with a format the album does not offer' do
      let(:format) { 'wav' }
      it 'falls back to flac' do
        expect(download).to include(url: 'https://bcbits/flac.zip', format: 'flac')
      end
    end

    context 'with no formats at all' do
      before { pagedata['download_items'][0]['downloads'] = {} }
      it { is_expected.to be_nil }
    end

    context 'with no download items' do
      let(:pagedata) { { 'download_items' => [] } }
      it { is_expected.to be_nil }
    end

    context 'with pre-fetched pagedata' do
      let(:extra) { { pagedata: pagedata } }
      it 'does not re-fetch the page' do
        expect(client).not_to receive(:get_pagedata)
        download
      end
    end

    context 'with the art id only on the page' do
      before do
        pagedata['download_items'][0].delete('art_id')
        pagedata['art_id'] = 99_999
      end
      it 'falls back to the page-level art id' do
        expect(download[:art_id]).to eq(99_999)
      end
    end

    context 'with no art id anywhere' do
      before { pagedata['download_items'][0].delete('art_id') }
      it { expect(download).not_to have_key(:art_id) }
    end
  end

  describe '.size_bytes' do
    subject(:bytes) { described_class.size_bytes(download) }

    let(:download) { { size_mb: '495.5MB' } }

    context 'with megabytes' do
      it { is_expected.to eq((495.5 * 1024 * 1024).to_i) }
    end

    context 'with whole gigabytes' do
      let(:download) { { size_mb: '2GB' } }
      it { is_expected.to eq(2 * 1024 * 1024 * 1024) }
    end

    context 'with decimal gigabytes' do
      let(:download) { { size_mb: '1.2GB' } }
      it { is_expected.to eq((1.2 * 1024 * 1024 * 1024).to_i) }
    end

    context 'with no size advertised' do
      let(:download) { {} }
      it { is_expected.to be_nil }
    end

    context 'with an unparseable size' do
      let(:download) { { size_mb: 'nope' } }
      it { is_expected.to be_nil }
    end
  end

  describe '.album_dir_for' do
    include_context 'with a temporary directory'

    subject(:album_dir) { described_class.album_dir_for(item, dest) }

    let(:item) { { 'band_name' => 'Radiohead', 'item_title' => 'Kid A' } }

    context 'with ordinary names' do
      it 'nests them under the library' do
        expect(album_dir).to eq(File.join(dest, 'Radiohead', 'Kid A'))
      end
    end

    context 'with a dotdot band name' do
      let(:item) { { 'band_name' => '..', 'item_title' => 'Kid A' } }
      it 'stays inside the library' do
        expect(album_dir).to start_with(dest + File::SEPARATOR)
      end
    end

    context 'with a dotdot item title' do
      let(:item) { { 'band_name' => 'Radiohead', 'item_title' => '..' } }
      it 'stays inside the library' do
        expect(album_dir).to start_with(dest + File::SEPARATOR)
      end
    end

    context 'with a dotdot band name and title' do
      let(:item) { { 'band_name' => '. .', 'item_title' => '..' } }
      it 'stays inside the library' do
        expect(album_dir).to start_with(dest + File::SEPARATOR)
      end
    end

    context 'when the path would escape the library' do
      before { allow(described_class).to receive(:contained_in?).and_return(false) }
      it 'uses placeholder names' do
        expect(album_dir).to eq(File.join(dest, 'Unknown Artist', 'Unknown Album'))
      end
      it 'warns that the path escapes' do
        expect(BandcampDlRb).to receive(:log_verbose).with(/escapes library root/)
        album_dir
      end
    end
  end

  describe '.download_album' do
    include_context 'with a temporary directory'

    subject(:outcome) { described_class.download_album(client, item, dest, 'flac', **extra) }

    let(:extra) { {} }
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
    let(:album_dir) { File.join(dest, 'Radiohead', 'Kid A') }
    let(:pagedata) do
      {
        'download_items' => [
          { 'downloads' => { 'flac' => { 'url' => download_url, 'size_mb' => '10MB' } } }
        ]
      }
    end
    let(:download_url) { 'https://bcbits.com/kida.zip' }
    let(:archive) { zip_bytes('01 Everything In Its Right Place.flac' => 'audio') }

    before do
      allow(client).to receive(:get_pagedata).and_return(pagedata)
      stub_request(:get, download_url).to_return(status: 200, body: archive)
    end

    # A real archive served over a stubbed socket, so the download path under
    # test is the one that runs in production: write_stream, zip detection,
    # extraction and directory layout.
    context 'with a zip archive' do
      it { is_expected.to eq(:downloaded) }
      it 'extracts the tracks into the album dir' do
        outcome
        expect(File.read(File.join(album_dir, '01 Everything In Its Right Place.flac'))).to eq('audio')
      end
      it 'drops the archive' do
        outcome
        expect(File).not_to exist(File.join(album_dir, 'download.zip'))
      end
      it 'leaves no bc temp dir behind' do
        outcome
        expect(Dir.glob(File.join(Dir.tmpdir, 'bc*'))).to eq(bc_temp_dirs_before)
      end
      context 'with unzip disabled' do
        let(:extra) { { unzip: false } }

        it 'keeps the archive under the album name' do
          outcome
          expect(File).to exist(File.join(album_dir, 'Kid A.zip'))
        end
      end
    end

    context 'with a single-track download' do
      let(:archive) { 'flacdata' }
      let(:download_url) { 'https://bcbits.com/track.flac' }
      it 'copies the file into the album dir' do
        outcome
        expect(Dir.glob(File.join(album_dir, '*.flac'))).not_to be_empty
      end
    end

    context 'with an archive that cannot be extracted' do
      let(:archive) { "PK\x03\x04truncated" }
      before { allow(described_class).to receive(:sleep) }
      it 'reports success anyway' do
        outcome
        expect(File).to exist(File.join(album_dir, 'Kid A.zip'))
      end
    end

    context 'with the album already downloaded' do
      let(:archive) { zip_bytes('01 Track.flac' => 'audio') }
      before do
        FileUtils.mkdir_p(album_dir)
        FileUtils.touch(File.join(album_dir, '01.flac'))
      end
      it { is_expected.to eq(:skipped) }
    end

    context 'with an album whose extraction failed once' do
      # Second run must skip rather than re-download and re-fail forever.
      let(:archive) { zip_bytes('01 Track.flac' => 'audio') }
      before { allow(described_class).to receive(:extract_zip).and_return(false) }
      it 'is skipped on the second run' do
        described_class.download_album(client, item, dest, 'flac')
        expect(described_class.download_album(client, item, dest, 'flac')).to eq(:skipped)
      end
      it 'only downloads once' do
        described_class.download_album(client, item, dest, 'flac')
        described_class.download_album(client, item, dest, 'flac')
        expect(a_request(:get, download_url)).to have_been_made.once
      end
    end

    context 'when the album offers no download' do
      let(:pagedata) { { 'download_items' => [] } }
      it { is_expected.to eq(:unavailable) }
    end

    context 'when the download fails' do
      let(:archive) { 'never served' }
      before do
        stub_request(:get, download_url).to_return(status: 500)
        allow(described_class).to receive(:sleep)
      end
      it { is_expected.to eq(:failed) }
      it 'leaves no bc temp dir behind' do
        outcome
        expect(Dir.glob(File.join(Dir.tmpdir, 'bc*'))).to eq(bc_temp_dirs_before)
      end
    end

    context 'with cover art advertised' do
      let(:archive) { zip_bytes('01 Track.flac' => 'audio') }
      let(:pagedata) do
        {
          'download_items' => [
            {
              'downloads' => { 'flac' => { 'url' => download_url, 'size_mb' => '1MB' } },
              'art_id' => 12_345
            }
          ]
        }
      end
      before { stub_request(:get, 'https://f4.bcbits.com/img/a12345_10.jpg').to_return(body: 'coverdata') }
      it 'saves cover.jpg from the CDN' do
        outcome
        expect(File.read(File.join(album_dir, 'cover.jpg'))).to eq('coverdata')
      end
    end

    context 'with a cover already on disk' do
      let(:archive) { zip_bytes('01 Track.flac' => 'audio') }
      let(:pagedata) do
        {
          'download_items' => [
            {
              'downloads' => { 'flac' => { 'url' => download_url, 'size_mb' => '1MB' } },
              'art_id' => 12_345
            }
          ]
        }
      end
      before do
        FileUtils.mkdir_p(album_dir)
        File.write(File.join(album_dir, 'cover.jpg'), 'existing-cover')
        stub_request(:get, 'https://f4.bcbits.com/img/a12345_10.jpg').to_return(body: 'new-cover')
      end
      it 'leaves the existing cover alone' do
        outcome
        expect(File.read(File.join(album_dir, 'cover.jpg'))).to eq('existing-cover')
      end
    end

    context 'with release metadata' do
      let(:archive) { zip_bytes('01 Track.flac' => 'audio') }
      let(:pagedata) do
        {
          'album_release_date' => '1 Oct 2000',
          'download_items' => [
            {
              'downloads' => { 'flac' => { 'url' => download_url, 'size_mb' => '1MB' } },
              'trackinfo' => [{ 'title' => 'Everything In Its Right Place', 'duration' => 251, 'track_num' => 1 }]
            }
          ]
        }
      end
      it 'writes album.json with the release date' do
        outcome
        info = JSON.parse(File.read(File.join(album_dir, 'album.json')))
        expect(info['release_date']).to eq('1 Oct 2000')
      end
      it 'writes album.json with the tracklist' do
        outcome
        info = JSON.parse(File.read(File.join(album_dir, 'album.json')))
        expect(info['tracklist'].first['title']).to eq('Everything In Its Right Place')
      end
    end
  end

  describe '.temp_dir_for' do
    subject(:temp_dir) { @temp_dir ||= described_class.temp_dir_for('sale_item_id' => 7) }

    after { FileUtils.rm_rf(@temp_dir) if @temp_dir }

    it 'creates a real directory' do
      expect(File).to be_directory(temp_dir)
    end

    it 'names it with the bc prefix' do
      expect(temp_dir).to start_with(File.join(Dir.tmpdir, 'bc'))
    end

    it 'locks it to 0700' do
      expect(File.stat(temp_dir).mode & 0o777).to eq(0o700)
    end
  end

  describe '.download_to_temp' do
    include_context 'with a temporary directory'

    subject(:tmp_file) { described_class.download_to_temp(client, download, dest) }

    let(:download) { { url: 'https://bcbits.com/track.flac', format: 'flac' } }

    before { stub_request(:get, download[:url]).to_return(body: 'flacdata') }

    it 'writes the downloaded bytes' do
      expect(File.read(tmp_file)).to eq('flacdata')
    end

    it 'locks the file to 0600' do
      expect(File.stat(tmp_file).mode & 0o777).to eq(0o600)
    end
  end

  describe '.extract_album_metadata' do
    subject(:info) { described_class.extract_album_metadata(pagedata) }

    context 'with a full album blob' do
      let(:pagedata) do
        {
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
      end
      it 'maps the artist' do
        expect(info['artist']).to eq('Radiohead')
      end
      it 'maps the title' do
        expect(info['title']).to eq('Kid A')
      end
      it 'maps the release date' do
        expect(info['release_date']).to eq('1 Oct 2000')
      end
      it 'maps the label' do
        expect(info['label']).to eq('XL Recordings')
      end
      it 'maps the credits' do
        expect(info['credits']).to eq('Written by Radiohead')
      end
      it 'keeps durations and track numbers' do
        expect(info['tracklist']).to eq(
          [
            { 'title' => 'Everything In Its Right Place', 'duration' => 251, 'track_num' => 1 },
            { 'title' => 'Kid A', 'duration' => 285, 'track_num' => 2 }
          ]
        )
      end
    end

    context 'with trackinfo only on the page' do
      let(:pagedata) do
        { 'trackinfo' => [{ 'title' => 'Windowlicker', 'duration' => 377 }],
          'download_items' => [{ 'downloads' => {} }] }
      end
      it 'still builds a tracklist' do
        expect(info['tracklist']).to eq([{ 'title' => 'Windowlicker', 'duration' => 377 }])
      end
    end

    context 'with no metadata at all' do
      let(:pagedata) { { 'download_items' => [{}] } }
      it { is_expected.to eq({}) }
    end

    context 'with a nil payload' do
      let(:pagedata) { nil }
      it { is_expected.to eq({}) }
    end
  end

  describe '.save_album_info' do
    include_context 'with a temporary directory'

    subject(:written) { described_class.save_album_info(pagedata, dest) }

    let(:pagedata) do
      {
        'album_release_date' => '1 Oct 2000',
        'download_items' => [
          {
            'downloads' => { 'flac' => { 'url' => 'https://bcbits/track.flac' } },
            'trackinfo' => [{ 'title' => 'Track 1', 'duration' => 200, 'track_num' => 1 }]
          }
        ]
      }
    end

    def info
      JSON.parse(File.read(File.join(dest, 'album.json')))
    end

    context 'with metadata' do
      it 'writes the release date' do
        written
        expect(info['release_date']).to eq('1 Oct 2000')
      end
      it 'writes the tracklist' do
        written
        expect(info['tracklist'].first['title']).to eq('Track 1')
      end
    end

    context 'with a nil payload' do
      let(:pagedata) { nil }
      it 'writes nothing' do
        written
        expect(Dir.glob(File.join(dest, '*'))).to be_empty
      end
    end

    context 'with empty metadata' do
      let(:pagedata) { { 'download_items' => [{}] } }
      it 'writes nothing' do
        written
        expect(Dir.glob(File.join(dest, '*'))).to be_empty
      end
    end

    context 'when extraction raises' do
      before { allow(described_class).to receive(:extract_album_metadata).and_raise(StandardError, 'parse error') }
      it 'swallows the error' do
        expect { written }.not_to raise_error
      end
    end
  end

  describe '.save_cover' do
    include_context 'with a temporary directory'

    subject(:saved) { described_class.save_cover(client, download_info, dest) }

    let(:cover_path) { File.join(dest, 'cover.jpg') }
    let(:cover_url) { 'https://f4.bcbits.com/img/a12345_10.jpg' }

    context 'with an art id' do
      let(:download_info) { { art_id: 12_345 } }
      before { stub_request(:get, cover_url).to_return(body: 'coverdata') }
      it 'writes cover.jpg' do
        saved
        expect(File.read(cover_path)).to eq('coverdata')
      end
    end

    context 'without an art id' do
      let(:download_info) { {} }
      it 'requests nothing' do
        saved
        expect(a_request(:get, cover_url)).not_to have_been_made
      end
    end

    context 'when the cover download fails' do
      let(:download_info) { { art_id: 1 } }
      let(:cover_url) { 'https://f4.bcbits.com/img/a1_10.jpg' }
      before do
        stub_request(:get, cover_url).to_return(status: 500)
        allow(described_class).to receive(:sleep)
      end
      it 'removes the partial file' do
        saved
        expect(File).not_to exist(cover_path)
      end
    end

    context 'when a cover is already on disk' do
      let(:download_info) { { art_id: 12_345 } }
      before do
        File.write(cover_path, 'existing')
        stub_request(:get, cover_url).to_return(body: 'replacement')
      end
      it 'does not overwrite it' do
        saved
        expect(File.read(cover_path)).to eq('existing')
      end
    end

    context 'when the download raises' do
      let(:download_info) { { art_id: 12_345 } }
      before { stub_request(:get, cover_url).to_raise(StandardError) }
      it 'swallows the error' do
        expect { saved }.not_to raise_error
      end
    end
  end

  describe '.extract_zip' do
    include_context 'with a temporary directory'

    subject(:extracted) { described_class.extract_zip(zip_path, dest, **extra) }

    let(:extra) { {} }
    let(:zip_path) { File.join(dest, 'album.zip') }

    def write_zip(entries)
      Zip::File.open(zip_path, create: true) do |zip|
        entries.each { |name, body| zip.get_output_stream(name) { |f| f.write(body) } }
      end
    end

    context 'with a nested track and cover' do
      before do
        write_zip(
          'Radiohead - Kid A/01 Track.flac' => 'audio',
          'Radiohead - Kid A/cover.jpg' => 'zipcover'
        )
      end
      it { is_expected.to be true }
      it 'flattens the nested path' do
        extracted
        expect(File.read(File.join(dest, '01 Track.flac'))).to eq('audio')
      end
      it 'extracts the cover' do
        extracted
        expect(File.read(File.join(dest, 'cover.jpg'))).to eq('zipcover')
      end
    end

    context 'with dotfile entries' do
      before do
        write_zip(
          'Radiohead - Kid A/01 Track.flac' => 'audio',
          'Radiohead - Kid A/.hidden' => 'skip',
          'Radiohead - Kid A/__MACOSX/._01' => 'skip'
        )
      end
      it 'skips the dotfiles' do
        extracted
        expect(File).not_to exist(File.join(dest, '.hidden'))
      end
      it 'skips the AppleDouble files' do
        extracted
        expect(File).not_to exist(File.join(dest, '._01'))
      end
    end

    context 'with a cover already in the album dir' do
      before do
        File.write(File.join(dest, 'cover.jpg'), 'cdn-cover')
        write_zip('cover.jpg' => 'zipcover', '01.flac' => 'audio')
      end
      it 'keeps the existing cover' do
        extracted
        expect(File.read(File.join(dest, 'cover.jpg'))).to eq('cdn-cover')
      end
      it 'still extracts the tracks' do
        extracted
        expect(File).to exist(File.join(dest, '01.flac'))
      end
    end

    context 'with an unreadable archive' do
      before { File.write(zip_path, 'not a zip') }
      it { is_expected.to be false }
    end

    context 'with CP932 entry names' do
      subject(:extracted) { described_class.extract_zip(zip_path, album_dir) }
      let(:album_dir) { File.join(dest, '小鬼', 'Linux舟') }
      before do
        FileUtils.mkdir_p(album_dir)
        build_zip(zip_path, [[CP932_TRACK, 'audio'], ['cover.jpg'.b, 'zipcover']])
      end
      it { is_expected.to be true }
      it 'decodes the name' do
        extracted
        expect(File.read(File.join(album_dir, "01 \u30c6\u30b9\u30c8 - \u30b5\u30b0\u30c3\u30ad.flac"))).to eq('audio')
      end
      it 'leaves ASCII names alone' do
        extracted
        expect(File.read(File.join(album_dir, 'cover.jpg'))).to eq('zipcover')
      end
    end

    context 'with bytes that are not valid CP932' do
      subject(:extracted) { described_class.extract_zip(zip_path, album_dir) }
      let(:album_dir) { File.join(dest, "Caf\u00c9", 'Ambiance') }
      before do
        FileUtils.mkdir_p(album_dir)
        build_zip(zip_path, [[CP437_TRACK, 'audio']])
      end
      it 'extracts exactly one file' do
        extracted
        expect(Dir.children(album_dir).length).to eq(1)
      end
      it 'keeps the payload' do
        extracted
        expect(File.read(File.join(album_dir, Dir.children(album_dir).first))).to eq('audio')
      end
    end

    context 'with an explicit entry encoding' do
      subject(:extracted) { described_class.extract_zip(zip_path, album_dir, encoding: 'CP437') }
      let(:album_dir) { File.join(dest, "Caf\u00c9", 'Ambiance') }
      before do
        FileUtils.mkdir_p(album_dir)
        build_zip(zip_path, [[CP437_TRACK, 'audio']])
      end
      it 'honours the requested encoding' do
        extracted
        expect(File.read(File.join(album_dir, "01 Caf\u0398 - Track.mp3"))).to eq('audio')
      end
    end

    context 'with a name that cannot be decoded at all' do
      subject(:extracted) { described_class.extract_zip(zip_path, album_dir, encoding: 'UTF-8') }
      let(:album_dir) { File.join(dest, 'Mystery', 'Album') }
      before do
        FileUtils.mkdir_p(album_dir)
        build_zip(zip_path, [["\x81\x20\xff\xfe broken.flac".b, 'audio']])
      end
      it 'extracts exactly one file' do
        extracted
        expect(Dir.children(album_dir).length).to eq(1)
      end
      it 'keeps the file extension' do
        extracted
        expect(Dir.children(album_dir).first).to end_with('.flac')
      end
      it 'keeps the payload' do
        extracted
        expect(File.read(File.join(album_dir, Dir.children(album_dir).first))).to eq('audio')
      end
    end

    context 'with reserved characters in a name' do
      subject(:extracted) { described_class.extract_zip(zip_path, album_dir) }
      let(:album_dir) { File.join(dest, 'Artist', 'Album') }
      before do
        FileUtils.mkdir_p(album_dir)
        build_zip(zip_path, [['we:ird|name.flac'.b, 'audio']])
      end
      it 'scrubs them' do
        extracted
        expect(Dir.children(album_dir)).to eq(['we_ird_name.flac'])
      end
    end

    context 'with a traversing entry name' do
      subject(:extracted) { described_class.extract_zip(zip_path, album_dir) }
      let(:album_dir) { File.join(dest, 'Artist', 'Album') }
      before do
        FileUtils.mkdir_p(album_dir)
        build_zip(zip_path, [['../../escaped.flac'.b, 'audio']])
      end
      it 'writes the entry inside the album dir' do
        extracted
        expect(File.read(File.join(album_dir, 'escaped.flac'))).to eq('audio')
      end
      it 'does not write outside the album dir' do
        extracted
        expect(File).not_to exist(File.join(dest, 'escaped.flac'))
      end
    end
  end

  describe '.entry_basename' do
    subject(:basename) { described_class.entry_basename(name, *args) }

    let(:args) { [] }

    context 'with valid UTF-8' do
      let(:name) { '01 トラック.flac'.b }
      it { is_expected.to eq('01 トラック.flac') }
    end

    context 'with CP932 bytes and no encoding' do
      let(:name) { CP932_TRACK }
      it { is_expected.to eq("01 \u30c6\u30b9\u30c8 - \u30b5\u30b0\u30c3\u30ad.flac") }
    end

    context 'with an unusable named encoding' do
      let(:name) { CP932_TRACK }
      let(:args) { ['NOPE-8'] }
      it 'scrubs rather than raising' do
        expect(basename).to be_valid_encoding
      end
      it 'keeps the extension' do
        expect(basename).to end_with('.flac')
      end
    end

    context 'with only separators' do
      let(:name) { '/.././/' }
      it { is_expected.to be_nil }
    end
  end

  describe '.place_download' do
    include_context 'with a temporary directory'

    subject(:placed) { described_class.place_download(file, album_dir, **extra) }

    let(:extra) { {} }
    let(:album_dir) { File.join(dest, 'Kid A') }
    let(:file) { tmp_file('download.flac') }

    def tmp_file(name)
      dir = File.join(dest, 'tmp')
      FileUtils.mkdir_p(dir)
      File.join(dir, name)
    end

    def write_zip_at(path)
      Zip::File.open(path, create: true) do |zip|
        zip.get_output_stream('01 Track.flac') { |f| f.write('audio') }
      end
    end

    context 'with a zip behind a .flac extension' do
      before do
        FileUtils.mkdir_p(album_dir)
        write_zip_at(file)
      end
      it { is_expected.to be true }
      it 'extracts the tracks' do
        placed
        expect(File.read(File.join(album_dir, '01 Track.flac'))).to eq('audio')
      end
      it 'removes the temp copy' do
        placed
        expect(File).not_to exist(file)
      end
    end

    context 'with a raw audio file' do
      before do
        FileUtils.mkdir_p(album_dir)
        File.write(file, 'FLA-CONTENT')
      end
      it 'copies it verbatim' do
        placed
        expect(File.read(File.join(album_dir, 'download.flac'))).to eq('FLA-CONTENT')
      end
    end

    context 'with a zip and unzip disabled' do
      let(:extra) { { unzip: false } }
      let(:file) { tmp_file('download.zip') }
      before do
        FileUtils.mkdir_p(album_dir)
        write_zip_at(file)
      end
      it 'keeps the archive' do
        placed
        expect(File).to exist(File.join(album_dir, 'Kid A.zip'))
      end
      it 'extracts nothing' do
        placed
        expect(File).not_to exist(File.join(album_dir, '01 Track.flac'))
      end
    end

    context 'when extraction fails' do
      let(:file) { tmp_file('download.zip') }
      before do
        FileUtils.mkdir_p(album_dir)
        write_zip_at(file)
        allow(described_class).to receive(:extract_zip).and_return(false)
      end
      it 'keeps the archive' do
        placed
        expect(File).to exist(File.join(album_dir, 'Kid A.zip'))
      end
      it 'still cleans up the temp dir' do
        placed
        expect(File).not_to exist(File.dirname(file))
      end
    end

    context 'when extraction partially succeeds' do
      let(:file) { tmp_file('download.zip') }
      before do
        FileUtils.mkdir_p(album_dir)
        write_zip_at(file)
        # Extracts one entry, then blows up on a later one.
        allow(described_class).to receive(:extract_zip) do
          File.write(File.join(album_dir, '01 Track.flac'), 'audio')
          false
        end
      end
      it 'keeps the archive' do
        placed
        expect(File).to exist(File.join(album_dir, 'Kid A.zip'))
      end
      it 'keeps the tracks that did extract' do
        placed
        expect(File.read(File.join(album_dir, '01 Track.flac'))).to eq('audio')
      end
    end
  end

  describe '.write_stream' do
    include_context 'with a temporary directory'

    subject(:result) { described_class.write_stream(response, File.join(dest, 'out.flac')) }

    # write_stream's job is to batch up the chunks Net::HTTP yields; the
    # chunking itself is Net::HTTP's. A stubbed HTTP response hands over the
    # whole body as one chunk, so a double is what actually exercises the
    # batching this method exists for.
    def response_yielding(chunks)
      double('response').tap do |resp|
        allow(resp).to receive(:read_body) { |&block| chunks.each(&block) }
      end
    end

    context 'with a body smaller than the write buffer' do
      let(:response) { response_yielding(%w[chunk-one- chunk-two- chunk-three]) }
      it { is_expected.to be true }
      it 'writes every chunk in order' do
        result
        expect(File.read(File.join(dest, 'out.flac'))).to eq('chunk-one-chunk-two-chunk-three')
      end
    end

    context 'with a body larger than the write buffer' do
      # 64KB of chunks over a 1MB buffer, so the buffer is flushed 32 times.
      let(:response) { response_yielding(Array.new(64) { 'x' * (16 * 1024) }) }
      let(:expected) { 'x' * (64 * 16 * 1024) }
      it 'reassembles the whole body' do
        result
        expect(File.read(File.join(dest, 'out.flac'))).to eq(expected)
      end
      it 'writes the right number of bytes' do
        result
        expect(File.size(File.join(dest, 'out.flac'))).to eq(expected.bytesize)
      end
    end

    context 'with an empty body' do
      let(:response) { response_yielding([]) }
      it 'creates an empty file' do
        result
        expect(File.size(File.join(dest, 'out.flac'))).to eq(0)
      end
    end
  end

  describe '.download_file' do
    include_context 'with a temporary directory'

    subject(:result) { described_class.download_file(client, url, File.join(dest, 'out.flac'), max_retries: 3) }

    let(:url) { 'https://bcbits.com/track.flac' }
    let(:out) { File.join(dest, 'out.flac') }

    context 'when the server answers directly' do
      before { stub_request(:get, url).to_return(status: 200, body: 'FLA-CONTENT') }
      it { is_expected.to be true }
      it 'writes the body to the destination' do
        result
        expect(File.read(out)).to eq('FLA-CONTENT')
      end
    end

    context 'when the server redirects' do
      let(:final_url) { 'https://final.example/file.flac' }
      before do
        stub_request(:get, url).to_return(status: 302, headers: { 'Location' => final_url })
        stub_request(:get, final_url).to_return(status: 200, body: 'FLA-CONTENT')
      end
      it { is_expected.to be true }
      it 'writes the body from the final hop' do
        result
        expect(File.read(out)).to eq('FLA-CONTENT')
      end
    end

    context 'when the redirect stays on an allowlisted host' do
      let(:final_url) { 'https://d1.bcbits.com/final.zip' }
      before do
        stub_request(:get, url).to_return(status: 302, headers: { 'Location' => final_url })
        stub_request(:get, final_url).to_return(status: 200, body: 'FLA-CONTENT')
      end
      it 'keeps the cookie on the redirect' do
        result
        expect(a_request(:get, final_url).with(headers: { 'Cookie' => 'identity=ident' })).to have_been_made
      end
    end

    context 'when the redirect leaves the allowlist' do
      let(:final_url) { 'https://example.com/file.flac' }
      before do
        stub_request(:get, url).to_return(status: 302, headers: { 'Location' => final_url })
        stub_request(:get, final_url).to_return(status: 200, body: 'FLA-CONTENT')
      end
      it 'drops the cookie on the redirect' do
        result
        expect(a_request(:get, final_url).with { |req| !req.headers.key?('Cookie') }).to have_been_made
      end
    end

    context 'when every attempt fails' do
      before do
        allow(described_class).to receive(:stream_download).and_return(nil)
        allow(described_class).to receive(:sleep)
      end
      it { is_expected.to be false }
      it 'makes one attempt per retry' do
        result
        expect(described_class).to have_received(:stream_download).exactly(3).times
      end
      it 'backs off exponentially' do
        expect(described_class).to receive(:sleep).with(1).ordered
        expect(described_class).to receive(:sleep).with(2).ordered
        expect(described_class).to receive(:sleep).with(4).ordered
        result
      end
    end
  end

  describe '.stream_download' do
    subject(:outcome) { described_class.stream_download(client, url, '/tmp/out') }

    let(:url) { 'https://bcbits.com/file.flac' }

    context 'when the connection fails' do
      before { stub_request(:get, url).to_raise(StandardError, 'connection failed') }
      it { is_expected.to be_nil }
    end

    context 'when the server answers with an error' do
      before { stub_request(:get, url).to_return(status: 500) }
      it { is_expected.to be_nil }
    end
  end

  describe '.download_size' do
    subject(:size) { described_class.download_size(client, url, max_redirects: 5) }

    let(:url) { 'https://bcbits.com/file.flac' }
    let(:ranged) { { headers: { 'Range' => 'bytes=0-0' } } }

    context 'when the server honours the range' do
      before do
        stub_request(:get, url).with(**ranged)
                               .to_return(status: 206, headers: { 'Content-Range' => 'bytes 0-0/12345' }, body: 'x')
      end
      it { is_expected.to eq(12_345) }
    end

    context 'when the server ignores the range' do
      before do
        stub_request(:get, url).with(**ranged)
                               .to_return(status: 200, headers: { 'Content-Length' => '2048' }, body: 'x')
      end
      it { is_expected.to eq(2048) }
    end

    context 'when the server redirects first' do
      let(:final_url) { 'https://final.example/file.flac' }
      before do
        stub_request(:get, url).to_return(status: 302, headers: { 'Location' => final_url })
        stub_request(:get, final_url).with(**ranged)
                                     .to_return(status: 206, headers: { 'Content-Range' => 'bytes 0-0/99' }, body: 'x')
      end
      it { is_expected.to eq(99) }
    end

    context 'when the size-check redirect stays on bcbits' do
      let(:final_url) { 'https://d1.bcbits.com/file.flac' }
      before do
        stub_request(:get, url).to_return(status: 302, headers: { 'Location' => final_url })
        stub_request(:get, final_url).with(**ranged)
                                     .to_return(status: 206, headers: { 'Content-Range' => 'bytes 0-0/99' }, body: 'x')
      end
      it 'keeps the cookie on the redirect' do
        size
        expect(a_request(:get, final_url).with(headers: { 'Cookie' => 'identity=ident' })).to have_been_made
      end
    end

    context 'when the size-check redirect leaves the allowlist' do
      let(:final_url) { 'https://example.com/file.flac' }
      before do
        stub_request(:get, url).to_return(status: 302, headers: { 'Location' => final_url })
        stub_request(:get, final_url).with(**ranged)
                                     .to_return(status: 206, headers: { 'Content-Range' => 'bytes 0-0/99' }, body: 'x')
      end
      it 'drops the cookie on the redirect' do
        size
        expect(a_request(:get, final_url).with { |req| !req.headers.key?('Cookie') }).to have_been_made
      end
    end

    context 'when no size header comes back' do
      before { stub_request(:get, url).with(**ranged).to_return(status: 206, body: 'x') }
      it { is_expected.to be_nil }
    end

    context 'when the request fails' do
      before { stub_request(:get, url).with(**ranged).to_raise(StandardError, 'boom') }

      it { is_expected.to be_nil }
    end

    context 'when the redirect never ends' do
      before do
        stub_request(:get, url).to_return(status: 302, headers: { 'Location' => 'https://other.example/f' })
        stub_request(:get, 'https://other.example/f')
          .to_return(status: 302, headers: { 'Location' => 'https://elsewhere.example/f' })
      end

      it 'gives up once the budget is spent' do
        expect(described_class.download_size(client, url, max_redirects: 2)).to be_nil
      end
    end
  end
end
