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
    rescue StandardError => e
      BandcampToPlex.log_verbose "  Error fetching page data: #{e.message}"
      nil
    end

    def collection_summary
      resp = post_json(BandcampToPlex::COLLECTION_SUMMARY_URL, {})
      return nil unless resp.is_a?(Net::HTTPSuccess)

      JSON.parse(resp.body)['collection_summary']
    rescue StandardError => e
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
    rescue StandardError => e
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
    rescue StandardError => e
      BandcampToPlex.log_verbose "  Error fetching hidden items: #{e.message}"
      nil
    end

    def get_collection(username, include_hidden: false, since: nil, until_date: nil)
      log "Fetching collection page for #{username}..."
      pagedata = load_pagedata(username)
      return {} unless pagedata

      fan_id = pagedata['fan_data']['fan_id']
      log "  Fan ID: #{fan_id}"

      items = cached_items(pagedata['item_cache']['collection'], pagedata['collection_data'])
      items = fetch_paged(items, pagedata, :collection, fan_id, :fetch_collection_items)
      items = merge_hidden_items(items, pagedata, fan_id) if include_hidden
      items = filter_by_dates(items, since, until_date)
      items.select { |_key, item| download_url?(item) }
    end

    private

    def load_pagedata(username)
      pagedata = get_pagedata(format(BandcampToPlex::USER_URL, username))
      return nil unless pagedata
      return pagedata if pagedata.key?('collection_count')

      log "ERROR: No collection info found. Is '#{username}' your correct Bandcamp username?"
      nil
    end

    def cached_items(cache, data)
      items = {}
      cache&.each_value do |item|
        items[item_key(item)] = item
      end
      urls = data['redownload_urls'] || {}
      items.each { |key, item| item['redownload_url'] = urls[key] if urls[key] }
      items
    end

    def item_key(item)
      "#{item['sale_item_type']}#{item['sale_item_id']}"
    end

    def fetch_paged(items, pagedata, scope, fan_id, fetcher)
      remaining, last_token = pagination_state(pagedata, scope)
      return items if remaining.nil?

      log "  Fetching #{remaining} more #{scope} items..." if remaining.positive?
      while remaining.positive? && last_token
        resp = send(fetcher, fan_id, last_token, [remaining, 100].min)
        break unless resp

        incorporate_paged_response(items, resp)
        last_token = resp['last_token']
        remaining -= resp['items']&.length || 0
      end
      items
    end

    def pagination_state(pagedata, scope)
      cache = pagedata['item_cache'][scope.to_s]
      return [nil, nil] if cache.nil?

      data = pagedata[pagedata_key(scope)]
      [data['item_count'] - cache.length, data['last_token']]
    end

    def incorporate_paged_response(items, resp)
      resp['items']&.each do |item|
        item['redownload_url'] = resp['redownload_urls']&.dig(item_key(item))
        items[item_key(item)] = item if download_url?(item)
      end
    end

    def merge_hidden_items(items, pagedata, fan_id)
      hidden = cached_items(pagedata['item_cache']['hidden'], pagedata['collection_data'])
      hidden = fetch_paged(hidden, pagedata, :hidden, fan_id, :fetch_hidden_items)
      items.merge(hidden)
    end

    def filter_by_dates(items, since, until_date)
      return items unless since || until_date

      items.select do |_key, item|
        next true unless item['purchased']

        begin
          purchased = Time.parse(item['purchased'])
          (since.nil? || purchased >= since) && (until_date.nil? || purchased < until_date)
        rescue StandardError
          true
        end
      end
    end

    def download_url?(item)
      url = item['redownload_url']
      url && !url.empty?
    end

    def pagedata_key(scope)
      "#{scope}_data"
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
