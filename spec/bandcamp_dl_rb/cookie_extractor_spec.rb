# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe BandcampDlRb::CookieExtractor::CookiesFile do
  include_context 'with a cookie file'

  describe '.load_from' do
    subject(:identity) { described_class.load_from(cookie_file.path) }

    context 'with an identity cookie' do
      let(:cookie_lines) { [BandcampFixtures.cookie_line('identity', 'abc123XYZ')] }

      it 'returns the cookie value' do
        expect(identity).to eq('abc123XYZ')
      end
    end

    context 'with other cookies alongside' do
      let(:cookie_lines) do
        [
          BandcampFixtures.cookie_line('identity', 'abc123XYZ'),
          BandcampFixtures.cookie_line('other', 'ignoreme')
        ]
      end

      it 'still finds the identity cookie' do
        expect(identity).to eq('abc123XYZ')
      end
    end

    context 'with comments and blank lines' do
      let(:cookie_lines) do
        ['# Netscape HTTP Cookie File', '', BandcampFixtures.cookie_line('identity', 'val42')]
      end

      it 'skips them' do
        expect(identity).to eq('val42')
      end
    end

    context 'without an identity cookie' do
      let(:cookie_lines) { [BandcampFixtures.cookie_line('session', 'x')] }

      it { is_expected.to be_nil }
    end

    context 'with an identity cookie on another host' do
      let(:cookie_lines) { [BandcampFixtures.cookie_line('identity', 'other-site', host: '.example.com')] }

      it { is_expected.to be_nil }
    end

    context 'with an empty file' do
      let(:cookie_lines) { [] }

      it { is_expected.to be_nil }
    end

    context 'when the file does not exist' do
      subject(:identity) { described_class.load_from('/nonexistent/cookies.txt') }

      it { is_expected.to be_nil }
    end
  end
end

RSpec.describe BandcampDlRb::CookieExtractor::TempCopy do
  describe '.create' do
    subject(:copy_dir) { described_class.create(src, 'bc_temp_copy_') }

    let(:src) { File.join(Dir.tmpdir, "temp_copy_src_#{Process.pid}.sqlite") }

    before { File.binwrite(src, "\x00cookie db") }

    after do
      FileUtils.rm_f(src)
      described_class.cleanup(copy_dir)
      described_class.cleanup(copy_dir)
    end

    it 'copies the bytes' do
      expect(File.binread(File.join(copy_dir, described_class::FILE_NAME))).to eq("\x00cookie db")
    end

    it 'locks the dir to 0700' do
      expect(File.stat(copy_dir).mode & 0o777).to eq(0o700)
    end

    it 'locks the copy to 0600' do
      expect(File.stat(File.join(copy_dir, described_class::FILE_NAME)).mode & 0o777).to eq(0o600)
    end

    it 'uses the given prefix under Dir.tmpdir' do
      expect(File.basename(copy_dir)).to start_with('bc_temp_copy_')
    end
  end

  describe '.cleanup' do
    subject(:removed) { described_class.cleanup(dir) }

    let(:dir) { described_class.create(src, 'bc_temp_copy_') }
    let(:src) { File.join(Dir.tmpdir, "temp_copy_src3_#{Process.pid}.sqlite") }

    before { File.binwrite(src, 'data') }

    after { FileUtils.rm_f(src) }

    it 'removes the directory' do
      removed
      expect(Dir.exist?(dir)).to be false
    end

    it 'leaves no bc temp dir behind' do
      removed
      expect(Dir.glob(File.join(Dir.tmpdir, 'bc_temp_copy_*'))).to be_empty
    end
  end
end

