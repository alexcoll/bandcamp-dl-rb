# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe BandcampToPlex::CookieExtractor::CookiesFile do
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

RSpec.describe BandcampToPlex::CookieExtractor::Firefox do
  describe '.profile_dir' do
    after { stub_const('RUBY_PLATFORM', RUBY_PLATFORM) }

    it 'uses the macOS Application Support path on darwin' do
      stub_const('RUBY_PLATFORM', 'arm64-darwin23')
      allow(Dir).to receive(:home).and_return('/Users/test')
      expect(described_class.profile_dir)
        .to eq('/Users/test/Library/Application Support/Firefox/Profiles')
    end

    it 'uses APPDATA on Windows' do
      stub_const('RUBY_PLATFORM', 'x64-mingw32')
      allow(ENV).to receive(:[]).with('APPDATA').and_return('C:/Users/Test/AppData/Roaming')
      expect(described_class.profile_dir)
        .to eq('C:/Users/Test/AppData/Roaming/Mozilla/Firefox/Profiles')
    end

    it 'uses ~/.mozilla/firefox on Linux and other platforms' do
      stub_const('RUBY_PLATFORM', 'x86_64-linux')
      allow(Dir).to receive(:home).and_return('/home/test')
      expect(described_class.profile_dir).to eq('/home/test/.mozilla/firefox')
    end
  end

  describe '.find' do
    it 'returns the identity cookie value from a profile cookies.sqlite' do
      profile_dir = File.join(Dir.tmpdir, "ff_profiles_#{Process.pid}")
      FileUtils.mkdir_p(profile_dir)
      profile = File.join(profile_dir, 'abc.default-release')
      FileUtils.mkdir_p(profile)

      db = SQLite3::Database.new(File.join(profile, described_class::COOKIE_DB))
      db.execute_batch <<~SQL
        CREATE TABLE moz_cookies (
          name TEXT, value TEXT, baseDomain TEXT
        );
        INSERT INTO moz_cookies (name, value, baseDomain)
          VALUES ('identity', 'FF-VALUE-123', 'bandcamp.com');
      SQL
      db.close

      expect(described_class.find(profile_dir)).to eq('FF-VALUE-123')
    ensure
      FileUtils.rm_rf(profile_dir) if profile_dir && Dir.exist?(profile_dir)
    end

    it 'returns nil when no profile has an identity cookie' do
      empty_dir = File.join(Dir.tmpdir, "ff_empty_#{Process.pid}")
      FileUtils.mkdir_p(empty_dir)
      expect(described_class.find(empty_dir)).to be_nil
    ensure
      FileUtils.rm_rf(empty_dir) if empty_dir && Dir.exist?(empty_dir)
    end
  end
end

