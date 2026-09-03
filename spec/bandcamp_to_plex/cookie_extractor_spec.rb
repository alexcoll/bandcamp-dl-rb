# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe BandcampToPlex::CookieExtractor do
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

  describe '.get_identity_cookie' do
    it 'reads the raw identity cookie value from --cookie-file' do
      expect(described_class.get_identity_cookie('auto', 'my-raw-cookie')).to eq('my-raw-cookie')
    end

    it 'reads the cookie from Chrome when browser is set to chrome' do
      allow(described_class).to receive(:find_chrome_cookies).and_return('chrome-cookie')
      expect(described_class.get_identity_cookie('chrome')).to eq('chrome-cookie')
    end

    it 'reads the cookie from Firefox when browser is set to firefox' do
      allow(described_class).to receive(:find_firefox_cookies).and_return('ff-cookie')
      expect(described_class.get_identity_cookie('firefox')).to eq('ff-cookie')
    end

    it 'tries Firefox then Chrome in auto mode' do
      allow(described_class).to receive(:find_firefox_cookies).and_return(nil)
      allow(described_class).to receive(:find_chrome_cookies).and_return('chrome-cookie')
      expect(described_class.get_identity_cookie('auto')).to eq('chrome-cookie')
    end

    it 'returns nil when no cookie source succeeds' do
      allow(described_class).to receive(:find_firefox_cookies).and_return(nil)
      allow(described_class).to receive(:find_chrome_cookies).and_return(nil)
      expect(described_class.get_identity_cookie('auto')).to be_nil
    end
  end

  describe '.firefox_profile_dir' do
    after { stub_const('RUBY_PLATFORM', RUBY_PLATFORM) }

    it 'uses the macOS Application Support path on darwin' do
      stub_const('RUBY_PLATFORM', 'arm64-darwin23')
      allow(Dir).to receive(:home).and_return('/Users/test')
      expect(described_class.firefox_profile_dir)
        .to eq('/Users/test/Library/Application Support/Firefox/Profiles')
    end

    it 'uses APPDATA on Windows' do
      stub_const('RUBY_PLATFORM', 'x64-mingw32')
      allow(ENV).to receive(:[]).with('APPDATA').and_return('C:/Users/Test/AppData/Roaming')
      expect(described_class.firefox_profile_dir)
        .to eq('C:/Users/Test/AppData/Roaming/Mozilla/Firefox/Profiles')
    end

    it 'uses ~/.mozilla/firefox on Linux and other platforms' do
      stub_const('RUBY_PLATFORM', 'x86_64-linux')
      allow(Dir).to receive(:home).and_return('/home/test')
      expect(described_class.firefox_profile_dir).to eq('/home/test/.mozilla/firefox')
    end
  end

  describe '.find_firefox_cookies' do
    it 'returns the identity cookie value from a profile cookies.sqlite' do
      profile_dir = File.join(Dir.tmpdir, "ff_profiles_#{Process.pid}")
      FileUtils.mkdir_p(profile_dir)
      profile = File.join(profile_dir, 'abc.default-release')
      FileUtils.mkdir_p(profile)

      db = SQLite3::Database.new(File.join(profile, 'cookies.sqlite'))
      db.execute_batch <<~SQL
        CREATE TABLE moz_cookies (
          name TEXT, value TEXT, baseDomain TEXT
        );
        INSERT INTO moz_cookies (name, value, baseDomain)
          VALUES ('identity', 'FF-VALUE-123', 'bandcamp.com');
      SQL
      db.close

      allow(described_class).to receive(:firefox_profile_dir).and_return(profile_dir)
      expect(described_class.find_firefox_cookies).to eq('FF-VALUE-123')
    ensure
      FileUtils.rm_rf(profile_dir) if profile_dir && Dir.exist?(profile_dir)
    end

    it 'returns nil when no profile has an identity cookie' do
      empty_dir = File.join(Dir.tmpdir, "ff_empty_#{Process.pid}")
      FileUtils.mkdir_p(empty_dir)
      allow(described_class).to receive(:firefox_profile_dir).and_return(empty_dir)
      expect(described_class.find_firefox_cookies).to be_nil
    ensure
      FileUtils.rm_rf(empty_dir) if empty_dir && Dir.exist?(empty_dir)
    end
  end

  describe '.chrome_local_state_path' do
    after { stub_const('RUBY_PLATFORM', RUBY_PLATFORM) }

    it 'uses the macOS Application Support path on darwin' do
      stub_const('RUBY_PLATFORM', 'arm64-darwin23')
      allow(Dir).to receive(:home).and_return('/Users/test')
      expect(described_class.chrome_local_state_path)
        .to eq('/Users/test/Library/Application Support/Google/Chrome/Local State')
    end

    it 'uses LOCALAPPDATA on Windows' do
      stub_const('RUBY_PLATFORM', 'x64-mingw32')
      allow(ENV).to receive(:[]).with('LOCALAPPDATA').and_return('C:/Users/Test/AppData/Local')
      expect(described_class.chrome_local_state_path)
        .to eq('C:/Users/Test/AppData/Local/Google/Chrome/User Data/Local State')
    end

    it 'uses ~/.config/google-chrome on Linux' do
      stub_const('RUBY_PLATFORM', 'x86_64-linux')
      allow(Dir).to receive(:home).and_return('/home/test')
      expect(described_class.chrome_local_state_path)
        .to eq('/home/test/.config/google-chrome/Local State')
    end
  end

  describe '.chrome_cookie_db_paths' do
    after { stub_const('RUBY_PLATFORM', RUBY_PLATFORM) }

    it 'lists the macOS Chrome cookie DBs' do
      stub_const('RUBY_PLATFORM', 'arm64-darwin23')
      allow(Dir).to receive(:home).and_return('/Users/test')
      paths = described_class.chrome_cookie_db_paths
      expect(paths).to include('/Users/test/Library/Application Support/Google/Chrome/Default/Network/Cookies')
      expect(paths).to include('/Users/test/Library/Application Support/Google/Chrome/Default/Cookies')
    end

    it 'lists the Windows Chrome cookie DBs under LOCALAPPDATA' do
      stub_const('RUBY_PLATFORM', 'x64-mingw32')
      allow(ENV).to receive(:[]).with('LOCALAPPDATA').and_return('C:/Users/Test/AppData/Local')
      paths = described_class.chrome_cookie_db_paths
      expect(paths).to include('C:/Users/Test/AppData/Local/Google/Chrome/User Data/Default/Network/Cookies')
    end

    it 'lists the Linux Chrome cookie DBs' do
      stub_const('RUBY_PLATFORM', 'x86_64-linux')
      allow(Dir).to receive(:home).and_return('/home/test')
      paths = described_class.chrome_cookie_db_paths
      expect(paths).to include('/home/test/.config/google-chrome/Default/Network/Cookies')
    end
  end

  describe '.decrypt_chrome_value' do
    let(:key) { '0123456789abcdef' }

    it 'decrypts a v10-encrypted cookie value' do
      plaintext = 'identity-cookie-123'
      cipher = OpenSSL::Cipher.new('aes-128-cbc')
      cipher.encrypt
      cipher.key = key
      cipher.iv = "\x20" * 16
      encrypted = "v10#{cipher.update(plaintext) + cipher.final}"

      expect(described_class.decrypt_chrome_value(encrypted, key)).to eq(plaintext)
    end

    it 'returns nil for a value without a v10/v11 prefix' do
      expect(described_class.decrypt_chrome_value('not-encrypted', key)).to be_nil
    end

    it 'returns nil when the key or value is missing' do
      expect(described_class.decrypt_chrome_value(nil, key)).to be_nil
      expect(described_class.decrypt_chrome_value("v10\x01\x02", nil)).to be_nil
    end
  end

  describe '.find_chrome_cookies' do
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

      stub_const('RUBY_PLATFORM', 'arm64-darwin23')
      allow(described_class).to receive(:get_chrome_key).and_return(key)
      allow(described_class).to receive(:chrome_cookie_db_paths).and_return([cookie_db])
      allow(described_class).to receive(:system).and_return(true)

      expect(described_class.find_chrome_cookies).to eq(plaintext)
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

      allow(described_class).to receive(:get_chrome_key).and_return(key)
      allow(described_class).to receive(:chrome_cookie_db_paths).and_return([empty_db])
      allow(described_class).to receive(:system).and_return(true)

      expect(described_class.find_chrome_cookies).to be_nil
    ensure
      FileUtils.rm_f(empty_db) if empty_db && File.exist?(empty_db)
    end
  end
end