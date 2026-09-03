# frozen_string_literal: true

module BandcampToPlex
  # Downloads Bandcamp purchase items (single tracks or zip albums) and
  # organizes them into an Artist/Album directory layout for Plex.
  class Downloader
    USER_AGENT = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36'

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

        BandcampToPlex.log_verbose "    Download error on attempt #{attempt + 1}"
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
      BandcampToPlex.log_verbose "    Download error: #{e.message}"
      nil
    end

    def self.redirect_to?(resp)
      resp.is_a?(Net::HTTPRedirection) && resp['location']
    end

    def self.success_response?(resp)
      resp.is_a?(Net::HTTPSuccess)
    end

    def self.get_download_url(client, album_url, format)
      pagedata = client.get_pagedata(album_url)
      return nil unless pagedata

      download_items = pagedata['download_items']
      return nil unless download_items&.any?

      item = download_items[0]
      downloads = item['downloads']
      return nil unless downloads

      ([format] + BandcampToPlex::QUALITY_ORDER).uniq.each do |fmt|
        return { url: downloads[fmt]['url'], format: fmt } if downloads[fmt] && downloads[fmt]['url']
      end

      nil
    end

    def self.download_album(client, item, dest_dir, format, force: false)
      album_dir = album_dir_for(item, dest_dir)
      label = album_label(album_dir)
      FileUtils.mkdir_p(album_dir)

      if album_exists?(album_dir) && !force
        BandcampToPlex.log "  Skipping: #{label} (already exists)"
        return :skipped
      end

      BandcampToPlex.log "  Downloading: #{label}"
      dl = get_download_url(client, item['redownload_url'], format)
      unless dl
        BandcampToPlex.log '    No download available for this format'
        return :unavailable
      end

      tmp_dir = temp_dir_for(item)
      tmp_file = download_to_temp(client, dl, tmp_dir)
      return :failed unless tmp_file

      placed = place_download(tmp_file, album_dir)
      placed ? :downloaded : :failed
    end

    def self.album_label(album_dir)
      "#{File.basename(File.dirname(album_dir))} - #{File.basename(album_dir)}"
    end

    def self.album_dir_for(item, dest_dir)
      artist = BandcampToPlex::Utils.sanitize_path(item['band_name'] || 'Unknown Artist')
      title = BandcampToPlex::Utils.sanitize_path(item['item_title'] || 'Unknown Album')
      File.join(dest_dir, artist, title)
    end

    def self.album_exists?(album_dir)
      Dir.glob(File.join(album_dir, '*.{flac,mp3,wav,zip,m4a,aiff,ogg}')).any?
    end

    def self.temp_dir_for(item)
      File.join(Dir.tmpdir, "bc_#{item['sale_item_id']}_#{Process.pid}")
    end

    def self.download_to_temp(client, download, tmp_dir)
      FileUtils.mkdir_p(tmp_dir)
      ext = BandcampToPlex::FORMAT_MAP[download[:format]] || '.zip'
      tmp_file = File.join(tmp_dir, "download#{ext}")

      unless download_file(client, download[:url], tmp_file)
        BandcampToPlex.log '    Failed to download'
        FileUtils.rm_rf(tmp_dir)
        return nil
      end

      tmp_file
    end

    def self.place_download(tmp_file, album_dir)
      ext = File.extname(tmp_file)
      if ext == '.zip'
        ok = extract_zip(tmp_file, album_dir)
      else
        FileUtils.cp(tmp_file, album_dir)
        BandcampToPlex.log "    Saved to #{album_dir}"
        ok = true
      end
      FileUtils.rm_rf(File.dirname(tmp_file))
      ok
    end

    def self.extract_zip(tmp_file, album_dir)
      Zip::File.open(tmp_file) do |zip|
        zip.each do |entry|
          next if entry.name.start_with?('__MACOSX', '.')
          next unless File.basename(entry.name).match?(BandcampToPlex::AUDIO_EXTENSIONS)

          entry.extract(File.join(album_dir, File.basename(entry.name)))
        end
      end
      BandcampToPlex.log "    Extracted to #{album_dir}"
      true
    rescue StandardError => e
      BandcampToPlex.log "    Error extracting zip: #{e.message}"
      false
    end
  end
end
