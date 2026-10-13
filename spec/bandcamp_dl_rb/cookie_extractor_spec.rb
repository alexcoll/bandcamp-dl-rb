# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe BandcampDlRb::CookieExtractor::CookiesFile do
  describe '.load_from' do
    it 'parses a Netscape cookies.txt file and returns the identity cookie value' do
      content = <<~TXT
        # Netscape HTTP Cookie File
        .bandcamp.com	TRUE	/	TRUE	2000000000	identity	abc123XYZ
        .bandcamp.com	TRUE	/	FALSE	2000000000	other	ignoreme
      TXT
      file = Tempfile.new('cookies')
      file.write(content)
      file.close

      expect(described_class.load_from(file.path)).to eq('abc123XYZ')
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

      expect(described_class.load_from(file.path)).to be_nil
    ensure
      file.unlink
    end

    it 'returns nil when the file is empty' do
      file = Tempfile.new('cookies')
      file.close

      expect(described_class.load_from(file.path)).to be_nil
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

      expect(described_class.load_from(file.path)).to eq('val42')
    ensure
      file.unlink
    end
  end
end

RSpec.describe BandcampDlRb::CookieExtractor::TempCopy do
  describe '.create' do
    it 'writes a 0600 copy inside a 0700 temp dir' do
      src = File.join(Dir.tmpdir, "temp_copy_src_#{Process.pid}.sqlite")
      File.binwrite(src, "\x00cookie db")
      dir = described_class.create(src, 'bc_temp_copy_')

      file = File.join(dir, described_class::FILE_NAME)
      expect(File.stat(dir).mode & 0o777).to eq(0o700)
      expect(File.stat(file).mode & 0o777).to eq(0o600)
      expect(File.binread(file)).to eq("\x00cookie db")
    ensure
      described_class.cleanup(dir) if dir
      FileUtils.rm_f(src) if src && File.exist?(src)
    end

    it 'creates the copy in Dir.tmpdir with the given prefix' do
      src = File.join(Dir.tmpdir, "temp_copy_src2_#{Process.pid}.sqlite")
      File.binwrite(src, 'data')
      dir = described_class.create(src, 'bc_temp_copy_')

      expect(File.dirname(dir)).to eq(Dir.tmpdir)
      expect(File.basename(dir)).to start_with('bc_temp_copy_')
    ensure
      described_class.cleanup(dir) if dir
      FileUtils.rm_f(src) if src && File.exist?(src)
    end
  end

  describe '.cleanup' do
    it 'removes the temp dir and its copy' do
      src = File.join(Dir.tmpdir, "temp_copy_src3_#{Process.pid}.sqlite")
      File.binwrite(src, 'data')
      dir = described_class.create(src, 'bc_temp_copy_')

      described_class.cleanup(dir)

      expect(Dir.exist?(dir)).to be(false)
      expect(Dir.glob(File.join(Dir.tmpdir, 'bc_temp_copy_*'))).to be_empty
    ensure
      FileUtils.rm_f(src) if src && File.exist?(src)
    end
  end
end

