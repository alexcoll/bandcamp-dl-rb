# frozen_string_literal: true

module BandcampDlRb
  module Utils
    module_function

    # Replaces characters that are illegal in directory / file names on common
    # filesystems so item titles can be used as paths.
    def sanitize_path(name)
      name.gsub(%r{[/\\:*?"<>|]}, '-').strip
    end

    # Formats a byte count as a short, human-readable string (e.g. 1.3 MB).
    def human_size(bytes)
      return '0 B' if bytes.nil? || bytes.zero?

      value = bytes.to_f
      %w[B KB MB GB TB].each do |unit|
        return format('%.1<size>f %<unit>s', size: value, unit: unit) if value < 1024 || unit == 'TB'

        value /= 1024
      end
    end
  end
end
