# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'json'
require 'optparse'
require 'fileutils'
require 'tmpdir'
require 'zip'
require 'sqlite3'
require 'cgi'
require 'date'
require 'openssl'

require 'bandcamp_dl_rb/version'
require 'bandcamp_dl_rb/utils'
require 'bandcamp_dl_rb/cookie_extractor'
require 'bandcamp_dl_rb/client'
require 'bandcamp_dl_rb/downloader'
require 'bandcamp_dl_rb/cli'

# Downloads all your Bandcamp purchases and organizes them for a Plex library.
module BandcampDlRb
  USER_URL = 'https://bandcamp.com/%s'
  COLLECTION_SUMMARY_URL = 'https://bandcamp.com/api/fan/2/collection_summary'
  COLLECTION_ITEMS_URL = 'https://bandcamp.com/api/fancollection/1/collection_items'
  HIDDEN_ITEMS_URL = 'https://bandcamp.com/api/fancollection/1/hidden_items'

  FORMAT_MAP = {
    'flac' => '.flac',
    'mp3-320' => '.mp3',
    'mp3-v0' => '.mp3',
    'wav' => '.wav',
    'aiff-lossless' => '.aiff',
    'aac-hi' => '.m4a',
    'alac' => '.m4a',
    'vorbis' => '.ogg'
  }.freeze

  AUDIO_EXTENSIONS = /\.(flac|mp3|wav|m4a|aiff|ogg)$/i
  QUALITY_ORDER = %w[flac wav aiff-lossless alac aac-hi mp3-320 mp3-v0 vorbis].freeze

  class << self
    attr_accessor :verbose
  end

  def self.log(msg)
    warn msg
  end

  def self.log_verbose(msg)
    warn msg if verbose
  end

  # Convenience entrypoint; delegates to the CLI.
  def self.run(argv = ARGV, out: $stdout, err: $stderr)
    CLI.run(argv, out: out, err: err)
  end
end
