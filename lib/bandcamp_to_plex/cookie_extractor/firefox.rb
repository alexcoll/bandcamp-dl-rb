# frozen_string_literal: true

require 'sqlite3'
require 'fileutils'
require 'tmpdir'

module BandcampToPlex
  class CookieExtractor
    # Reads the Bandcamp `identity` cookie from a Firefox profile.
    class Firefox
      COOKIE_DB = 'cookies.sqlite'
      IDENTITY_SQL = "SELECT value FROM moz_cookies WHERE name = 'identity' " \
                     "AND host LIKE '%bandcamp.com%' LIMIT 1"

      # Top-level directory containing the Firefox profile folders.
      def self.profile_dir
        case RUBY_PLATFORM
        when /darwin/
          File.join(Dir.home, 'Library/Application Support/Firefox/Profiles')
        when /mswin|mingw|cygwin/
          File.join(ENV['APPDATA'].to_s, 'Mozilla', 'Firefox', 'Profiles')
        else
          File.join(Dir.home, '.mozilla/firefox')
        end
      end

      # Returns the identity cookie value, or nil if none is found.
      def self.find(profile_root = nil)
        new(profile_root).find
      end

      def initialize(profile_root = nil)
        @profile_root = profile_root
      end

      def find
        profiles.each do |profile|
          value = read_cookie(cookie_path_for(profile))
          return value unless value.nil?
        end
        nil
      end

      private

      def profiles
        return [] unless Dir.exist?(profiles_root)

        Dir.glob(File.join(profiles_root, '*'))
      end

      def profiles_root
        @profile_root || self.class.profile_dir
      end

      def cookie_path_for(profile)
        File.join(profile, COOKIE_DB)
      end

      def read_cookie(cookie_path)
        return nil unless File.exist?(cookie_path)

        tmp = copy_to_temp(cookie_path)
        value = query_identity(tmp)
        FileUtils.rm_f(tmp)
        present?(value) ? value : nil
      rescue StandardError => e
        BandcampToPlex.log_verbose "  Firefox cookie read error: #{e.message}"
        FileUtils.rm_f(tmp) if tmp
        nil
      end

      def copy_to_temp(cookie_path)
        tmp = File.join(Dir.tmpdir, "bc_firefox_cookies_#{Process.pid}.sqlite")
        FileUtils.cp(cookie_path, tmp)
        tmp
      end

      def query_identity(tmp)
        db = SQLite3::Database.new(tmp, readonly: true)
        value = db.get_first_value(IDENTITY_SQL)
        db.close
        value
      end

      def present?(value)
        !value.nil? && !value.empty?
      end
    end
  end
end