RSpec.describe BandcampDlRb::CookieExtractor::Firefox do
  include_context 'with a temporary directory'

  describe '.profile_dir' do
    subject(:profile_root) { described_class.profile_dir }

    context 'when running on macOS' do
      before do
        stub_const('RUBY_PLATFORM', 'arm64-darwin23')
        allow(Dir).to receive(:home).and_return('/Users/test')
      end

      it { expect(profile_root).to eq('/Users/test/Library/Application Support/Firefox/Profiles') }
    end

    context 'when running on Linux' do
      before do
        stub_const('RUBY_PLATFORM', 'x86_64-linux')
        allow(Dir).to receive(:home).and_return('/home/test')
      end

      it { expect(profile_root).to eq('/home/test/.mozilla/firefox') }
    end
  end

  describe '.find' do
    subject(:identity) { described_class.find(dest) }

    # A real cookies.sqlite, not a double: the extractor opens the file with
    # sqlite3 and copies it first, so a stubbed DB would not exercise the code
    # that actually runs on a user's machine.
    def build_profile(name)
      profile = File.join(dest, name)
      FileUtils.mkdir_p(profile)
      db = SQLite3::Database.new(File.join(profile, described_class::COOKIE_DB))
      db.execute_batch 'CREATE TABLE moz_cookies (name TEXT, value TEXT, host TEXT);'
      db
    end

    def add_cookie(db, name:, value:, host: '.bandcamp.com')
      db.execute('INSERT INTO moz_cookies (name, value, host) VALUES (?, ?, ?)', [name, value, host])
    end

    context 'with a single profile holding the cookie' do
      it 'returns the value' do
        db = build_profile('abc.default-release')
        add_cookie(db, name: 'identity', value: 'FF-VALUE-123')
        db.close

        expect(identity).to eq('FF-VALUE-123')
      end
    end

    context 'with several profiles' do
      it 'uses the first one holding a cookie' do
        first = build_profile('one.default')
        add_cookie(first, name: 'session', value: 'x', host: '.example.com')
        first.close

        second = build_profile('two.default-release')
        add_cookie(second, name: 'identity', value: 'FF-VALUE-456')
        second.close

        expect(identity).to eq('FF-VALUE-456')
      end
    end

    context 'with the cookie on another host' do
      it 'ignores it' do
        db = build_profile('abc.default-release')
        add_cookie(db, name: 'identity', value: 'OTHER-SITE', host: '.example.com')
        db.close

        expect(identity).to be_nil
      end
    end

    context 'with no profiles at all' do
      it { is_expected.to be_nil }
    end

    context 'with an unreadable profile' do
      it 'skips it and returns nil' do
        broken = File.join(dest, 'broken.default')
        FileUtils.mkdir_p(broken)
        File.binwrite(File.join(broken, described_class::COOKIE_DB), 'not a sqlite db')

        expect(identity).to be_nil
      end
    end

    context 'with a readable profile' do
      it 'removes its private temp copy' do
        db = build_profile('abc.default-release')
        add_cookie(db, name: 'identity', value: 'FF-VALUE-123')
        db.close
        stale = Dir.glob(File.join(Dir.tmpdir, 'bc_*'))

        identity

        expect(Dir.glob(File.join(Dir.tmpdir, 'bc_*'))).to match_array(stale)
      end
    end

    context 'with a profile it cannot read' do
      it 'removes its private temp copy' do
        broken = File.join(dest, 'broken.default')
        FileUtils.mkdir_p(broken)
        File.binwrite(File.join(broken, described_class::COOKIE_DB), 'not a sqlite db')
        stale = Dir.glob(File.join(Dir.tmpdir, 'bc_*'))

        identity

        expect(Dir.glob(File.join(Dir.tmpdir, 'bc_*'))).to match_array(stale)
      end
    end
  end
end

