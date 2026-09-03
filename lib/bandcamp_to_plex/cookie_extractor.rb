# frozen_string_literal: true

require 'English'
module BandcampToPlex
  # Extracts the Bandcamp `identity` cookie from the user's browser (Firefox or
  # Chrome), a cookies.txt file, or a raw cookie value.
  class CookieExtractor
    FIREFOX_COOKIE = 'cookies.sqlite'

    class << self
      # Returns the identity cookie value, or nil if none could be found.
      def get_identity_cookie(browser = nil, cookie_file = nil)
        value = extract_cookie_file(cookie_file)
        return value if value
        return cookie_file if raw_cookie_value?(cookie_file)

        extract_from_browser(browser || 'auto')
      end

      def extract_cookie_file(cookie_file)
        return nil unless cookie_file && File.exist?(cookie_file)

        BandcampToPlex.log "Reading cookies from #{cookie_file}"
        load_cookies_from_file(cookie_file)
      end

      def raw_cookie_value?(cookie_file)
        cookie_file && cookie_file =~ /\A[A-Za-z0-9_-]+\z/
      end

      def extract_from_browser(browser_mode)
        case browser_mode.downcase
        when 'firefox' then extract_with('Firefox', -> { find_firefox_cookies })
        when 'chrome', 'chromium', 'brave', 'edge' then extract_with(browser_mode, -> { find_chrome_cookies })
        when 'auto' then extract_auto
        end
      end

      def extract_with(label, finder)
        BandcampToPlex.log "Extracting identity cookie from #{label}..."
        value = finder.call
        BandcampToPlex.log "Could not find identity cookie in #{label}." unless value
        value
      end

      def extract_auto
        BandcampToPlex.log 'Trying Firefox...'
        value = find_firefox_cookies
        return value if value

        BandcampToPlex.log 'Trying Chrome...'
        find_chrome_cookies
      end

      # --- Firefox ---

      def firefox_profile_dir
        case RUBY_PLATFORM
        when /darwin/
          File.join(Dir.home, 'Library/Application Support/Firefox/Profiles')
        when /mswin|mingw|cygwin/
          File.join(ENV['APPDATA'].to_s, 'Mozilla', 'Firefox', 'Profiles')
        else
          File.join(Dir.home, '.mozilla/firefox')
        end
      end

      def find_firefox_cookies(profile_root = nil)
        profile_dir = profile_root || firefox_profile_dir
        return nil unless Dir.exist?(profile_dir)

        Dir.glob(File.join(profile_dir, '*')).each do |profile|
          value = read_firefox_cookie(File.join(profile, FIREFOX_COOKIE))
          return value unless value.nil?
        end
        nil
      end

      def read_firefox_cookie(cookie_path)
        return nil unless File.exist?(cookie_path)

        db = SQLite3::Database.new(cookie_path, readonly: true)
        row = db.get_first_value(
          "SELECT value FROM moz_cookies WHERE name = 'identity' AND baseDomain = 'bandcamp.com' LIMIT 1"
        )
        db.close
        return row if row && !row.empty?

        nil
      rescue SQLite3::Exception => e
        BandcampToPlex.log_verbose "  Firefox cookie read error: #{e.message}"
        nil
      end

      # --- Chrome ---

      def chrome_local_state_path
        case RUBY_PLATFORM
        when /darwin/
          File.join(Dir.home, 'Library/Application Support/Google/Chrome/Local State')
        when /mswin|mingw|cygwin/
          File.join(ENV['LOCALAPPDATA'].to_s, 'Google', 'Chrome', 'User Data', 'Local State')
        else
          File.join(Dir.home, '.config/google-chrome/Local State')
        end
      end

      def chrome_cookie_db_paths
        case RUBY_PLATFORM
        when /darwin/
          base = File.join(Dir.home, 'Library/Application Support/Google/Chrome')
          ['Default/Network/Cookies', 'Default/Cookies', 'Profile 1/Network/Cookies']
            .map { |p| File.join(base, p) }
        when /mswin|mingw|cygwin/
          base = File.join(ENV['LOCALAPPDATA'].to_s, 'Google', 'Chrome', 'User Data')
          ['Default/Network/Cookies', 'Default/Cookies'].map { |p| File.join(base, p) }
        else
          base = File.join(Dir.home, '.config/google-chrome')
          ['Default/Network/Cookies', 'Default/Cookies', 'Profile 1/Network/Cookies']
            .map { |p| File.join(base, p) }
        end
      end

      def get_chrome_key
        case RUBY_PLATFORM
        when /darwin/
          get_macos_chrome_key
        when /mswin|mingw|cygwin/
          get_windows_chrome_key
        else
          get_linux_chrome_key
        end
      rescue StandardError => e
        BandcampToPlex.log_verbose "  Chrome key retrieval failed: #{e.message}"
        nil
      end

      def get_macos_chrome_key
        return nil unless system('which security > /dev/null 2>&1')

        result = `/usr/bin/security find-generic-password -s 'Chrome Safe Storage' -a 'Chrome' -w 2>&1`.strip
        return nil unless $CHILD_STATUS.success? && !result.empty?

        result
      end

      def get_windows_chrome_key
        local_state = chrome_local_state_path
        return nil unless File.exist?(local_state)

        json = JSON.parse(File.read(local_state))
        encrypted = json.dig('os_crypt', 'encrypted_key')
        return nil unless encrypted&.start_with?('DPAPI')

        # Decode base64 and strip the "DPAPI" prefix. DPAPI protection is
        # reversible only on the same Windows user; see CryptoAPI below.
        decoded = encrypted[5..].unpack1('m0')
        decrypt_windows_dpapi(decoded) if !decoded.empty? && defined?(WIN32OLE)
      rescue StandardError => e
        BandcampToPlex.log_verbose "  Windows Chrome key read error: #{e.message}"
        nil
      end

      def get_linux_chrome_key
        return nil unless system('which secret-tool > /dev/null 2>&1')

        result = `secret-tool search 'application chrome' 'chrome' 2>&1`.strip
        result[/^\s*value:\s*(.+)$/, 1]
      rescue StandardError => e
        BandcampToPlex.log_verbose "  Linux Chrome key read error: #{e.message}"
        nil
      end

      def decrypt_chrome_value(encrypted, key)
        return nil unless encrypted && key
        return nil unless encrypted.start_with?('v10', 'v11')

        cipher = OpenSSL::Cipher.new('aes-128-cbc')
        cipher.decrypt
        cipher.key = key
        cipher.iv = "\x20" * 16
        cipher.update(encrypted[3..]) + cipher.final
      rescue OpenSSL::Cipher::CipherError => e
        BandcampToPlex.log_verbose "  Chrome value decrypt error: #{e.message}"
        nil
      end

      def find_chrome_cookies(db_path = nil)
        keys = get_chrome_key
        paths = db_path ? [db_path] : chrome_cookie_db_paths

        paths.each do |cookie_path|
          next unless File.exist?(cookie_path)

          value = read_chrome_cookie(cookie_path, keys)
          return value unless value.nil?
        end
        nil
      end

      def read_chrome_cookie(cookie_path, keys)
        tmp = File.join(Dir.tmpdir, "bc_chrome_cookies_#{Process.pid}.sqlite")
        FileUtils.cp(cookie_path, tmp)
        db = SQLite3::Database.new(tmp, readonly: true)

        rows = db.execute(
          "SELECT encrypted_value FROM cookies WHERE name = 'identity' " \
          "AND host_key LIKE '%bandcamp.com%' LIMIT 1"
        )
        db.close
        FileUtils.rm_f(tmp)

        return nil unless rows.any? && rows[0][0]

        value = decrypt_chrome_value(rows[0][0], keys)
        value unless value.empty?
      rescue StandardError => e
        BandcampToPlex.log_verbose "  Chrome cookie read error: #{e.message}"
        FileUtils.rm_f(tmp)
        nil
      end

      # --- Cookies file / raw value ---

      def load_cookies_from_file(path)
        File.readlines(path).each do |line|
          line.strip!
          next if line.start_with?('#') || line.empty?

          fields = line.split("\t")
          next unless fields.length >= 7

          _domain, _flag, _path, _secure, _expires, name, value = fields
          return value if name == 'identity' && fields[0].include?('bandcamp.com')
        end
        nil
      end

      private

      def decrypt_windows_dpapi(decoded)
        b64 = [decoded].pack('m0')
        script = "Add-Type -AssemblyName System.Security;\n" \
                 "$e=[Convert]::FromBase64String('#{b64}');\n" \
                 '$r=[System.Security.Cryptography.ProtectedData]::Unprotect(' \
                 "$e,$null,[System.Security.Cryptography.DataProtectionScope]::CurrentUser);\n" \
                 '[Convert]::ToBase64String($r)'
        result = `powershell -NoProfile -NonInteractive -Command "#{script}"`.strip
        return result.unpack1('m0') if $CHILD_STATUS.success? && !result.empty?

        nil
      rescue StandardError => e
        BandcampToPlex.log_verbose "  Windows DPAPI decrypt error: #{e.message}"
        nil
      end
    end
  end
end
