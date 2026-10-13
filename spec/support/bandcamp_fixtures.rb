# frozen_string_literal: true

# Builders for the payloads Bandcamp serves.
#
# Specs state only the part they care about -- which items, which artist --
# and let these fill in the surrounding structure, so a change to the real
# payload shape is made in one place rather than in every spec that happened
# to copy that shape. The literals these replace were near-identical blobs of
# thirty lines each.
module BandcampFixtures
  FAN_ID = 123
  REDOWNLOAD_URL = 'https://bandcamp.com/redownload/%s'
  DOWNLOAD_URL = 'https://bandcamp.com/download/album?id=%d'

  module_function

  # <div id="pagedata" data-blob="...">, as served on a Bandcamp profile page
  # and read back by Client#get_pagedata.
  def pagedata_page(blob)
    %(<div id="pagedata" data-blob="#{CGI.escapeHTML(JSON.generate(blob))}"></div>)
  end

  # <div data-tralbum='...'>, as served on an album or track page and read
  # back by Client#parse_tralbum.
  def tralbum_page(artist:, title:, id:, item_type: 'album')
    %(<div data-tralbum='#{CGI.escapeHTML(JSON.generate(tralbum_blob(artist, title, id, item_type)))}'></div>)
  end

  def tralbum_blob(artist, title, id, item_type)
    { 'artist' => artist, 'current' => { 'title' => title }, 'id' => id, 'item_type' => item_type }
  end

  # One collection entry, carrying the fields Bandcamp puts on a sale item.
  # +type+ is the sale item type, which doubles as the tralbum type ('a' for an
  # album, 't' for a track, 'p' for a physical item).
  def sale_item(id:, artist:, title:, type: 'a', **extra)
    {
      'sale_item_type' => type,
      'sale_item_id' => id,
      'band_name' => artist,
      'item_title' => title,
      'tralbum_type' => type
    }.merge(extra)
  end

  def item_key(item)
    "#{item['sale_item_type']}#{item['sale_item_id']}"
  end

  def redownload_url(key)
    format(REDOWNLOAD_URL, key)
  end

  # A complete profile-page blob. +items+ is an array of sale_item hashes;
  # every item is given a redownload URL unless +downloadable: false+.
  #
  # Note that hidden items read their download URL out of collection_data, not
  # hidden_data -- verified against live pagedata, which carries no
  # hidden-specific URL map.
  def collection_blob(items, hidden: [], downloadable: true, last_token: nil, visible_count: nil)
    everyone = items + hidden
    blob = {
      'collection_count' => items.length,
      'fan_data' => { 'fan_id' => FAN_ID },
      'item_cache' => { 'collection' => by_key(items), 'hidden' => by_key(hidden) },
      'collection_data' => {
        'item_count' => items.length,
        'last_token' => last_token,
        'redownload_urls' => downloadable ? urls_by_key(everyone) : {}
      },
      'hidden_data' => { 'item_count' => hidden.length, 'last_token' => nil }
    }
    blob['visible_item_count'] = visible_count unless visible_count.nil?
    blob
  end

  # A response from the fancollection paged endpoints: a window of items plus
  # the cursor to resume from.
  def page_response(items, more_available: false, last_token: nil)
    {
      'items' => items,
      'redownload_urls' => urls_by_key(items),
      'more_available' => more_available,
      'last_token' => last_token
    }
  end

  # One line of a Netscape-format cookie jar, as browsers export it.
  def cookie_line(name, value, host: '.bandcamp.com', secure: true)
    [host, 'TRUE', '/', secure ? 'TRUE' : 'FALSE', '2000000000', name, value].join("\t")
  end

  def by_key(items)
    items.to_h { |item| [item_key(item), item] }
  end

  def urls_by_key(items)
    items.to_h { |item| [key = item_key(item), redownload_url(key)] }
  end
end
