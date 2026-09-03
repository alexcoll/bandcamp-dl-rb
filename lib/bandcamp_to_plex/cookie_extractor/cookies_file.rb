# frozen_string_literal: true

module BandcampToPlex
  class CookieExtractor
    # Reads the Bandcamp `identity` cookie from a Netscape-style cookies.txt file.
    class CookiesFile
      # Returns the identity cookie value, or nil if none is found.
      def self.load_from(path)
        return nil unless path && File.exist?(path)

        File.readlines(path).each do |line|
          value = identity_value(line)
          return value unless value.nil?
        end
        nil
      end

      def self.identity_value(line)
        line = line.strip
        return nil if line.start_with?('#') || line.empty?

        fields = line.split("\t")
        return nil unless fields.length >= 7

        _domain, _flag, _path, _secure, _expires, name, value = fields
        value if name == 'identity' && fields[0].include?('bandcamp.com')
      end
    end
  end
end
