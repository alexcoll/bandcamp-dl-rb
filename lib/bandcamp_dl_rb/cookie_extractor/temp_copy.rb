# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'

module BandcampDlRb
  class CookieExtractor
    # Creates and cleans up private temp copies of browser cookie DBs.
    module TempCopy
      FILE_NAME = 'cookies.sqlite'

      # Returns the path to a directory holding a private 0600 copy of src.
      def self.create(src, prefix)
        dir = Dir.mktmpdir(prefix)
        tmp = File.join(dir, FILE_NAME)
        File.open(tmp, 'wb', 0o600) { |f| f.write(File.binread(src)) }
        dir
      end

      # Removes a temp directory created by .create, if any.
      def self.cleanup(dir)
        FileUtils.rm_rf(dir) if dir
      end
    end
  end
end
