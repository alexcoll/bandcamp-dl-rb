# frozen_string_literal: true

module BandcampToPlex
  # Thin HTTP client that authenticates to Bandcamp's undocumented collection
  # API using the user's `identity` session cookie.
  class Client
    USER_AGENT = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36'

    attr_reader :identity

    def initialize(identity)
      @identity = identity
      @cookie = "identity=#{identity}"
    end

    def get(url)
      uri = URI.parse(url)
      req = Net::HTTP::Get.new(uri)
      req['Cookie'] = @cookie
      req['User-Agent'] = USER_AGENT
      req['Accept'] = '*/*'

      http_request(uri, req)
    end

    def post_json(url, data)
      uri = URI.parse(url)
      req = Net::HTTP::Post.new(uri)
      req['Cookie'] = @cookie
      req['User-Agent'] = USER_AGENT
      req['Content-Type'] = 'application/json'
      req['Accept'] = 'application/json'
      req.body = JSON.generate(data)

      http_request(uri, req)
    end

    def get_pagedata(url)
      resp = get(url)
      return nil unless resp.is_a?(Net::HTTPSuccess)

      resp.body.each_line do |line|
        next unless line.include?('pagedata') && line.include?('data-blob')

        blob = line.match(/data-blob="([^"]+)"/)
        return JSON.parse(CGI.unescapeHTML(blob[1])) if blob
      end
      nil
    rescue => e
      BandcampToPlex.log_verbose "  Error fetching page data: #{e.message}"
      nil
    end

    def collection_summary
      resp = post_json(BandcampToPlex::COLLECTION_SUMMARY_URL, {})
      return nil unless resp.is_a?(Net::HTTPSuccess)

      JSON.parse(resp.body)['collection_summary']
    rescue => e
      BandcampToPlex.log "Error fetching collection summary: #{e.message}"
      nil
    end

    def fetch_collection_items(fan_id, last_token, count)
      resp = post_json(BandcampToPlex::COLLECTION_ITEMS_URL, {
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
      resp = post_json(BandcampToPlex::HIDDEN_ITEMS_URL, {
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
      user_url = format(BandcampToPlex::USER_URL, username)
      pagedata = get_pagedata(user_url)
      unless pagedata
        log "ERROR: Could not load page data for #{username}. Check your username and cookies."
        return {}
      end

      unless pagedata.key?('collection_count')
        log "ERROR: No collection info found. Is '#{username}' your correct Bandcamp username?"
        log '       It should match the end of your collection URL (e.g., bandcamp.com/yourname).'
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

      items = merge_hidden_items(items, pagedata, fan_id, last_token) if include_hidden

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

    def merge_hidden_items(items, pagedata, fan_id, last_token)
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

      items.merge(hidden_items)
    end

    def http_request(uri, req)
      Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, open_timeout: 30, read_timeout: 60) do |http|
        http.request(req)
      end
    end

    def log(msg)
      BandcampToPlex.log(msg)
    end
  end

  # Backwards-compatible alias.
  BandcampClient = Client unless const_defined?(:BandcampClient)
end