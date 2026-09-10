# frozen_string_literal: true

module BandcampDlRb
  # Downloads Bandcamp purchase items (single tracks or zip albums) and
  # organizes them into an Artist/Album directory layout for Plex.
  class Downloader
    USER_AGENT = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36'
    AUDIO_EXTENSIONS = /\.(flac|mp3|wav|m4a|aiff|ogg)$/i
    COVER_EXTENSIONS = /\.(jpe?g|png)$/i
    COVER_CDN = 'https://f4.bcbits.com/img/a%s_10.jpg'

    def self.download_file(client, url, dest_path, max_retries: 3)
      max_retries.times do |attempt|
        resp = perform_download(client, url)

        if redirect_to?(resp)
          url = resp['location']
          next
        end
        if success_response?(resp)
          File.binwrite(dest_path, resp.body)
          return true
        end

        BandcampDlRb.log_verbose "    Download error on attempt #{attempt + 1}"
        sleep(2**attempt)
      end
      false
    end

    def self.perform_download(client, url)
      uri = URI.parse(url)
      Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, read_timeout: 120) do |http|
        req = Net::HTTP::Get.new(uri)
        req['Cookie'] = "identity=#{client.identity}"
        req['User-Agent'] = USER_AGENT
        http.request(req)
      end
    rescue StandardError => e
      BandcampDlRb.log_verbose "    Download error: #{e.message}"
      nil
    end

    # Determines the byte size of a remote download without saving it, by
    # requesting a single byte (Range) and reading the total from the
    # Content-Range header. Some download servers reject HEAD requests, so a
    # ranged GET is used instead. Returns nil when the size cannot be
    # determined.
    def self.download_size(client, url, max_redirects: 5)
      max_redirects.times do
        resp = perform_size_check(client, url)
        return nil unless resp

        return total_from_content_range(resp) if partial_content?(resp)
        return resp['content-length']&.to_i if success_response?(resp)
        return nil unless redirect_to?(resp)

        url = resp['location']
      end
      nil
    end

    def self.partial_content?(resp)
      resp.is_a?(Net::HTTPPartialContent)
    end

    def self.total_from_content_range(resp)
      range = resp['content-range']
      return nil unless range

      range.split('/').last.to_i
    end

    def self.perform_size_check(client, url)
      uri = URI.parse(url)
      Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, open_timeout: 30, read_timeout: 60) do |http|
        req = Net::HTTP::Get.new(uri)
        req['Cookie'] = "identity=#{client.identity}"
        req['User-Agent'] = USER_AGENT
        req['Range'] = 'bytes=0-0'
        http.request(req)
      end
    rescue StandardError => e
      BandcampDlRb.log_verbose "    Size check error: #{e.message}"
      nil
    end

    def self.redirect_to?(resp)
      resp.is_a?(Net::HTTPRedirection) && resp['location']
    end

    def self.success_response?(resp)
      resp.is_a?(Net::HTTPSuccess)
    end

    # Fetches the download page and resolves the URL for the requested format.
    # Pass pre-fetched +pagedata+ to avoid a redundant HTTP request.
    def self.get_download_url(client, album_url, format, pagedata: nil)
      pagedata ||= client.get_pagedata(album_url)
      item = pagedata&.dig('download_items', 0)
      return nil unless item

      downloads = item['downloads']
      return nil unless downloads

      dl = first_available_format(downloads, format)
      return nil unless dl

      attach_art_id(dl, item, pagedata)
      dl
    end

    def self.attach_art_id(download_info, item, pagedata)
      art_id = item['art_id'] || pagedata['art_id']
      download_info[:art_id] = art_id if art_id
    end

    def self.first_available_format(downloads, format)
      ([format] + BandcampDlRb::QUALITY_ORDER).uniq.each do |fmt|
        url = downloads.dig(fmt, 'url')
        return { url: url, format: fmt, size_mb: downloads.dig(fmt, 'size_mb') } if url
      end
      nil
    end

    SIZE_UNITS = { 'B' => 1, 'KB' => 1024, 'MB' => 1024**2, 'GB' => 1024**3, 'TB' => 1024**4 }.freeze

    # Bandcamp reports each format's size as a display string (e.g. "1.2GB")
    # in the album pagedata. Parses it to bytes, or nil when absent.
    def self.size_bytes(download)
      raw = download[:size_mb]
      return nil unless raw

      match = raw.match(/([\d.]+)\s*(B|KB|MB|GB|TB)/i)
      return nil unless match

      (match[1].to_f * SIZE_UNITS[match[2].upcase]).to_i
    end

    def self.download_album(client, item, dest_dir, format, force: false)
      album_dir = album_dir_for(item, dest_dir)
      label = album_label(album_dir)
      FileUtils.mkdir_p(album_dir)

      if album_exists?(album_dir) && !force
        BandcampDlRb.log "  Skipping: #{label} (already exists)"
        return :skipped
      end

      BandcampDlRb.log "  Downloading: #{label}"
      pagedata = client.get_pagedata(item['redownload_url'])
      dl = get_download_url(client, nil, format, pagedata: pagedata)
      unless dl
        BandcampDlRb.log '    No download available for this format'
        return :unavailable
      end

      save_cover(client, dl, album_dir)
      save_album_info(pagedata, album_dir)

      tmp_dir = temp_dir_for(item)
      tmp_file = download_to_temp(client, dl, tmp_dir)
      return :failed unless tmp_file

      placed = place_download(tmp_file, album_dir)
      placed ? :downloaded : :failed
    end

    def self.save_cover(client, download_info, album_dir)
      art_id = download_info[:art_id]
      return unless art_id

      url = format(COVER_CDN, art_id)
      dest = File.join(album_dir, 'cover.jpg')
      return if File.exist?(dest)

      BandcampDlRb.log_verbose '    Downloading cover art...'
      ok = download_file(client, url, dest, max_retries: 2)
      FileUtils.rm_f(dest) unless ok
    rescue StandardError => e
      BandcampDlRb.log_verbose "    Cover download error: #{e.message}"
    end

    def self.save_album_info(pagedata, album_dir)
      return unless pagedata

      info = extract_album_metadata(pagedata)
      return if info.empty?

      dest = File.join(album_dir, 'album.json')
      File.write(dest, JSON.pretty_generate(info))
    rescue StandardError => e
      BandcampDlRb.log_verbose "    Album info error: #{e.message}"
    end

    def self.extract_album_metadata(pagedata)
      return {} unless pagedata.is_a?(Hash)

      digital_item = pagedata.dig('download_items', 0) || {}
      source = pagedata.merge(digital_item) { |_key, paged, item| item || paged }

      {
        'artist' => source['artist'],
        'title' => source['title'],
        'release_date' => source['album_release_date'],
        'label' => source['label'],
        'credits' => source['credits']
      }.merge(tracklist_metadata(source)).compact
    end

    def self.tracklist_metadata(source)
      trackinfo = source['trackinfo']
      return {} unless trackinfo.is_a?(Array) && !trackinfo.empty?

      { 'tracklist' => trackinfo.map { |track| track_entry(track) } }
    end

    def self.track_entry(track)
      entry = { 'title' => track['title'], 'duration' => track['duration'] }
      entry['track_num'] = track['track_num'] if track.key?('track_num')
      entry
    end

    def self.album_label(album_dir)
      "#{File.basename(File.dirname(album_dir))} - #{File.basename(album_dir)}"
    end

    def self.album_dir_for(item, dest_dir)
      album_dir = File.join(dest_dir, safe_segment(item['band_name'], 'Unknown Artist'),
                            safe_segment(item['item_title'], 'Unknown Album'))
      return album_dir if contained_in?(album_dir, dest_dir)

      BandcampDlRb.log_verbose '    Album path escapes library root; using placeholder name'
      File.join(dest_dir, 'Unknown Artist', 'Unknown Album')
    end

    def self.safe_segment(raw, fallback)
      BandcampDlRb::Utils.sanitize_path(raw || fallback)
    end

    def self.contained_in?(path, root)
      File.expand_path(path).start_with?(File.expand_path(root) + File::SEPARATOR)
    end

    def self.album_exists?(album_dir)
      Dir.glob(File.join(album_dir, '*.{flac,mp3,wav,zip,m4a,aiff,ogg}')).any?
    end

    def self.temp_dir_for(item)
      File.join(Dir.tmpdir, "bc_#{item['sale_item_id']}_#{Process.pid}")
    end

    def self.download_to_temp(client, download, tmp_dir)
      FileUtils.mkdir_p(tmp_dir)
      ext = BandcampDlRb::FORMAT_MAP[download[:format]] || '.zip'
      tmp_file = File.join(tmp_dir, "download#{ext}")

      unless download_file(client, download[:url], tmp_file)
        BandcampDlRb.log '    Failed to download'
        FileUtils.rm_rf(tmp_dir)
        return nil
      end

      tmp_file
    end

    def self.place_download(tmp_file, album_dir)
      ext = File.extname(tmp_file)
      if ext == '.zip'
        extract_zip(tmp_file, album_dir)
      else
        FileUtils.cp(tmp_file, album_dir)
        BandcampDlRb.log "    Saved to #{album_dir}"
        true
      end
    ensure
      FileUtils.rm_rf(File.dirname(tmp_file))
    end

    def self.extract_zip(tmp_file, album_dir)
      Zip::File.open(tmp_file) do |zip|
        zip.each do |entry|
          next unless extractable_entry?(entry)

          basename = File.basename(entry.name)
          next if existing_cover?(basename, album_dir)

          entry.extract(basename, destination_directory: album_dir)
        end
      end
      BandcampDlRb.log "    Extracted to #{album_dir}"
      true
    rescue StandardError => e
      BandcampDlRb.log "    Error extracting zip: #{e.message}"
      false
    end

    def self.extractable_entry?(entry)
      return false if entry.name.start_with?('__MACOSX', '.')

      basename = File.basename(entry.name)
      basename.match?(AUDIO_EXTENSIONS) || basename.match?(COVER_EXTENSIONS)
    end

    def self.existing_cover?(basename, album_dir)
      basename.match?(COVER_EXTENSIONS) && File.exist?(File.join(album_dir, basename))
    end
  end
end
