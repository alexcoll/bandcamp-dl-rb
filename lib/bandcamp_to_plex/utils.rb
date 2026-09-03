# frozen_string_literal: true

module BandcampToPlex
  module Utils
    module_function

    # Replaces characters that are illegal in directory / file names on common
    # filesystems so item titles can be used as paths.
    def sanitize_path(name)
      name.gsub(%r{[/\\:*?"<>|]}, '-').strip
    end
  end
end