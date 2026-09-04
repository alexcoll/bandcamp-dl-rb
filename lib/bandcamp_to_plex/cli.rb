# frozen_string_literal: true

module BandcampToPlex
  # Command-line interface: argument parsing and the top-level run loop.
  class CLI
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
        username: nil
      }

      parser = build_parser(options)
      parser.parse!(argv)
      options[:username] = argv.shift unless argv.empty?
      options[:parser] = parser
      options
    end

    private

    def valid_options?(options)
      return true if options[:username] && options[:library]

      @err.puts(options[:parser])
      false
    end

    def authenticate(options)
      identity = CookieExtractor.get_identity_cookie(options[:browser], options[:cookie_file])
      if identity
        BandcampToPlex.log 'Authenticated with Bandcamp.'
      else
        print_cookie_error
      end
      identity
    end

    def acquire_items(client, options)
      items = client.get_collection(
        options[:username],
        include_hidden: options[:include_hidden],
        since: options[:since],
        until_date: options[:until_date]
      )

      if items.empty?
        BandcampToPlex.log "\nNo downloadable items found. Check your username and ensure you're logged in."
        return nil
      end

      BandcampToPlex.log "\nFound #{items.length} downloadable items in collection."
      items
    end

    def finalize(client, options, items)
      if options[:dry_run]
        print_dry_run(items)
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
        opts.separator 'Downloads all your Bandcamp purchases and organizes them for Plex.'
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
        opts.on('-f', '--format FORMAT', BandcampToPlex::FORMAT_MAP.keys, 'Audio format (default: flac)') { |v| options[:format] = v }
        opts.on('-b', '--browser BROWSER', %w[firefox chrome chromium brave edge safari auto],
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
        opts.on('-v', '--verbose', 'Verbose output') { BandcampToPlex.verbose = true }
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

    def print_dry_run(items)
      BandcampToPlex.log "\n--- Dry Run ---"
      items.each_value do |item|
        artist = item['band_name'] || 'Unknown Artist'
        title = item['item_title'] || 'Unknown Album'
        BandcampToPlex.log "  #{artist} - #{title}"
      end
      BandcampToPlex.log "\nTotal: #{items.length} items would be downloaded"
    end

    def download_items(client, items, options)
      @stats = { downloaded: 0, skipped: 0, failed: 0, unavailable: 0 }
      items.each_value do |item|
        result = Downloader.download_album(
          client, item, options[:library], options[:format], force: options[:force]
        )
        @stats[result] += 1
      end
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
      BandcampToPlex.log "\nSync state saved to #{state_file}"
    end

    def print_summary(stats, _items, options)
      BandcampToPlex.log "\n--- Summary ---"
      BandcampToPlex.log "  Downloaded:  #{stats[:downloaded]}"
      BandcampToPlex.log "  Skipped:     #{stats[:skipped]}"
      BandcampToPlex.log "  Unavailable: #{stats[:unavailable]}"
      BandcampToPlex.log "  Failed:      #{stats[:failed]}"
      BandcampToPlex.log "  Library:     #{options[:library]}"
    end

    def stats
      @stats ||= { downloaded: 0, skipped: 0, failed: 0, unavailable: 0 }
    end
  end
end