RSpec.describe BandcampDlRb::CookieExtractor::Firefox do
  describe '.profile_dir' do
    after { stub_const('RUBY_PLATFORM', RUBY_PLATFORM) }

    it 'uses the macOS Application Support path on darwin' do
      stub_const('RUBY_PLATFORM', 'arm64-darwin23')
      allow(Dir).to receive(:home).and_return('/Users/test')
      expect(described_class.profile_dir)
        .to eq('/Users/test/Library/Application Support/Firefox/Profiles')
    end

    it 'uses ~/.mozilla/firefox on Linux and other platforms' do
      stub_const('RUBY_PLATFORM', 'x86_64-linux')
      allow(Dir).to receive(:home).and_return('/home/test')
      expect(described_class.profile_dir).to eq('/home/test/.mozilla/firefox')
    end
  end

  describe '.find' do
    let(:profile_dir) { File.join(Dir.tmpdir, "ff_profiles_#{Process.pid}") }

    def build_firefox_profile(profile_dir, profile_name)
      profile = File.join(profile_dir, profile_name)
      FileUtils.mkdir_p(profile)
      db = SQLite3::Database.new(File.join(profile, described_class::COOKIE_DB))
      db.execute_batch <<~SQL
        CREATE TABLE moz_cookies (
          name TEXT, value TEXT, host TEXT
        );
      SQL
      db
    end

    def insert_cookie(db, name:, value:, host:)
      db.execute('INSERT INTO moz_cookies (name, value, host) VALUES (?, ?, ?)',
                 [name, value, host])
    end

    after { FileUtils.rm_rf(profile_dir) if profile_dir && Dir.exist?(profile_dir) }

    it 'returns the identity cookie value from a profile cookies.sqlite' do
      db = build_firefox_profile(profile_dir, 'abc.default-release')
      insert_cookie(db, name: 'identity', value: 'FF-VALUE-123', host: '.bandcamp.com')
      db.close

      expect(described_class.find(profile_dir)).to eq('FF-VALUE-123')
    end

    it 'searches multiple profiles and uses the first one with an identity cookie' do
      first = build_firefox_profile(profile_dir, 'one.default')
      insert_cookie(first, name: 'session', value: 'x', host: '.example.com')
      first.close

      second = build_firefox_profile(profile_dir, 'two.default-release')
      insert_cookie(second, name: 'identity', value: 'FF-VALUE-456', host: '.bandcamp.com')
      second.close

      expect(described_class.find(profile_dir)).to eq('FF-VALUE-456')
    end

    it 'ignores identity cookies on hosts other than bandcamp.com' do
      db = build_firefox_profile(profile_dir, 'abc.default-release')
      insert_cookie(db, name: 'identity', value: 'OTHER-SITE', host: '.example.com')
      db.close

      expect(described_class.find(profile_dir)).to be_nil
    end

    it 'returns nil when no profile has an identity cookie' do
      FileUtils.mkdir_p(profile_dir)
      expect(described_class.find(profile_dir)).to be_nil
    end

    it 'removes its private temp copy after a successful find' do
      db = build_firefox_profile(profile_dir, 'abc.default-release')
      insert_cookie(db, name: 'identity', value: 'FF-VALUE-123', host: '.bandcamp.com')
      db.close

      stale = Dir.glob(File.join(Dir.tmpdir, 'bc_*'))
      described_class.find(profile_dir)
      expect(Dir.glob(File.join(Dir.tmpdir, 'bc_*'))).to contain_exactly(*stale)
    end

    it 'removes its private temp copy after an error' do
      broken_profile = File.join(profile_dir, 'broken.default')
      FileUtils.mkdir_p(broken_profile)
      File.binwrite(File.join(broken_profile, described_class::COOKIE_DB), 'not a sqlite db')

      stale = Dir.glob(File.join(Dir.tmpdir, 'bc_*'))
      expect(described_class.find(profile_dir)).to be_nil
      expect(Dir.glob(File.join(Dir.tmpdir, 'bc_*'))).to contain_exactly(*stale)
    end
  end
end

