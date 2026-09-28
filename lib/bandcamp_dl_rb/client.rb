# frozen_string_literal: true

module BandcampDlRb
  # Thin HTTP client that authenticates to Bandcamp's undocumented collection
  # API using the user's `identity` session cookie.
  class Client
    USER_AGENT = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36'
    MAX_PAGES = 500

    attr_reader :identity

    def initialize(identity, page_size: BandcampDlRb::DEFAULT_PAGE_SIZE)
      @identity = identity
      @page_size = page_size
      @cookie = "identity=#{identity}"
    end

    def get(url)
      uri = URI.parse(url)
      req = Net::HTTP::Get.new(uri)
      req['Cookie'] = @cookie if BandcampDlRb.bc_host?(uri.hostname)
      req['User-Agent'] = USER_AGENT
      req['Accept'] = '*/*'

      http_request(uri, req)
    end

    def get_html(url)
      resp = get(url)
      return nil unless resp.is_a?(Net::HTTPSuccess)

      resp.body
    rescue StandardError => e
      BandcampDlRb.log_verbose "  Error fetching page: #{e.message}"
      nil
    end

    def post_json(url, data)
      uri = URI.parse(url)
      req = Net::HTTP::Post.new(uri)
      req['Cookie'] = @cookie if BandcampDlRb.bc_host?(uri.hostname)
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
      BandcampDlRb.log_verbose "  Error fetching page data: #{e.message}"
      nil
    end

    def collection_summary
      resp = post_json(BandcampDlRb::COLLECTION_SUMMARY_URL, {})
      return nil unless resp.is_a?(Net::HTTPSuccess)

      JSON.parse(resp.body)['collection_summary']
    rescue StandardError => e
      BandcampDlRb.log "Error fetching collection summary: #{e.message}"
      nil
    end

    def fetch_collection_items(fan_id, last_token, count)
      resp = post_json(BandcampDlRb::COLLECTION_ITEMS_URL, {
                         'fan_id' => fan_id,
                         'count' => count,
                         'older_than_token' => last_token
                       })
      return nil unless resp.is_a?(Net::HTTPSuccess)

      JSON.parse(resp.body)
    rescue StandardError => e
      BandcampDlRb.log_verbose "  Error fetching collection items: #{e.message}"
      nil
    end

    def fetch_hidden_items(fan_id, last_token, count)
      resp = post_json(BandcampDlRb::HIDDEN_ITEMS_URL, {
                         'fan_id' => fan_id,
                         'count' => count,
                         'older_than_token' => last_token
                       })
      return nil unless resp.is_a?(Net::HTTPSuccess)

      JSON.parse(resp.body)
    rescue StandardError => e
      BandcampDlRb.log_verbose "  Error fetching hidden items: #{e.message}"
      nil
    end

    def parse_tralbum(html)
      match = html.match(/data-tralbum=("([^"]+)"|'([^']+)')/)
      return nil unless match

      raw = match[2] || match[3]
      data = JSON.parse(CGI.unescapeHTML(raw))
      {
        'band_name' => data['artist'],
        'item_title' => data.dig('current', 'title'),
        'tralbum_id' => data['id'],
        'tralbum_type' => data['item_type'] == 'album' ? 'a' : 't'
      }
    rescue StandardError => e
      BandcampDlRb.log_verbose "  Error parsing tralbum data: #{e.message}"
      nil
    end

    # Collection entries are keyed by sale item ("p403398974"), a different
    # keyspace from the tralbum id carried by a Bandcamp page URL
    # ("a1546900568"), so the two are joined on the tralbum identity that every
    # collection item also carries.
    def find_item_in_collection(items, tralbum)
      tralbum_id = tralbum['tralbum_id'].to_s
      tralbum_type = tralbum['tralbum_type'].to_s
      return nil if tralbum_id.empty?

      items.values.find do |item|
        item['tralbum_id'].to_s == tralbum_id && item['tralbum_type'].to_s == tralbum_type
      end
    end

    def filter_by_ids(items, item_ids)
      ids = Array(item_ids).flat_map { |id| id.split(',') }.map(&:strip).reject(&:empty?)
      items.slice(*ids)
    end

    def filter_collection(items, pattern)
      regex = pattern.is_a?(Regexp) ? pattern : Regexp.new(pattern, Regexp::IGNORECASE)
      items.select do |_key, item|
        haystack = [item['band_name'], item['item_title']].compact.join(' ')
        haystack.match?(regex)
      end
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
      pagedata = get_pagedata(format(BandcampDlRb::USER_URL, username))
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
      last_token = start_token(pagedata, scope)
      return items unless last_token

      fetch_pages(items, last_token, fan_id, fetcher)
    end

    # Walks the collection until the API reports no more pages. Bandcamp's
    # `count` is a page size, not a budget: consecutive pages overlap heavily
    # (a 100-item page advances the cursor by only ~20 new items), so the item
    # count advertised on the profile page cannot be used to decide when to
    # stop. `more_available` is the only reliable end-of-collection signal.
    def fetch_pages(items, last_token, fan_id, fetcher)
      pages = 0
      while last_token && pages < MAX_PAGES
        resp = send(fetcher, fan_id, last_token, @page_size)
        break unless resp

        incorporate_paged_response(items, resp)
        pages += 1
        break if last_page?(resp, last_token)

        last_token = resp['last_token']
      end
      BandcampDlRb.log_verbose "  Fetched #{pages} page(s) of #{fetcher_label(fetcher)} items"
      items
    end

    # A response ends paging when the server says so, when it hands back no
    # token, or when the token fails to advance. The token can also stall on
    # an empty page, which would otherwise loop forever.
    def last_page?(resp, previous_token)
      return true unless resp['more_available']

      resp['items'].nil? || resp['items'].empty? || resp['last_token'].nil? || resp['last_token'] == previous_token
    end

    def fetcher_label(fetcher)
      fetcher == :fetch_hidden_items ? 'hidden' : 'collection'
    end

    # The starting cursor for a scope, or nil when the profile page's embedded
    # cache already covers the whole scope and there is nothing left to page.
    def start_token(pagedata, scope)
      return nil if pagedata['item_cache'][scope.to_s].nil?

      pagedata.dig(pagedata_key(scope), 'last_token')
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

      items.select { |_key, item| in_date_range?(item, since, until_date) }
    end

    def in_date_range?(item, since, until_date)
      return true unless item['purchased']

      purchased = Time.parse(item['purchased'])
      (since.nil? || purchased >= since) && (until_date.nil? || purchased < until_date)
    rescue StandardError
      true
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
      BandcampDlRb.log(msg)
    end
  end

  # Backwards-compatible alias.
  BandcampClient = Client unless const_defined?(:BandcampClient)
end
