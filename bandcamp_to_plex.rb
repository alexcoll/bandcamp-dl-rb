#!/usr/bin/env ruby
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

module BandcampToPlex
  FORMAT_MAP = {
    'flac'          => '.flac',
    'mp3-320'       => '.mp3',
    'mp3-v0'        => '.mp3',
    'wav'           => '.wav',
    'aiff-lossless' => '.aiff',
    'aac-hi'        => '.m4a',
    'alac'          => '.m4a',
    'vorbis'        => '.ogg'
  }.freeze

  USER_URL = 'https://bandcamp.com/%s'
  COLLECTION_SUMMARY_URL = 'https://bandcamp.com/api/fan/2/collection_summary'
  COLLECTION_ITEMS_URL = 'https://bandcamp.com/api/fancollection/1/collection_items'
  HIDDEN_ITEMS_URL = 'https://bandcamp.com/api/fancollection/1/hidden_items'

  AUDIO_EXTENSIONS = /\.(flac|mp3|wav|m4a|aiff|ogg)$/i.freeze

  QUALITY_ORDER = %w[flac wav aiff-lossless alac aac-hi mp3-320 mp3-v0 vorbis].freeze

  class << self
    attr_accessor :verbose
  end

  def self.log(msg)
    $stderr.puts msg
  end

  def self.log_verbose(msg)
    $stderr.puts msg if verbose
  end

  # --- Cookie Extraction ---

  def self.firefox_profile_dir
    case RUBY_PLATFORM
    when /darwin/
      File.join(Dir.home, 'Library/Application Support/Firefox/Profiles')
    when /mswin|mingw|cygwin/
      File.join(ENV['APPDATA'].to_s, 'Mozilla', 'Firefox', 'Profiles')
    else
      File.join(Dir.home, '.mozilla/firefox')
    end
  end

  def self.find_firefox_cookies(profile_root = nil)
    profile_dir = profile_root || firefox_profile_dir
    return nil unless Dir.exist?(profile_dir)

    Dir.glob(File.join(profile_dir, '*')).each do |profile|
      cookie_path = File.join(profile, 'cookies.sqlite')
      next unless File.exist?(cookie_path)

      begin
        db = SQLite3::Database.new(cookie_path, readonly: true)
        row = db.get_first_value(
          "SELECT value FROM moz_cookies WHERE name = 'identity' AND baseDomain = 'bandcamp.com' LIMIT 1"
        )
        db.close
        return row if row && !row.empty?
      rescue SQLite3::Exception => e
        log_verbose "  Firefox cookie read error: #{e.message}"
      end
    end
    nil
  end

  def self.load_cookies_from_file(path)
    File.readlines(path).each do |line|
      line.strip!
      next if line.start_with?('#') || line.empty?

      fields = line.split("\t")
      next unless fields.length >= 7
      _domain, _flag, _path, _secure, _expires, name, value = fields
      return value if name == 'identity' && fields[0].include?('bandcamp.com')
    end
    nil
  end

  def self.get_identity_cookie(browser = nil, cookie_file = nil)
    if cookie_file && File.exist?(cookie_file)
      log "Reading cookies from #{cookie_file}"
      val = load_cookies_from_file(cookie_file)
      return val if val
    end

    if cookie_file && cookie_file =~ /\A[A-Za-z0-9_-]+\z/
      log "Using raw identity cookie value"
      return cookie_file
    end

    browser_name = browser || 'auto'
    case browser_name.downcase
    when 'firefox'
      log "Extracting identity cookie from Firefox..."
      val = find_firefox_cookies
      return val if val
      log "Could not find identity cookie in Firefox."
    when 'auto'
      log "Trying Firefox..."
      val = find_firefox_cookies
      return val if val
    end

    nil
  end

  # --- Bandcamp API ---

  class BandcampClient
    attr_reader :identity

    def initialize(identity)
      @identity = identity
      @cookie = "identity=#{identity}"
    end

    def get(url)
      uri = URI.parse(url)
      req = Net::HTTP::Get.new(uri)
      req['Cookie'] = @cookie
      req['User-Agent'] = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36'
      req['Accept'] = '*/*'

      Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, open_timeout: 30, read_timeout: 60) do |http|
        http.request(req)
      end
    end

    def post_json(url, data)
      uri = URI.parse(url)
      req = Net::HTTP::Post.new(uri)
      req['Cookie'] = @cookie
      req['User-Agent'] = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36'
      req['Content-Type'] = 'application/json'
      req['Accept'] = 'application/json'
      req.body = JSON.generate(data)

      Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, open_timeout: 30, read_timeout: 60) do |http|
        http.request(req)
      end
    end

    def get_pagedata(url)
      resp = get(url)
      return nil unless resp.is_a?(Net::HTTPSuccess)

      resp.body.each_line do |line|
        next unless line.include?('pagedata') && line.include?('data-blob')
        blob = line.match(/data-blob="([^"]+)"/)
        if blob
          return JSON.parse(CGI.unescapeHTML(blob[1]))
        end
      end
      nil
    rescue => e
      BandcampToPlex.log_verbose "  Error fetching page data: #{e.message}"
      nil
    end

    def collection_summary
      resp = post_json(COLLECTION_SUMMARY_URL, {})
      return nil unless resp.is_a?(Net::HTTPSuccess)
      JSON.parse(resp.body)['collection_summary']
    rescue => e
      BandcampToPlex.log "Error fetching collection summary: #{e.message}"
      nil
    end

    def fetch_collection_items(fan_id, last_token, count)
      resp = post_json(COLLECTION_ITEMS_URL, {
        'fan_id' => fan_id,
        'count' => count,
        'older_than_token' => last_token
      })
      return nil unless resp.is_a?(Net::HTTPSuccess)
      JSON.parse(resp.body)
    rescue => e
      BandcampToPlex.log_verbose "  Error fetching collection items: #{e.message}"
      nil
    end

    def fetch_hidden_items(fan_id, last_token, count)
      resp = post_json(HIDDEN_ITEMS_URL, {
        'fan_id' => fan_id,
        'count' => count,
        'older_than_token' => last_token
      })
      return nil unless resp.is_a?(Net::HTTPSuccess)
      JSON.parse(resp.body)
    rescue => e
      BandcampToPlex.log_verbose "  Error fetching hidden items: #{e.message}"
      nil
    end

    def get_collection(username, include_hidden: false, since: nil, until_date: nil)
      log "Fetching collection page for #{username}..."
      user_url = format(USER_URL, username)
      pagedata = get_pagedata(user_url)
      unless pagedata
        log "ERROR: Could not load page data for #{username}. Check your username and cookies."
        return {}
      end

      unless pagedata.key?('collection_count')
        log "ERROR: No collection info found. Is '#{username}' your correct Bandcamp username?"
        log "       It should match the end of your collection URL (e.g., bandcamp.com/yourname)."
        return {}
      end

      fan_id = pagedata['fan_data']['fan_id']
      log "  Fan ID: #{fan_id}"

      items = {}
      pagedata['item_cache']['collection']&.each_value do |item|
        key = "#{item['sale_item_type']}#{item['sale_item_id']}"
        items[key] = item
      end

      urls = pagedata['collection_data']['redownload_urls'] || {}
      items.each do |key, item|
        item['redownload_url'] = urls[key] if urls[key]
      end

      remaining = pagedata['collection_data']['item_count'] - pagedata['item_cache']['collection'].length
      last_token = pagedata['collection_data']['last_token']

      if remaining > 0
        log "  Fetching #{remaining} more collection items..."
        while remaining > 0 && last_token
          batch = [remaining, 100].min
          data = fetch_collection_items(fan_id, last_token, batch)
          break unless data

          data['items']&.each do |item|
            key = "#{item['sale_item_type']}#{item['sale_item_id']}"
            item['redownload_url'] = data['redownload_urls']&.dig(key)
            items[key] = item if item['redownload_url']
          end

          last_token = data['last_token']
          remaining -= data['items']&.length || 0
        end
      end

      if include_hidden
        hidden_items = {}
        pagedata['item_cache']['hidden']&.each_value do |item|
          key = "#{item['sale_item_type']}#{item['sale_item_id']}"
          hidden_items[key] = item
        end
        urls = pagedata['collection_data']['redownload_urls'] || {}
        hidden_items.each do |key, item|
          item['redownload_url'] = urls[key] if urls[key]
        end

        remaining_hidden = pagedata['hidden_data']['item_count'] - pagedata['item_cache']['hidden'].length
        last_token = pagedata['hidden_data']['last_token']

        if remaining_hidden > 0
          log "  Fetching #{remaining_hidden} hidden items..."
          while remaining_hidden > 0 && last_token
            batch = [remaining_hidden, 100].min
            data = fetch_hidden_items(fan_id, last_token, batch)
            break unless data

            data['items']&.each do |item|
              key = "#{item['sale_item_type']}#{item['sale_item_id']}"
              item['redownload_url'] = data['redownload_urls']&.dig(key)
              hidden_items[key] = item if item['redownload_url']
            end

            last_token = data['last_token']
            remaining_hidden -= data['items']&.length || 0
          end
        end

        items.merge!(hidden_items)
      end

      if since || until_date
        items = items.select do |_key, item|
          next true unless item['purchased']

          begin
            purchased = Time.parse(item['purchased'])
            (since.nil? || purchased >= since) && (until_date.nil? || purchased < until_date)
          rescue
            true
          end
        end
      end

      items.select! { |_k, v| v['redownload_url'] && !v['redownload_url'].empty? }

      items
    end

    private

    def log(msg)
      BandcampToPlex.log(msg)
    end
  end

  # --- Download ---

  def self.download_file(client, url, dest_path, max_retries: 3)
    max_retries.times do |attempt|
      begin
        uri = URI.parse(url)
        resp = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, read_timeout: 120) do |http|
          req = Net::HTTP::Get.new(uri)
          req['Cookie'] = "identity=#{client.identity}"
          req['User-Agent'] = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36'
          http.request(req)
        end

        if resp.is_a?(Net::HTTPRedirection) && resp['location']
          url = resp['location']
          next
        end

        unless resp.is_a?(Net::HTTPSuccess)
          log_verbose "    HTTP #{resp.code} on attempt #{attempt + 1}"
          sleep(2**attempt)
          next
        end

        File.open(dest_path, 'wb') do |f|
          f.write(resp.body)
        end
        return true
      rescue => e
        log_verbose "    Download error on attempt #{attempt + 1}: #{e.message}"
        sleep(2**attempt)
      end
    end
    false
  end

  def self.get_download_url(client, album_url, format)
    pagedata = client.get_pagedata(album_url)
    return nil unless pagedata

    download_items = pagedata['download_items']
    return nil unless download_items&.any?

    item = download_items[0]
    downloads = item['downloads']
    return nil unless downloads

    preferred = ([format] + QUALITY_ORDER).uniq
    preferred.each do |fmt|
      if downloads[fmt] && downloads[fmt]['url']
        return { url: downloads[fmt]['url'], format: fmt }
      end
    end

    nil
  end

  def self.download_album(client, item, dest_dir, format, force: false)
    artist = sanitize_path(item['band_name'] || 'Unknown Artist')
    title = sanitize_path(item['item_title'] || 'Unknown Album')

    album_dir = File.join(dest_dir, artist, title)
    FileUtils.mkdir_p(album_dir)

    existing_files = Dir.glob(File.join(album_dir, '*.{flac,mp3,wav,zip,m4a,aiff,ogg}'))

    if existing_files.any? && !force
      log "  Skipping: #{artist} - #{title} (already exists)"
      return :skipped
    end

    redownload_url = item['redownload_url']
    log "  Downloading: #{artist} - #{title}"

    dl = get_download_url(client, redownload_url, format)
    unless dl
      log "    No download available for this format"
      return :unavailable
    end

    tmp = File.join(Dir.tmpdir, "bc_#{item['sale_item_id']}_#{Process.pid}")
    FileUtils.mkdir_p(tmp)

    ext = FORMAT_MAP[dl[:format]] || '.zip'
    tmp_file = File.join(tmp, "download#{ext}")

    success = download_file(client, dl[:url], tmp_file)
    unless success
      log "    Failed to download"
      FileUtils.rm_rf(tmp)
      return :failed
    end

    if ext == '.zip'
      begin
        Zip::File.open(tmp_file) do |zip|
          zip.each do |entry|
            next if entry.name.start_with?('__MACOSX', '.')
            next unless File.basename(entry.name).match?(AUDIO_EXTENSIONS)

            entry_path = File.join(album_dir, File.basename(entry.name))
            entry.extract(entry_path)
          end
        end
        log "    Extracted to #{album_dir}"
      rescue => e
        log "    Error extracting zip: #{e.message}"
        FileUtils.rm_rf(tmp)
        return :failed
      end
    else
      FileUtils.cp(tmp_file, album_dir)
      log "    Saved to #{album_dir}"
    end

    FileUtils.rm_rf(tmp)
    :downloaded
  end

  def self.sanitize_path(name)
    name.gsub(/[\/\\:*?"<>|]/, '-').strip
  end

  # --- CLI ---

  def self.parse_args(argv = ARGV)
    options = {
      format: 'flac',
      library: nil,
      browser: 'auto',
      cookie_file: nil,
      include_hidden: false,
      since: nil,
      until_date: nil,
      force: false,
      dry_run: false,
      username: nil
    }

    parser = OptionParser.new do |opts|
      opts.banner = "Usage: #{$0} [options] <bandcamp-username>"
      opts.separator ""
      opts.separator "Downloads all your Bandcamp purchases and organizes them for Plex."
      opts.separator ""
      opts.separator "Authentication:"
      opts.separator "  The script reads your identity cookie from Firefox automatically."
      opts.separator "  If that fails, export your cookies from your browser and use --cookie-file."
      opts.separator "  Or provide the raw identity cookie value with --cookie-file."
      opts.separator ""
      opts.separator "To get your username: visit bandcamp.com, go to your profile, and look at the URL."
      opts.separator "  It will be something like bandcamp.com/yourname"
      opts.separator ""

      opts.separator "Options:"
      opts.on('-l', '--library PATH', 'Plex library root path (required)') { |v| options[:library] = v }
      opts.on('-f', '--format FORMAT', FORMAT_MAP.keys, "Audio format (default: flac)") { |v| options[:format] = v }
      opts.on('-b', '--browser BROWSER', %w[firefox auto],
              'Browser to extract cookies from (default: auto)') { |v| options[:browser] = v }
      opts.on('-c', '--cookie-file PATH', 'Path to cookies.txt file, or raw identity cookie value') { |v| options[:cookie_file] = v }
      opts.on('-H', '--include-hidden', 'Also download hidden items') { options[:include_hidden] = true }
      opts.on('--since DATE', 'Only download items purchased on or after this date (YYYY-MM-DD)') { |v| options[:since] = Date.parse(v) }
      opts.on('--until DATE', 'Only download items purchased before this date (YYYY-MM-DD)') { |v| options[:until_date] = Date.parse(v) }
      opts.on('--force', 'Re-download even if album already exists') { options[:force] = true }
      opts.on('--dry-run', 'Show what would be downloaded without downloading') { options[:dry_run] = true }
      opts.on('-v', '--verbose', 'Verbose output') { BandcampToPlex.verbose = true }
      opts.on('-h', '--help', 'Show this help') { puts opts; exit }
    end

    parser.parse!(argv)
    options[:username] = argv.shift unless argv.empty?
    options[:parser] = parser
    options
  end

  def self.run(argv = ARGV, out: $stdout, err: $stderr)
    options = parse_args(argv)

    if options[:username].nil? || options[:library].nil?
      err.puts options[:parser]
      return 1
    end

    FileUtils.mkdir_p(options[:library])

    identity = get_identity_cookie(options[:browser], options[:cookie_file])
    unless identity
      err.puts "\nERROR: Could not find Bandcamp identity cookie."
      err.puts "\nTo fix this, try one of:"
      err.puts "  1. Log in to bandcamp.com in Firefox and run this script again."
      err.puts "  2. Use a browser extension (e.g., 'Get cookies.txt LOCALLY') to export cookies,"
      err.puts "     then pass the file with: --cookie-file /path/to/cookies.txt"
      err.puts "  3. Open DevTools (F12) > Application > Cookies > bandcamp.com, find 'identity',"
      err.puts "     copy its value and pass it with: --cookie-file <raw-value>"
      return 1
    end

    log "Authenticated with Bandcamp."

    client = BandcampClient.new(identity)

    items = client.get_collection(
      options[:username],
      include_hidden: options[:include_hidden],
      since: options[:since],
      until_date: options[:until_date]
    )

    if items.empty?
      log "\nNo downloadable items found. Check your username and ensure you're logged in."
      return 1
    end

    log "\nFound #{items.length} downloadable items in collection."

    if options[:dry_run]
      log "\n--- Dry Run ---"
      items.each_value do |item|
        artist = item['band_name'] || 'Unknown Artist'
        title = item['item_title'] || 'Unknown Album'
        log "  #{artist} - #{title}"
      end
      log "\nTotal: #{items.length} items would be downloaded"
      return 0
    end

    stats = { downloaded: 0, skipped: 0, failed: 0, unavailable: 0 }

    items.each_value do |item|
      result = download_album(client, item, options[:library], options[:format], force: options[:force])
      stats[result] += 1
    end

    state_file = File.join(options[:library], '.bandcamp-sync.json')
    state = {
      'last_sync' => Time.now.iso8601,
      'username' => options[:username],
      'item_count' => items.length,
      'item_ids' => items.keys
    }
    File.write(state_file, JSON.pretty_generate(state))
    log "\nSync state saved to #{state_file}"

    log "\n--- Summary ---"
    log "  Downloaded:  #{stats[:downloaded]}"
    log "  Skipped:     #{stats[:skipped]}"
    log "  Unavailable: #{stats[:unavailable]}"
    log "  Failed:      #{stats[:failed]}"
    log "  Library:     #{options[:library]}"
    0
  end
end

if __FILE__ == $0
  exit BandcampToPlex.run
end