RSpec.describe BandcampToPlex::CookieExtractor::Chrome do
  describe '.local_state_path' do
    after { stub_const('RUBY_PLATFORM', RUBY_PLATFORM) }

    it 'uses the macOS Application Support path on darwin' do
      stub_const('RUBY_PLATFORM', 'arm64-darwin23')
      allow(Dir).to receive(:home).and_return('/Users/test')
      expect(described_class.local_state_path)
        .to eq('/Users/test/Library/Application Support/Google/Chrome/Local State')
    end

    it 'uses LOCALAPPDATA on Windows' do
      stub_const('RUBY_PLATFORM', 'x64-mingw32')
      allow(ENV).to receive(:[]).with('LOCALAPPDATA').and_return('C:/Users/Test/AppData/Local')
      expect(described_class.local_state_path)
        .to eq('C:/Users/Test/AppData/Local/Google/Chrome/User Data/Local State')
    end

    it 'uses ~/.config/google-chrome on Linux' do
      stub_const('RUBY_PLATFORM', 'x86_64-linux')
      allow(Dir).to receive(:home).and_return('/home/test')
      expect(described_class.local_state_path)
        .to eq('/home/test/.config/google-chrome/Local State')
    end
  end

  describe '.cookie_db_paths' do
    after { stub_const('RUBY_PLATFORM', RUBY_PLATFORM) }

    it 'lists the macOS Chrome cookie DBs' do
      stub_const('RUBY_PLATFORM', 'arm64-darwin23')
      allow(Dir).to receive(:home).and_return('/Users/test')
      paths = described_class.cookie_db_paths
      expect(paths).to include('/Users/test/Library/Application Support/Google/Chrome/Default/Network/Cookies')
      expect(paths).to include('/Users/test/Library/Application Support/Google/Chrome/Default/Cookies')
    end

    it 'lists the Windows Chrome cookie DBs under LOCALAPPDATA' do
      stub_const('RUBY_PLATFORM', 'x64-mingw32')
      allow(ENV).to receive(:[]).with('LOCALAPPDATA').and_return('C:/Users/Test/AppData/Local')
      paths = described_class.cookie_db_paths
      expect(paths).to include('C:/Users/Test/AppData/Local/Google/Chrome/User Data/Default/Network/Cookies')
    end

    it 'lists the Linux Chrome cookie DBs' do
      stub_const('RUBY_PLATFORM', 'x86_64-linux')
      allow(Dir).to receive(:home).and_return('/home/test')
      paths = described_class.cookie_db_paths
      expect(paths).to include('/home/test/.config/google-chrome/Default/Network/Cookies')
    end
  end

  describe '.decrypt' do
    let(:key) { '0123456789abcdef' }

    it 'decrypts a v10-encrypted cookie value' do
      plaintext = 'identity-cookie-123'
      cipher = OpenSSL::Cipher.new('aes-128-cbc')
      cipher.encrypt
      cipher.key = key
      cipher.iv = "\x20" * 16
      encrypted = "v10#{cipher.update(plaintext) + cipher.final}"

      expect(described_class.decrypt(encrypted, key)).to eq(plaintext)
    end

    it 'returns nil for a value without a v10/v11 prefix' do
      expect(described_class.decrypt('not-encrypted', key)).to be_nil
    end

    it 'returns nil when the key or value is missing' do
      expect(described_class.decrypt(nil, key)).to be_nil
      expect(described_class.decrypt("v10\x01\x02", nil)).to be_nil
    end
  end

  describe '.find' do
    let(:key) { '0123456789abcdef' }

    it 'reads and decrypts the identity cookie from a Chrome cookie DB' do
      plaintext = 'CHROME-IDENTITY-456'

      cipher = OpenSSL::Cipher.new('aes-128-cbc')
      cipher.encrypt
      cipher.key = key
      cipher.iv = "\x20" * 16
      encrypted = "v10#{cipher.update(plaintext) + cipher.final}"

      cookie_db = File.join(Dir.tmpdir, "chrome_cookies_#{Process.pid}.sqlite")
      db = SQLite3::Database.new(cookie_db)
      db.execute_batch <<~SQL
        CREATE TABLE cookies (
          name TEXT, value TEXT, host_key TEXT, encrypted_value BLOB
        );
      SQL
      db.execute(
        "INSERT INTO cookies (name, host_key, encrypted_value) VALUES ('identity', '.bandcamp.com', ?)",
        [encrypted]
      )
      db.close

      expect(described_class.find(cookie_db, key)).to eq(plaintext)
    ensure
      FileUtils.rm_f(cookie_db) if cookie_db && File.exist?(cookie_db)
    end

    it 'returns nil when no identity cookie exists' do
      empty_db = File.join(Dir.tmpdir, "chrome_empty_#{Process.pid}.sqlite")
      db = SQLite3::Database.new(empty_db)
      db.execute_batch <<~SQL
        CREATE TABLE cookies (
          name TEXT, value TEXT, host_key TEXT, encrypted_value BLOB
        );
      SQL
      db.close

      expect(described_class.find(empty_db, key)).to be_nil
    ensure
      FileUtils.rm_f(empty_db) if empty_db && File.exist?(empty_db)
    end
  end
end

RSpec.describe BandcampToPlex::CookieExtractor::Safari do
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

    it 'points at the default macOS cookies file under the home Library/Cookies dir' do
      allow(Dir).to receive(:home).and_return('/Users/test')
      expect(described_class.cookies_path)
        .to eq('/Users/test/Library/Cookies/Cookies.binarycookies')
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

RSpec.describe BandcampToPlex::CookieExtractor do
  describe '.get_identity_cookie' do
    it 'reads the raw identity cookie value from --cookie-file' do
      expect(described_class.get_identity_cookie('auto', 'my-raw-cookie')).to eq('my-raw-cookie')
    end

    it 'reads the cookie from Chrome when browser is set to chrome' do
      allow(BandcampToPlex::CookieExtractor::Chrome).to receive(:find).and_return('chrome-cookie')
      expect(described_class.get_identity_cookie('chrome')).to eq('chrome-cookie')
    end

    it 'reads the cookie from Firefox when browser is set to firefox' do
      allow(BandcampToPlex::CookieExtractor::Firefox).to receive(:find).and_return('ff-cookie')
      expect(described_class.get_identity_cookie('firefox')).to eq('ff-cookie')
    end

    it 'reads the cookie from Safari when browser is set to safari' do
      allow(BandcampToPlex::CookieExtractor::Safari).to receive(:find).and_return('safari-cookie')
      expect(described_class.get_identity_cookie('safari')).to eq('safari-cookie')
    end

    it 'tries Firefox then Safari then Chrome in auto mode' do
      allow(BandcampToPlex::CookieExtractor::Firefox).to receive(:find).and_return(nil)
      allow(BandcampToPlex::CookieExtractor::Safari).to receive(:find).and_return(nil)
      allow(BandcampToPlex::CookieExtractor::Chrome).to receive(:find).and_return('chrome-cookie')
      expect(described_class.get_identity_cookie('auto')).to eq('chrome-cookie')
    end

    it 'returns nil when no cookie source succeeds' do
      allow(BandcampToPlex::CookieExtractor::Firefox).to receive(:find).and_return(nil)
      allow(BandcampToPlex::CookieExtractor::Safari).to receive(:find).and_return(nil)
      allow(BandcampToPlex::CookieExtractor::Chrome).to receive(:find).and_return(nil)
      expect(described_class.get_identity_cookie('auto')).to be_nil
    end
  end
end