RSpec.describe BandcampDlRb::CookieExtractor::Safari do
  # Builds a minimal but byte-correct Cookies.binarycookies payload.
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

  def build_file(cookies, page_offset: 12)
    page = "\x00\x00\x01\x00".b + [cookies.length].pack('V')
    page += cookie_offsets(cookies).map { |o| [o].pack('V') }.join
    page += cookies.join

    'cook'.b + [1].pack('N') + [page_offset].pack('N') + page
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
    after { allow(Dir).to receive(:home).and_return(Dir.home) }

    it 'prefers the sandboxed container path when it exists (macOS Monterey+)' do
      allow(Dir).to receive(:home).and_return('/Users/test')
      modern = '/Users/test/Library/Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies'
      legacy = '/Users/test/Library/Cookies/Cookies.binarycookies'
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with(modern).and_return(true)
      allow(File).to receive(:exist?).with(legacy).and_return(false)
      expect(described_class.cookies_path).to eq(modern)
    end

    it 'falls back to the legacy Library/Cookies path otherwise' do
      allow(Dir).to receive(:home).and_return('/Users/test')
      modern = '/Users/test/Library/Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies'
      legacy = '/Users/test/Library/Cookies/Cookies.binarycookies'
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with(modern).and_return(false)
      allow(File).to receive(:exist?).with(legacy).and_return(false)
      expect(described_class.cookies_path).to eq(legacy)
    end
  end

  describe '.find' do
    it 'reads the identity cookie from a Cookies.binarycookies file' do
      file = File.join(Dir.tmpdir, "safari_#{Process.pid}.binarycookies")
      File.write(file, build_file([build_cookie('https://bandcamp.com', 'identity', 'SAFARI-IDENTITY')]))

      expect(described_class.find(file)).to eq('SAFARI-IDENTITY')
    ensure
      FileUtils.rm_f(file)
    end

    it 'returns nil when the file does not exist' do
      expect(described_class.find('/nonexistent/binarycookies')).to be_nil
    end

    it 'returns nil when no identity cookie is present' do
      file = File.join(Dir.tmpdir, "safari_empty_#{Process.pid}.binarycookies")
      File.write(file, build_file([build_cookie('https://example.com', 'session', 'nope')]))

      expect(described_class.find(file)).to be_nil
    ensure
      FileUtils.rm_f(file)
    end
  end

  describe '#parse' do
    it 'returns the identity cookie value for a bandcamp.com identity cookie' do
      data = build_file([build_cookie('https://bandcamp.com', 'identity', 'SAFARI-IDENTITY')])
      expect(described_class.new.parse(data)).to eq('SAFARI-IDENTITY')
    end

    it 'skips cookies that do not target bandcamp.com' do
      data = build_file([build_cookie('https://other.example', 'identity', 'UNUSED')])
      expect(described_class.new.parse(data)).to be_nil
    end

    it 'skips cookies that are not named identity' do
      data = build_file([build_cookie('https://bandcamp.com', 'session', 'UNUSED')])
      expect(described_class.new.parse(data)).to be_nil
    end

    it 'skips cookies before later finds the identity cookie' do
      data = build_file([
                          build_cookie('https://bandcamp.com', 'other', 'UNUSED'),
                          build_cookie('https://bandcamp.com', 'identity', 'SAFARI-IDENTITY')
                        ])
      expect(described_class.new.parse(data)).to eq('SAFARI-IDENTITY')
    end

    it 'returns nil for malformed data' do
      expect(described_class.new.parse('not a cookie file at all')).to be_nil
    end

    it 'returns nil for a nil payload' do
      expect(described_class.new.parse(nil)).to be_nil
    end
  end
end

RSpec.describe BandcampDlRb::CookieExtractor do
  describe '.get_identity_cookie' do
    it 'reads the raw identity cookie value from --cookie-file' do
      expect(described_class.get_identity_cookie('auto', 'my-raw-cookie')).to eq('my-raw-cookie')
    end

    it 'reads the cookie from Firefox when browser is set to firefox' do
      allow(BandcampDlRb::CookieExtractor::Firefox).to receive(:find).and_return('ff-cookie')
      expect(described_class.get_identity_cookie('firefox')).to eq('ff-cookie')
    end

    it 'reads the cookie from Safari when browser is set to safari' do
      allow(BandcampDlRb::CookieExtractor::Safari).to receive(:find).and_return('safari-cookie')
      expect(described_class.get_identity_cookie('safari')).to eq('safari-cookie')
    end

    it 'tries Firefox then Safari in auto mode' do
      allow(BandcampDlRb::CookieExtractor::Firefox).to receive(:find).and_return(nil)
      allow(BandcampDlRb::CookieExtractor::Safari).to receive(:find).and_return('safari-cookie')
      expect(described_class.get_identity_cookie('auto')).to eq('safari-cookie')
    end

    it 'returns nil when no cookie source succeeds' do
      allow(BandcampDlRb::CookieExtractor::Firefox).to receive(:find).and_return(nil)
      allow(BandcampDlRb::CookieExtractor::Safari).to receive(:find).and_return(nil)
      expect(described_class.get_identity_cookie('auto')).to be_nil
    end
  end
end
