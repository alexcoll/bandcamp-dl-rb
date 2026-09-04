# frozen_string_literal: true

require 'English'
require 'json'
require 'fileutils'
require 'tmpdir'
require 'openssl'
require 'sqlite3'

module BandcampDlRb
  class CookieExtractor
    # Reads the Bandcamp `identity` cookie from a Chrome-family browser.
    class Chrome
      LOCAL_STATE_RELATIVE = 'Local State'
      SAFE_STORAGE_DB_RELATIVE = 'Network/Cookies'
      LEGACY_DB_RELATIVE = 'Cookies'
      IDENTITY_SQL = "SELECT encrypted_value FROM cookies WHERE name = 'identity' " \
                     "AND host_key LIKE '%bandcamp.com%' LIMIT 1"
      BROWSER_DIRS = {
        'chrome' => {
          darwin: ['Library', 'Application Support', 'Google', 'Chrome'],
          windows: ['Google', 'Chrome', 'User Data'],
          linux: ['.config', 'google-chrome']
        },
        'chromium' => {
          darwin: ['Library', 'Application Support', 'Chromium'],
          windows: ['Chromium', 'User Data'],
          linux: ['.config', 'chromium']
        }
      }.freeze
      KEYRING_LABELS = {
        'chrome' => { macos_service: 'Chrome Safe Storage', macos_account: 'Chrome', linux_app: 'chrome' },
        'chromium' => { macos_service: 'Chromium Safe Storage', macos_account: 'Chromium', linux_app: 'chromium' }
      }.freeze

      # Returns the identity cookie value, or nil if none is found.
      def self.find(browser = 'chrome', db_path = nil, key = nil)
        new(browser, db_path, key).find
      end

      def initialize(browser = 'chrome', db_path = nil, key = nil)
        @browser = browser
        @db_path = db_path
        @provided_key = key
      end

      def find
        paths.each do |cookie_path|
          next unless File.exist?(cookie_path)

          value = read_cookie(cookie_path, key)
          return value unless value.nil?
        end
        nil
      end

      # Decrypts an AES-128-CBC Chrome cookie payload ("v10"/"v11" prefix).
      def self.decrypt(encrypted, key)
        return nil unless encrypted && key
        return nil unless encrypted.start_with?('v10', 'v11')

        cipher = OpenSSL::Cipher.new('aes-128-cbc')
        cipher.decrypt
        cipher.key = key
        cipher.iv = "\x20" * 16
        cipher.update(encrypted[3..]) + cipher.final
      rescue OpenSSL::Cipher::CipherError => e
        BandcampDlRb.log_verbose "  Chrome value decrypt error: #{e.message}"
        nil
      end

      private

      def paths
        @db_path ? [@db_path] : self.class.cookie_db_paths(@browser)
      end

      def key
        @provided_key || self.class.retrieve_key(@browser)
      end

      def read_cookie(cookie_path, decryption_key)
        tmp = copy_to_temp(cookie_path)
        rows = query_identity(tmp)
        FileUtils.rm_f(tmp)

        return nil unless rows.any? && rows[0][0]

        value = self.class.decrypt(rows[0][0], decryption_key)
        value if !value.nil? && !value.empty?
      rescue StandardError => e
        BandcampDlRb.log_verbose "  Chrome cookie read error: #{e.message}"
        FileUtils.rm_f(tmp) if tmp
        nil
      end

      def copy_to_temp(cookie_path)
        tmp = File.join(Dir.tmpdir, "bc_chrome_cookies_#{Process.pid}.sqlite")
        FileUtils.cp(cookie_path, tmp)
        tmp
      end

      def query_identity(tmp)
        db = SQLite3::Database.new(tmp, readonly: true)
        rows = db.execute(IDENTITY_SQL)
        db.close
        rows
      end

      class << self
        def local_state_path(browser = 'chrome')
          File.join(*browser_base_path(browser), LOCAL_STATE_RELATIVE)
        end

        def cookie_db_paths(browser = 'chrome')
          db_relative_paths(browser_base_path(browser), cookie_profiles)
        end

        def retrieve_key(browser = 'chrome')
          case RUBY_PLATFORM
          when /darwin/
            macos_key(browser)
          when /mswin|mingw|cygwin/
            windows_key(browser)
          else
            linux_key(browser)
          end
        rescue StandardError => e
          BandcampDlRb.log_verbose "  Chrome key retrieval failed: #{e.message}"
          nil
        end

        private

        def browser_base_path(browser)
          dirs = BROWSER_DIRS.fetch(browser)
          case RUBY_PLATFORM
          when /darwin/
            File.join(Dir.home, *dirs[:darwin])
          when /mswin|mingw|cygwin/
            File.join(ENV['LOCALAPPDATA'].to_s, *dirs[:windows])
          else
            File.join(Dir.home, *dirs[:linux])
          end
        end

        def cookie_profiles
          case RUBY_PLATFORM
          when /mswin|mingw|cygwin/
            %w[Default]
          else
            %w[Default Profile 1]
          end
        end

        def db_relative_paths(base, profiles)
          profiles.flat_map do |profile|
            [File.join(base, profile, SAFE_STORAGE_DB_RELATIVE),
             File.join(base, profile, LEGACY_DB_RELATIVE)]
          end
        end

        def macos_key(browser)
          labels = KEYRING_LABELS.fetch(browser)
          return nil unless system('which security > /dev/null 2>&1')

          cmd = "/usr/bin/security find-generic-password -s '#{labels[:macos_service]}' " \
                "-a '#{labels[:macos_account]}' -w 2>&1"
          result = `#{cmd}`.strip
          return nil unless $CHILD_STATUS.success? && !result.empty?

          result
        end

        def windows_key(browser)
          local_state = local_state_path(browser)
          return nil unless File.exist?(local_state)

          json = JSON.parse(File.read(local_state))
          encrypted = json.dig('os_crypt', 'encrypted_key')
          return nil unless encrypted&.start_with?('DPAPI')

          decoded = encrypted[5..].unpack1('m0')
          decrypt_windows_dpapi(decoded) if !decoded.empty? && defined?(WIN32OLE)
        rescue StandardError => e
          BandcampDlRb.log_verbose "  Windows Chrome key read error: #{e.message}"
          nil
        end

        def linux_key(browser)
          labels = KEYRING_LABELS.fetch(browser)
          return nil unless system('which secret-tool > /dev/null 2>&1')

          result = `secret-tool search 'application #{labels[:linux_app]}' '#{labels[:linux_app]}' 2>&1`.strip
          result[/^\s*value:\s*(.+)$/, 1]
        rescue StandardError => e
          BandcampDlRb.log_verbose "  Linux Chrome key read error: #{e.message}"
          nil
        end

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
          BandcampDlRb.log_verbose "  Windows DPAPI decrypt error: #{e.message}"
          nil
        end
      end
    end
  end
end