RSpec.describe BandcampDlRb::CookieExtractor::Safari do
  include_context 'with a temporary directory'

  # Builds a minimal but byte-correct Cookies.binarycookies payload. Safari
  # stores its cookies in this bespoke format, so the parser is only worth
  # testing against real bytes rather than a stand-in.
  def build_cookie(url, name, value)
    parts = [cstring(url), cstring(name), cstring('/'), cstring(value)]
    offsets = string_offsets(parts)
    body = +[offsets.last + parts.last.bytesize].pack('V')
    body += cookie_header(offsets)
    body += parts.join
    body
  end

  def string_offsets(parts)
    positions = [45]
    parts[0..-2].each { |part| positions << (positions.last + part.bytesize) }
    positions
  end

  def cookie_header(offsets)
    result = +[0].pack('V')
    result += "\x00".b + "\x00\x00\x00\x00".b
    result += offsets.map { |o| [o].pack('N') }.join
    result += [0, 0].pack('Q>Q>')
    result
  end

  def cstring(str)
    str.b + "\x00".b
  end

  def build_file(cookies)
    page = "\x00\x00\x01\x00".b + [cookies.length].pack('V')
    page += cookie_offsets(cookies).map { |o| [o].pack('V') }.join
    page += cookies.join

    'cook'.b + [1].pack('N') + [12].pack('N') + page
  end

  def cookie_offsets(cookies)
    position = 8 + (cookies.length * 4)
    cookies.map do |cookie|
      offset = position
      position += cookie.bytesize
      offset
    end
  end

  describe '.cookies_path' do
    subject(:path) { described_class.cookies_path }

    let(:modern) { '/Users/test/Library/Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies' }
    let(:legacy) { '/Users/test/Library/Cookies/Cookies.binarycookies' }

    before do
      allow(Dir).to receive(:home).and_return('/Users/test')
      allow(File).to receive(:exist?).and_call_original
    end

    context 'with the sandbox container present' do
      before do
        allow(File).to receive(:exist?).with(modern).and_return(true)
        allow(File).to receive(:exist?).with(legacy).and_return(false)
      end

      it 'prefers the container path' do
        expect(path).to eq(modern)
      end
    end

    context 'with neither path present' do
      before do
        allow(File).to receive(:exist?).with(modern).and_return(false)
        allow(File).to receive(:exist?).with(legacy).and_return(false)
      end

      it 'falls back to the legacy path' do
        expect(path).to eq(legacy)
      end
    end
  end

  describe '.find' do
    subject(:identity) { described_class.find(path) }

    context 'with an identity cookie in the file' do
      let(:path) { File.join(dest, 'Cookies.binarycookies') }

      before { File.binwrite(path, build_file([build_cookie('https://bandcamp.com', 'identity', 'SAFARI-IDENTITY')])) }

      it { is_expected.to eq('SAFARI-IDENTITY') }
    end

    context 'with no identity cookie in the file' do
      let(:path) { File.join(dest, 'Cookies.binarycookies') }

      before { File.binwrite(path, build_file([build_cookie('https://example.com', 'session', 'nope')])) }

      it { is_expected.to be_nil }
    end

    context 'when the file does not exist' do
      let(:path) { '/nonexistent/Cookies.binarycookies' }

      it { is_expected.to be_nil }
    end

    context 'when the file cannot be read' do
      let(:path) { File.join(dest, 'Cookies.binarycookies') }

      before do
        File.binwrite(path, 'unused')
        allow(File).to receive(:binread).and_call_original
        allow(File).to receive(:binread).with(path).and_raise(StandardError, 'permission denied')
      end

      it { is_expected.to be_nil }
    end
  end

  describe '#parse' do
    subject(:identity) { described_class.new(path).parse(data) }

    let(:path) { File.join(dest, 'Cookies.binarycookies') }

    context 'with a bandcamp identity cookie' do
      let(:data) { build_file([build_cookie('https://bandcamp.com', 'identity', 'SAFARI-IDENTITY')]) }

      it { is_expected.to eq('SAFARI-IDENTITY') }
    end

    context 'with an identity cookie on another host' do
      let(:data) { build_file([build_cookie('https://other.example', 'identity', 'UNUSED')]) }

      it { is_expected.to be_nil }
    end

    context 'with a bandcamp cookie that is not the identity cookie' do
      let(:data) { build_file([build_cookie('https://bandcamp.com', 'session', 'UNUSED')]) }

      it { is_expected.to be_nil }
    end

    context 'with the identity cookie behind another cookie' do
      let(:data) do
        build_file([
                     build_cookie('https://bandcamp.com', 'other', 'UNUSED'),
                     build_cookie('https://bandcamp.com', 'identity', 'SAFARI-IDENTITY')
                   ])
      end

      it { is_expected.to eq('SAFARI-IDENTITY') }
    end

    context 'with malformed bytes' do
      let(:data) { 'not a cookie file at all' }

      it { is_expected.to be_nil }
    end

    context 'with a nil payload' do
      let(:data) { nil }

      it { is_expected.to be_nil }
    end
  end
