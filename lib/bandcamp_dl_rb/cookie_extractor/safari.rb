# frozen_string_literal: true

module BandcampDlRb
  class CookieExtractor
    # Reads the Bandcamp `identity` cookie from the Safari binary cookies file.
    #
    # macOS stores Safari cookies in a custom binary format (Cookies.binarycookies)
    # whose values are stored in plaintext (unlike Chrome's AES-encrypted DB).
    class Safari
      COOKIES_FILE = 'Cookies.binarycookies'
      MAGIC = 'cook'
      IDENTITY = 'identity'
      HOST_HINT = 'bandcamp.com'
      MODERN_CONTAINER = 'Library/Containers/com.apple.Safari/Data/Library/Cookies'
      LEGACY_PATH = 'Library/Cookies'

      # Returns the identity cookie value, or nil if none is found.
      def self.find(path = nil)
        new(path).find
      end

      # Returns the path to the default macOS Safari cookies file.
      #
      # Safari was historically bundled into ~/Library/Cookies, but on macOS
      # Monterey+ it is sandboxed and the file lives under the app container at
      # ~/Library/Containers/com.apple.Safari/Data/... The first candidate that
      # exists is returned so both layouts are supported.
      def self.cookies_path
        [MODERN_CONTAINER, LEGACY_PATH].each do |dir|
          candidate = File.join(Dir.home, dir, COOKIES_FILE)
          return candidate if File.exist?(candidate)
        end
        File.join(Dir.home, LEGACY_PATH, COOKIES_FILE)
      end

      def initialize(path = nil)
        @path = path || self.class.cookies_path
      end

      def find
        return nil unless File.exist?(@path)

        parse(File.binread(@path))
      rescue StandardError => e
        BandcampDlRb.log_verbose "  Safari cookie read error: #{e.message}"
        nil
      end

      # Parses raw .binarycookies bytes and returns the identity cookie value,
      # or nil if none is found. All offsets are unsigned big/little-endian as
      # documented for the format.
      def parse(data)
        cookies(data).each do |cookie|
          return cookie[:value] if identity_cookie?(cookie)
        end
        nil
      end

      private

      def cookies(data)
        return [] unless data && data.bytesize >= 8 && data[0, 4] == MAGIC

        num_pages = data[4, 4].unpack1('N')
        pages = extract_pages(data, num_pages)
        pages.flat_map { |page| extract_cookies(data, page) }
      end

      def extract_pages(data, num_pages)
        return [] if num_pages.zero?

        sizes = read_page_sizes(data, num_pages)
        return [] if sizes.any?(&:nil?)

        compute_page_offsets(sizes).select { |o| data[o, 8] }
      end

      def read_page_sizes(data, num_pages)
        (0...num_pages).map { |i| data[8 + (i * 4), 4]&.unpack1('N') }
      end

      def compute_page_offsets(sizes)
        first = 8 + (sizes.length * 4)
        offsets = [first]
        sizes.first(sizes.length - 1).each { |size| offsets << (offsets.last + size) }
        offsets
      end

      def extract_cookies(data, page_start)
        return [] if page_start.nil?

        page = data[page_start..] || ''
        return [] unless page.bytesize >= 8

        num_cookies = page[4, 4].unpack1('V')
        (0...[num_cookies, ((page.bytesize - 8) / 4)].min).map do |i|
          rel = page[8 + (i * 4), 4].unpack1('V')
          parse_cookie(data, page_start + rel)
        end.compact
      end

      def parse_cookie(data, start)
        size = cookie_size(data, start)
        return nil if size.nil?
        return {} unless size >= 45

        {
          url: cstring(data, start + cookie_offset(data, start, 13)),
          name: cstring(data, start + cookie_offset(data, start, 17)),
          value: cstring(data, start + cookie_offset(data, start, 25))
        }
      rescue StandardError
        nil
      end

      def cookie_size(data, start)
        return nil if start.nil? || start < 8
        return nil if data[start, 4].nil?

        size = data[start, 4].unpack1('V')
        return nil if (start + size) > data.bytesize

        size
      end

      def cookie_offset(data, start, relative)
        data[start + relative, 4].unpack1('N')
      end

      def cstring(data, offset)
        return nil if offset.nil? || offset.negative?
        return nil if data[offset..].nil?

        bytes = data[offset..]
        terminator = bytes.index("\x00")
        return nil if terminator.nil?

        bytes[0...terminator].force_encoding('UTF-8')
      end

      def identity_cookie?(cookie)
        cookie[:name] == IDENTITY && cookie[:url].to_s.include?(HOST_HINT)
      end
    end
  end
end
