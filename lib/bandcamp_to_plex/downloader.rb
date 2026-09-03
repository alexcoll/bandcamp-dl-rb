# frozen_string_literal: true

module BandcampToPlex
  # Downloads Bandcamp purchase items (single tracks or zip albums) and
  # organizes them into an Artist/Album directory layout for Plex.
  class Downloader
    USER_AGENT = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36'

    def self.download_file(client, url, dest_path, max_retries: 3)
      max_retries.times do |attempt|
        begin
          uri = URI.parse(url)
          resp = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, read_timeout: 120) do |http|
            req = Net::HTTP::Get.new(uri)
            req['Cookie'] = "identity=#{client.identity}"
            req['User-Agent'] = USER_AGENT
            http.request(req)
          end

          if resp.is_a?(Net::HTTPRedirection) && resp['location']
            url = resp['location']
            next
          end

          unless resp.is_a?(Net::HTTPSuccess)
            BandcampToPlex.log_verbose "    HTTP #{resp.code} on attempt #{attempt + 1}"
            sleep(2**attempt)
            next
          end

          File.open(dest_path, 'wb') { |f| f.write(resp.body) }
          return true
        rescue => e
          BandcampToPlex.log_verbose "    Download error on attempt #{attempt + 1}: #{e.message}"
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

      ([format] + BandcampToPlex::QUALITY_ORDER).uniq.each do |fmt|
        if downloads[fmt] && downloads[fmt]['url']
          return { url: downloads[fmt]['url'], format: fmt }
        end
      end

      nil
    end

    def self.download_album(client, item, dest_dir, format, force: false)
      artist = BandcampToPlex::Utils.sanitize_path(item['band_name'] || 'Unknown Artist')
      title = BandcampToPlex::Utils.sanitize_path(item['item_title'] || 'Unknown Album')

      album_dir = File.join(dest_dir, artist, title)
      FileUtils.mkdir_p(album_dir)

      existing_files = Dir.glob(File.join(album_dir, '*.{flac,mp3,wav,zip,m4a,aiff,ogg}'))

      if existing_files.any? && !force
        BandcampToPlex.log "  Skipping: #{artist} - #{title} (already exists)"
        return :skipped
      end

      redownload_url = item['redownload_url']
      BandcampToPlex.log "  Downloading: #{artist} - #{title}"

      dl = get_download_url(client, redownload_url, format)
      unless dl
        BandcampToPlex.log '    No download available for this format'
        return :unavailable
      end

      tmp = File.join(Dir.tmpdir, "bc_#{item['sale_item_id']}_#{Process.pid}")
      FileUtils.mkdir_p(tmp)

      ext = BandcampToPlex::FORMAT_MAP[dl[:format]] || '.zip'
      tmp_file = File.join(tmp, "download#{ext}")

      unless download_file(client, dl[:url], tmp_file)
        BandcampToPlex.log '    Failed to download'
        FileUtils.rm_rf(tmp)
        return :failed
      end

      if ext == '.zip'
        begin
          Zip::File.open(tmp_file) do |zip|
            zip.each do |entry|
              next if entry.name.start_with?('__MACOSX', '.')
              next unless File.basename(entry.name).match?(BandcampToPlex::AUDIO_EXTENSIONS)

              entry_path = File.join(album_dir, File.basename(entry.name))
              entry.extract(entry_path)
            end
          end
          BandcampToPlex.log "    Extracted to #{album_dir}"
        rescue => e
          BandcampToPlex.log "    Error extracting zip: #{e.message}"
          FileUtils.rm_rf(tmp)
          return :failed
        end
      else
        FileUtils.cp(tmp_file, album_dir)
        BandcampToPlex.log "    Saved to #{album_dir}"
      end

      FileUtils.rm_rf(tmp)
      :downloaded
    end
  end
end