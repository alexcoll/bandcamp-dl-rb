# frozen_string_literal: true

require 'bandcamp_dl_rb/cookie_extractor/firefox'
require 'bandcamp_dl_rb/cookie_extractor/chrome'
require 'bandcamp_dl_rb/cookie_extractor/safari'
require 'bandcamp_dl_rb/cookie_extractor/cookies_file'

module BandcampDlRb
  # Orchestrates extraction of the Bandcamp `identity` cookie from the user's
  # browser (Firefox, Safari, or Chrome), a cookies.txt file, or a raw cookie
  # value, delegating the source-specific work to collaborator classes.
  class CookieExtractor
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

        BandcampDlRb.log "Reading cookies from #{cookie_file}"
        CookiesFile.load_from(cookie_file)
      end

      def raw_cookie_value?(cookie_file)
        cookie_file && cookie_file =~ /\A[A-Za-z0-9_-]+\z/
      end

      def extract_from_browser(browser_mode)
        case browser_mode.downcase
        when 'firefox' then extract_with('Firefox', -> { Firefox.find })
        when 'safari' then extract_with('Safari', -> { Safari.find })
        when 'chrome', 'chromium' then extract_with(browser_mode, -> { Chrome.find(browser_mode) })
        when 'auto' then extract_auto
        end
      end

      def extract_with(label, finder)
        BandcampDlRb.log "Extracting identity cookie from #{label}..."
        value = finder.call
        BandcampDlRb.log "Could not find identity cookie in #{label}." unless value
        value
      end

      def extract_auto
        BandcampDlRb.log 'Trying Firefox...'
        value = Firefox.find
        return value if value

        BandcampDlRb.log 'Trying Safari...'
        value = Safari.find
        return value if value

        BandcampDlRb.log 'Trying Chrome...'
        Chrome.find
      end
    end
  end
end
