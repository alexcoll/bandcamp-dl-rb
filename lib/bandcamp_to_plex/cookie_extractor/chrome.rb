# frozen_string_literal: true

require 'English'
require 'json'
require 'fileutils'
require 'tmpdir'
require 'openssl'
require 'sqlite3'

module BandcampToPlex
  class CookieExtractor
    # Reads the Bandcamp `identity` cookie from a Chrome-family browser.
    class Chrome
      LOCAL_STATE_RELATIVE = 'Local State'
      SAFE_STORAGE_DB_RELATIVE = 'Network/Cookies'
      LEGACY_DB_RELATIVE = 'Cookies'
      IDENTITY_SQL = "SELECT encrypted_value FROM cookies WHERE name = 'identity' " \
                     "AND host_key LIKE '%bandcamp.com%' LIMIT 1"

      # Returns the identity cookie value, or nil if none is found.
      def self.find(db_path = nil, key = nil)
        new(db_path, key).find
      end

      def initialize(db_path = nil, key = nil)
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
        BandcampToPlex.log_verbose "  Chrome value decrypt error: #{e.message}"
        nil
      end

      private

      def paths
        @db_path ? [@db_path] : self.class.cookie_db_paths
      end

      def key
        @provided_key || self.class.retrieve_key
      end

      def read_cookie(cookie_path, decryption_key)
        tmp = copy_to_temp(cookie_path)
        rows = query_identity(tmp)
        FileUtils.rm_f(tmp)

        return nil unless rows.any? && rows[0][0]

        value = self.class.decrypt(rows[0][0], decryption_key)
        value if !value.nil? && !value.empty?
      rescue StandardError => e
        BandcampToPlex.log_verbose "  Chrome cookie read error: #{e.message}"
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
        def local_state_path
          case RUBY_PLATFORM
          when /darwin/
            File.join(Dir.home, 'Library/Application Support/Google/Chrome', LOCAL_STATE_RELATIVE)
          when /mswin|mingw|cygwin/
            File.join(ENV['LOCALAPPDATA'].to_s, 'Google', 'Chrome', 'User Data', LOCAL_STATE_RELATIVE)
          else
            File.join(Dir.home, '.config/google-chrome', LOCAL_STATE_RELATIVE)
          end
        end

        def cookie_db_paths
          case RUBY_PLATFORM
          when /darwin/
            base = File.join(Dir.home, 'Library/Application Support/Google/Chrome')
            db_relative_paths(base, %w[Default Profile 1])
          when /mswin|mingw|cygwin/
            base = File.join(ENV['LOCALAPPDATA'].to_s, 'Google', 'Chrome', 'User Data')
            db_relative_paths(base, %w[Default])
          else
            base = File.join(Dir.home, '.config/google-chrome')
            db_relative_paths(base, %w[Default Profile 1])
          end
        end

        def retrieve_key
          case RUBY_PLATFORM
          when /darwin/
            macos_key
          when /mswin|mingw|cygwin/
            windows_key
          else
            linux_key
          end
        rescue StandardError => e
          BandcampToPlex.log_verbose "  Chrome key retrieval failed: #{e.message}"
          nil
        end

        private

        def db_relative_paths(base, profiles)
          profiles.flat_map do |profile|
            [File.join(base, profile, SAFE_STORAGE_DB_RELATIVE),
             File.join(base, profile, LEGACY_DB_RELATIVE)]
          end
        end

        def macos_key
          return nil unless system('which security > /dev/null 2>&1')

          result = `/usr/bin/security find-generic-password -s 'Chrome Safe Storage' -a 'Chrome' -w 2>&1`.strip
          return nil unless $CHILD_STATUS.success? && !result.empty?

          result
        end

        def windows_key
          local_state = local_state_path
          return nil unless File.exist?(local_state)

          json = JSON.parse(File.read(local_state))
          encrypted = json.dig('os_crypt', 'encrypted_key')
          return nil unless encrypted&.start_with?('DPAPI')

          decoded = encrypted[5..].unpack1('m0')
          decrypt_windows_dpapi(decoded) if !decoded.empty? && defined?(WIN32OLE)
        rescue StandardError => e
          BandcampToPlex.log_verbose "  Windows Chrome key read error: #{e.message}"
          nil
        end

        def linux_key
          return nil unless system('which secret-tool > /dev/null 2>&1')

          result = `secret-tool search 'application chrome' 'chrome' 2>&1`.strip
          result[/^\s*value:\s*(.+)$/, 1]
        rescue StandardError => e
          BandcampToPlex.log_verbose "  Linux Chrome key read error: #{e.message}"
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
          BandcampToPlex.log_verbose "  Windows DPAPI decrypt error: #{e.message}"
          nil
        end
      end
    end
  end
end