end

RSpec.describe BandcampDlRb::CookieExtractor do
  include_context 'with a temporary directory'

  describe '.get_identity_cookie' do
    subject(:identity) { described_class.get_identity_cookie(browser, cookie_file) }

    let(:browser) { 'auto' }
    let(:cookie_file) { nil }

    context 'with a raw cookie value' do
      let(:cookie_file) { 'my-raw-cookie' }

      it 'uses it verbatim' do
        expect(identity).to eq('my-raw-cookie')
      end
    end

    context 'with a cookies.txt file' do
      let(:cookie_file) { File.join(dest, 'cookies.txt') }
      let(:lines) { [BandcampFixtures.cookie_line('identity', 'file-cookie-value')] }

      before { File.write(cookie_file, "#{lines.join("\n")}\n") }

      it 'reads the identity cookie' do
        expect(identity).to eq('file-cookie-value')
      end
    end

    context 'with a cookies.txt file holding no identity cookie' do
      let(:cookie_file) { File.join(dest, 'cookies.txt') }

      before { File.write(cookie_file, "#{BandcampFixtures.cookie_line('session', 'v')}\n") }

      it 'answers nil' do
        expect(identity).to be_nil
      end
    end

    context 'with a cookie file that does not exist' do
      let(:cookie_file) { '/nonexistent/cookies.txt' }

      it 'answers nil' do
        expect(identity).to be_nil
      end
    end

    context 'with browser set to firefox' do
      let(:browser) { 'firefox' }

      it 'reads the cookie from firefox' do
        allow(BandcampDlRb::CookieExtractor::Firefox).to receive(:find).and_return('ff-cookie')
        expect(identity).to eq('ff-cookie')
      end
    end

    context 'with browser set to safari' do
      let(:browser) { 'safari' }

      it 'reads the cookie from safari' do
        allow(BandcampDlRb::CookieExtractor::Safari).to receive(:find).and_return('safari-cookie')
        expect(identity).to eq('safari-cookie')
      end
    end

    context 'with an unrecognised browser' do
      let(:browser) { 'netscape' }

      it 'answers nil rather than searching' do
        expect(identity).to be_nil
      end
    end

    context 'with browser set to auto' do
      before do
        allow(BandcampDlRb::CookieExtractor::Firefox).to receive(:find).and_return(firefox_cookie)
        allow(BandcampDlRb::CookieExtractor::Safari).to receive(:find).and_return(safari_cookie)
      end

      let(:firefox_cookie) { nil }
      let(:safari_cookie) { nil }

      context 'when Firefox has the cookie' do
        let(:firefox_cookie) { 'ff-cookie' }

        it 'takes the Firefox cookie' do
          expect(identity).to eq('ff-cookie')
        end

        it 'does not ask Safari' do
          identity
          expect(BandcampDlRb::CookieExtractor::Safari).not_to have_received(:find)
        end
      end

      context 'when only Safari has the cookie' do
        let(:safari_cookie) { 'safari-cookie' }

        it 'falls through to the Safari cookie' do
          expect(identity).to eq('safari-cookie')
        end
      end

      context 'when neither browser has the cookie' do
        it 'answers nil' do
          expect(identity).to be_nil
        end
      end
    end
  end
end
