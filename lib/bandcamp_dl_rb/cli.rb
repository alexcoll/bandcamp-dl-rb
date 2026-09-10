# frozen_string_literal: true

module BandcampDlRb
  # Command-line interface: argument parsing and the top-level run loop.
  class CLI
    MAX_JOBS = 4

    def self.parse_args(argv = ARGV)
      new.parse_args(argv)
    end

    def self.run(argv = ARGV, out: $stdout, err: $stderr)
      new(out: out, err: err).run(argv)
    end

    def initialize(out: $stdout, err: $stderr)
      @out = out
      @err = err
    end

    def run(argv = ARGV)
      options = parse_args(argv)
      return 1 unless valid_options?(options)

      FileUtils.mkdir_p(options[:library])
      identity = authenticate(options)
      return 1 unless identity

      client = Client.new(identity)
      items = acquire_items(client, options)
      return 1 unless items

      finalize(client, options, items)
    end

    def parse_args(argv = ARGV)
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
        username: nil,
        urls: [],
        items: nil,
        jobs: 1,
        filter: nil
      }

      parser = build_parser(options)
      parser.parse!(argv)
      options[:username] = argv.shift unless argv.empty?
      options[:parser] = parser
      options
    end

    private

    def valid_options?(options)
      valid_jobs?(options) && valid_mode?(options)
    end

    def valid_mode?(options)
      return true if valid_requirements?(options)

      @err.puts(options[:parser])
      false
    end

    def valid_requirements?(options)
      return false unless options[:library]
      return true if options[:urls].any?

      !options[:username].nil?
    end

    def valid_jobs?(options)
      jobs = options[:jobs]
      return true unless jobs
      return true if (1..MAX_JOBS).cover?(jobs)

      @err.puts "ERROR: --jobs must be between 1 and #{MAX_JOBS}."
      @err.puts(options[:parser])
      false
    end

    def authenticate(options)
      identity = CookieExtractor.get_identity_cookie(options[:browser], options[:cookie_file])
      if identity
        BandcampDlRb.log 'Authenticated with Bandcamp.'
      else
        print_cookie_error
      end
      identity
    end

    def acquire_items(client, options)
      items = if options[:urls].any?
                resolve_url_items(client, options)
              elsif options[:items]
                filter_collection_items(client, options)
              elsif options[:filter]
                filter_collection_by_regex(client, options)
              else
                fetch_collection(client, options)
              end

      if items.nil? || items.empty?
        BandcampDlRb.log "\nNo downloadable items found."
        return nil
      end

      BandcampDlRb.log "\nFound #{items.length} downloadable item(s)."
      items
    end

    def fetch_collection(client, options)
      items = client.get_collection(
        options[:username],
        include_hidden: options[:include_hidden],
        since: options[:since],
        until_date: options[:until_date]
      )

      if items.empty?
        BandcampDlRb.log "\nNo downloadable items found. Check your username and ensure you're logged in."
        return nil
      end

      BandcampDlRb.log "\nFound #{items.length} downloadable items in collection."
      items
    end

    def filter_collection_items(client, options)
      all_items = get_all_collection(client, options)
      return nil if all_items.empty?

      items = client.filter_by_ids(all_items, options[:items])
      if items.empty?
        BandcampDlRb.log "\nNo matching items found for: #{options[:items]}"
        BandcampDlRb.log "Available item IDs: #{all_items.keys.join(', ')}"
        return nil
      end

      BandcampDlRb.log "Matched #{items.length} item(s) from collection."
      items
    end

    def filter_collection_by_regex(client, options)
      begin
        regex = Regexp.new(options[:filter], Regexp::IGNORECASE)
      rescue RegexpError => e
        BandcampDlRb.log "Invalid --filter regex: #{e.message}"
        return nil
      end

      all_items = get_all_collection(client, options)
      return nil if all_items.empty?

      items = client.filter_collection(all_items, regex)
      if items.empty?
        BandcampDlRb.log "\nNo matching items found for: #{options[:filter]}"
        return nil
      end

      BandcampDlRb.log "Matched #{items.length} item(s) from collection."
      items
    end

    def get_all_collection(client, options)
      BandcampDlRb.log "Fetching collection for #{options[:username]}..."
      all_items = client.get_collection(
        options[:username],
        include_hidden: options[:include_hidden]
      )
      if all_items.empty?
        BandcampDlRb.log "\nNo items found in collection. Check your username and ensure you're logged in."
        return {}
      end

      all_items
    end

    def resolve_url_items(client, options)
      items = {}
      options[:urls].each do |url|
        BandcampDlRb.log "Fetching #{url}..."
        html = client.get_html(url)
        unless html
          BandcampDlRb.log "  Failed to fetch page: #{url}"
          next
        end

        tralbum = client.parse_tralbum(html)
        unless tralbum
          BandcampDlRb.log "  Could not parse album data from: #{url}"
          next
        end

        BandcampDlRb.log "  #{tralbum['band_name']} - #{tralbum['item_title']}"

        item = resolve_item_from_tralbum(client, tralbum, options)
        if item
          items[item_key(item)] = item
        else
          BandcampDlRb.log '  Not found in collection or no download available'
        end
      end
      items
    end

    def resolve_item_from_tralbum(client, tralbum, options)
      username = options[:username]
      unless username
        BandcampDlRb.log '  Username required to look up download URL (pass as positional arg)'
        return nil
      end

      BandcampDlRb.log '  Searching collection for this item...'
      collection = client.get_collection(username, include_hidden: options[:include_hidden])
      item = client.find_item_in_collection(collection, tralbum)
      return item if item

      nil
    end

    def item_key(item)
      "#{item['sale_item_type']}#{item['sale_item_id']}"
    end

    def finalize(client, options, items)
      if options[:dry_run]
        print_dry_run(client, items, options[:format])
        return 0
      end

      download_items(client, items, options)
      write_state_file(items, options)
      print_summary(stats, items, options)
      0
    end

    # The OptionParser DSL's many opts.on/separator sends are an option
    # declaration table, not logic complexity; AbcSize is not meaningful here.
    # rubocop:disable Metrics/AbcSize
    def build_parser(options)
      OptionParser.new do |opts|
        opts.banner = "Usage: #{$PROGRAM_NAME} [options] <bandcamp-username>"
        opts.separator ''
        opts.separator 'Downloads Bandcamp purchases and organizes them for Plex.'
        opts.separator 'Provide a username to sync your collection, or --url/--items for specific items.'
        opts.separator ''
        opts.separator 'Authentication:'
        opts.separator '  The script reads your identity cookie from Firefox, Safari, or Chrome automatically (macOS).'
        opts.separator '  If that fails, export your cookies from your browser and use --cookie-file.'
        opts.separator '  Or provide the raw identity cookie value with --cookie-file.'
        opts.separator ''
        opts.separator 'To get your username: visit bandcamp.com, go to your profile, and look at the URL.'
        opts.separator '  It will be something like bandcamp.com/yourname'
        opts.separator ''

        opts.separator 'Options:'
        opts.on('-l', '--library PATH', 'Plex library root path (required)') { |v| options[:library] = v }
        opts.on('-f', '--format FORMAT', BandcampDlRb::FORMAT_MAP.keys, 'Audio format (default: flac)') { |v| options[:format] = v }
        opts.on('-b', '--browser BROWSER', %w[firefox chrome chromium safari auto],
                'Browser to extract cookies from (default: auto)') { |v| options[:browser] = v }
        opts.on('-c', '--cookie-file PATH', 'Path to cookies.txt file, or raw identity cookie value') do |v|
          options[:cookie_file] = v
        end
        opts.on('-H', '--include-hidden', 'Also download hidden items') { options[:include_hidden] = true }
        opts.on('--since DATE', 'Only download items purchased on or after this date (YYYY-MM-DD)') do |v|
          options[:since] = Date.parse(v)
        end
        opts.on('--until DATE', 'Only download items purchased before this date (YYYY-MM-DD)') do |v|
          options[:until_date] = Date.parse(v)
        end
        opts.on('--force', 'Re-download even if album already exists') { options[:force] = true }
        opts.on('--dry-run', 'Show what would be downloaded without downloading') { options[:dry_run] = true }
        opts.on('--url URL', 'Download a specific album/track by Bandcamp URL (repeatable)') { |v| options[:urls] << v }
        opts.on('-j', '--jobs N', Integer,
                "Download up to N albums in parallel (1-#{MAX_JOBS}, default: 1)") do |v|
          options[:jobs] = v
        end
        opts.on('--items IDS', 'Download specific items by ID, e.g. a100,t200 (requires username)') do |v|
          options[:items] = v
        end
        opts.on('--filter REGEX', 'Download only items whose artist or title matches REGEX (requires username)') do |v|
          options[:filter] = v
        end
        opts.on('-v', '--verbose', 'Verbose output') { BandcampDlRb.verbose = true }
        opts.on('-h', '--help', 'Show this help') do
          @out.puts opts
          exit
        end
      end
    end
    # rubocop:enable Metrics/AbcSize

    def print_cookie_error
      @err.puts "\nERROR: Could not find Bandcamp identity cookie."
      @err.puts "\nTo fix this, try one of:"
      @err.puts '  1. Log in to bandcamp.com in Firefox, Safari, or Chrome and run this script again.'
      @err.puts "  2. Use a browser extension (e.g., 'Get cookies.txt LOCALLY') to export cookies,"
      @err.puts '     then pass the file with: --cookie-file /path/to/cookies.txt'
      @err.puts "  3. Open DevTools (F12) > Application > Cookies > bandcamp.com, find 'identity',"
      @err.puts '     copy its value and pass it with: --cookie-file <raw-value>'
    end

    def print_dry_run(client, items, format)
      BandcampDlRb.log "\n--- Dry Run ---"
      total_bytes = 0
      unknown = 0

      items.each do |key, item|
        artist = item['band_name'] || 'Unknown Artist'
        title = item['item_title'] || 'Unknown Album'
        size = download_size_for(client, item, format)
        if size
          total_bytes += size
          size_line = BandcampDlRb::Utils.human_size(size)
        else
          unknown += 1
          size_line = 'unknown size'
        end
        BandcampDlRb.log "  [#{key}] #{artist} - #{title} (#{size_line})"
      end

      total_line = BandcampDlRb::Utils.human_size(total_bytes)
      total_line += " (+#{unknown} unknown)" if unknown.positive?
      BandcampDlRb.log "\nTotal: #{items.length} items, #{total_line} would be downloaded"
    end

    def download_size_for(client, item, format)
      download = Downloader.get_download_url(client, item['redownload_url'], format)
      return nil unless download

      Downloader.size_bytes(download) || Downloader.download_size(client, download[:url])
    end

    def download_items(client, items, options)
      @stats = { downloaded: 0, skipped: 0, failed: 0, unavailable: 0 }
      if (options[:jobs] || 1) > 1
        download_items_parallel(client, items, options)
      else
        download_items_serial(client, items, options)
      end
    end

    def download_items_serial(client, items, options)
      items.each_value do |item|
        result = Downloader.download_album(
          client, item, options[:library], options[:format], force: options[:force]
        )
        @stats[result] += 1
      end
    end

    def download_items_parallel(client, items, options)
      queue = Queue.new
      items.each_value { |item| queue << item }
      stats_mutex = Mutex.new

      workers = Array.new(options[:jobs]) { download_worker(client, queue, options, stats_mutex) }
      workers.each(&:join)
    end

    def download_worker(client, queue, options, stats_mutex)
      Thread.new do
        loop do
          item = queue.pop(true)
          result = Downloader.download_album(
            client, item, options[:library], options[:format], force: options[:force]
          )
          stats_mutex.synchronize { @stats[result] += 1 }
        rescue ThreadError
          break
        rescue StandardError => e
          BandcampDlRb.log "  Error downloading #{item_label(item)}: #{e.message}"
          stats_mutex.synchronize { @stats[:failed] += 1 }
        end
      end
    end

    def item_label(item)
      "#{item['band_name'] || 'Unknown Artist'} - #{item['item_title'] || 'Unknown Album'}"
    end

    def write_state_file(items, options)
      state_file = File.join(options[:library], '.bandcamp-sync.json')
      state = {
        'last_sync' => Time.now.iso8601,
        'username' => options[:username],
        'item_count' => items.length,
        'item_ids' => items.keys
      }
      File.write(state_file, JSON.pretty_generate(state))
      BandcampDlRb.log "\nSync state saved to #{state_file}"
    end

    def print_summary(stats, _items, options)
      BandcampDlRb.log "\n--- Summary ---"
      BandcampDlRb.log "  Downloaded:  #{stats[:downloaded]}"
      BandcampDlRb.log "  Skipped:     #{stats[:skipped]}"
      BandcampDlRb.log "  Unavailable: #{stats[:unavailable]}"
      BandcampDlRb.log "  Failed:      #{stats[:failed]}"
      BandcampDlRb.log "  Library:     #{options[:library]}"
    end

    def stats
      @stats ||= { downloaded: 0, skipped: 0, failed: 0, unavailable: 0 }
    end
  end
end
