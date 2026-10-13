# frozen_string_literal: true

require_relative '../spec_helper'

# collection_summary, fetch_collection_items and fetch_hidden_items differ
# only in their arguments and endpoint; all three post JSON, unwrap the reply
# and answer nil when anything goes wrong. One set of examples covers all three.
RSpec.shared_examples 'a JSON API reader' do
  subject(:parsed) { client.public_send(reader_method, *reader_args) }

  before { stub_request(:post, api_url).to_return(body: api_body) }

  context 'when the server returns JSON' do
    it 'parses the body' do
      expect(parsed).to eq(expected)
    end
  end

  context 'when the server rejects the request' do
    before { stub_request(:post, api_url).to_return(status: 500, body: 'boom') }

    it { is_expected.to be_nil }
  end

  context 'when the request fails' do
    before { stub_request(:post, api_url).to_raise(StandardError) }

    it { is_expected.to be_nil }
  end
end

RSpec.describe BandcampDlRb::Client do
  subject(:client) { described_class.new(identity) }

  let(:identity) { 'test-identity-value' }
  let(:username) { 'testuser' }
  let(:profile_url) { 'https://bandcamp.com/testuser' }

  # Extra arguments for the shared example below; #get takes only a url.
  let(:sending_args) { [] }

  include BandcampFixtures

  # The cookie must only ever ride along to a host Bandcamp owns; leaking it
  # to a redirect target would hand the session to whoever controls that host.
  shared_examples 'an unauthenticated request' do
    it 'omits the Cookie header' do
      client.public_send(sending_method, url, *sending_args)
      expect(a_request(:any, url).with { |req| !req.headers.key?('Cookie') }).to have_been_made
    end
  end

  it 'exposes the identity' do
    expect(client.identity).to eq(identity)
  end

  describe '#get' do
    subject(:response) { client.get(url) }

    let(:url) { 'https://bandcamp.com/api/test' }

    before { stub_request(:get, url).to_return(body: '{}') }

    context 'with the apex domain' do
      let(:url) { 'https://bandcamp.com/api/test' }

      it 'sends the identity cookie' do
        client.get(url)
        expect(a_request(:get, url).with(headers: { 'Cookie' => "identity=#{identity}" })).to have_been_made
      end
    end

    context 'with a bandcamp.com subdomain' do
      let(:url) { 'https://radiohead.bandcamp.com/album/in-rainbows' }

      it 'sends the identity cookie' do
        client.get(url)
        expect(a_request(:get, url).with(headers: { 'Cookie' => "identity=#{identity}" })).to have_been_made
      end
    end

    context 'with a host off the allowlist' do
      let(:url) { 'https://example.com/api/test' }
      let(:sending_method) { :get }

      it_behaves_like 'an unauthenticated request'
    end

    context 'with a lookalike domain' do
      let(:url) { 'https://notbandcamp.com/api/test' }
      let(:sending_method) { :get }

      it_behaves_like 'an unauthenticated request'
    end

    context 'when the server responds' do
      it 'returns the response' do
        expect(response.code).to eq('200')
      end
    end
  end

  describe '#post_json' do
    subject(:response) { client.post_json(url, payload) }

    let(:url) { 'https://bandcamp.com/api/x' }
    let(:payload) { { 'a' => 1 } }

    before { stub_request(:post, url).to_return(body: '{}') }

    context 'with an allowlisted host' do
      let(:sending_args) { [payload] }

      it 'sends the JSON body' do
        client.post_json(url, payload)
        expect(a_request(:post, url).with(body: '{"a":1}')).to have_been_made
      end

      it 'sets a JSON content type' do
        client.post_json(url, payload)
        expect(a_request(:post, url).with(headers: { 'Content-Type' => 'application/json' })).to have_been_made
      end

      it 'sends the identity cookie' do
        client.post_json(url, payload)
        expect(a_request(:post, url).with(headers: { 'Cookie' => "identity=#{identity}" })).to have_been_made
      end
    end

    context 'with a host off the allowlist' do
      let(:url) { 'https://example.com/api/x' }
      let(:sending_method) { :post_json }
      let(:sending_args) { [payload] }

      it_behaves_like 'an unauthenticated request'
    end

    context 'when the server responds' do
      it 'returns the response' do
        expect(response.code).to eq('200')
      end
    end
  end

  describe '#get_pagedata' do
    subject(:pagedata) { client.get_pagedata(profile_url) }

    context 'with a pagedata div' do
      let(:blob) { { 'collection_count' => 1, 'fan_data' => { 'fan_id' => 4242 } } }

      before { stub_request(:get, profile_url).to_return(body: pagedata_page(blob)) }

      it 'returns the decoded data-blob' do
        expect(pagedata).to eq(blob)
      end
    end

    context 'without a pagedata div' do
      before { stub_request(:get, profile_url).to_return(body: '<html>No pagedata here</html>') }

      it { is_expected.to be_nil }
    end

    context 'when the server rejects the request' do
      before { stub_request(:get, profile_url).to_return(status: 404) }

      it { is_expected.to be_nil }
    end

    context 'when the request fails' do
      before { stub_request(:get, profile_url).to_raise(StandardError) }

      it { is_expected.to be_nil }
    end
  end

  describe '#get_html' do
    subject(:html) { client.get_html(url) }

    let(:url) { 'https://radiohead.bandcamp.com/album/in-rainbows' }

    context 'when the page loads' do
      before { stub_request(:get, url).to_return(body: '<html>OK</html>') }

      it { is_expected.to eq('<html>OK</html>') }
    end

    context 'when the page does not exist' do
      let(:url) { 'https://radiohead.bandcamp.com/album/missing' }

      before { stub_request(:get, url).to_return(status: 404) }

      it { is_expected.to be_nil }
    end

    context 'when the request fails' do
      before { stub_request(:get, url).to_raise(StandardError) }

      it { is_expected.to be_nil }
    end
  end

  describe '#get_collection' do
    subject(:items) { client.get_collection(username, **options) }

    let(:options) { {} }
    let(:albums) { [sale_item(id: 100, artist: 'Artist One', title: 'Album One')] }
    let(:blob) { collection_blob(albums) }

    before { stub_request(:get, profile_url).to_return(body: pagedata_page(blob)) }

    context 'when the profile page lists a purchase' do
      it 'keys the item by sale item id' do
        expect(items.keys).to eq(['a100'])
      end

      it 'attaches the redownload url' do
        expect(items['a100']['redownload_url']).to eq(redownload_url('a100'))
      end
    end

    context 'when an item has no redownload url' do
      let(:blob) { collection_blob(albums, downloadable: false) }

      it 'drops the item' do
        expect(items).to eq({})
      end
    end

    context 'when the profile page has no pagedata' do
      before { stub_request(:get, profile_url).to_return(status: 404) }

      it { is_expected.to eq({}) }
    end

    context 'when the page carries no collection count' do
      let(:blob) { { 'fan_data' => { 'fan_id' => BandcampFixtures::FAN_ID } } }

      it { is_expected.to eq({}) }
    end

    context 'when hidden items are requested' do
      let(:hidden) { [sale_item(id: 300, artist: 'Hidden Artist', title: 'Hidden Album')] }
      let(:blob) { collection_blob(albums, hidden: hidden) }
      let(:options) { { include_hidden: true } }

      it 'includes the hidden items' do
        expect(items.keys).to contain_exactly('a100', 'a300')
      end
    end

    context 'when hidden items are requested but the profile page is missing one' do
      # A hidden item's download URL lives in collection_data['redownload_urls']
      # -- the same map visible items use. hidden_data carries no URL map at
      # all, verified against live pagedata, so there is no hidden-specific map
      # to read from. A phantom entry here would be ignored by merge_hidden_items
      # and make this example look like it covers a path that does not exist.
      let(:hidden) { [sale_item(id: 300, artist: 'Hidden Artist', title: 'Hidden Album')] }
      let(:blob) { collection_blob(albums, hidden: hidden) }
      let(:options) { { include_hidden: true } }

      it 'still resolves the hidden download url' do
        expect(items['a300']['redownload_url']).to eq(redownload_url('a300'))
      end
    end

    context 'when hidden items are not requested' do
      let(:hidden) { [sale_item(id: 300, artist: 'Hidden Artist', title: 'Hidden Album')] }
      let(:blob) { collection_blob(albums, hidden: hidden) }

      it 'leaves them out' do
        expect(items.keys).to eq(['a100'])
      end
    end

    context 'when the hidden item count is null' do
      # Bandcamp omits the count on a profile whose hidden list has never been
      # paginated; the walk must not treat a nil count as "no hidden items".
      let(:hidden) { [sale_item(id: 300, artist: 'Hidden Artist', title: 'Hidden Album')] }
      let(:blob) do
        collection_blob(albums, hidden: hidden).tap { |b| b['hidden_data']['item_count'] = nil }
      end
      let(:options) { { include_hidden: true } }

      it 'still finds the visible items' do
        expect(items.keys).to include('a100')
      end
    end

    context 'when date filters are given' do
      let(:albums) do
        [
          sale_item(id: 100, artist: 'One', title: 'Album One',
                    'purchased' => '01 Jan 2023 00:00:00 GMT'),
          sale_item(id: 200, artist: 'Two', title: 'Album Two',
                    'purchased' => '01 Jan 2024 00:00:00 GMT'),
          sale_item(id: 300, artist: 'Three', title: 'Album Three',
                    'purchased' => '01 Jan 2025 00:00:00 GMT')
        ]
      end

      context 'with a since date' do
        let(:options) { { since: Date.new(2024, 1, 1) } }

        it 'keeps purchases on or after it' do
          expect(items.keys).to contain_exactly('a200', 'a300')
        end
      end

      context 'with an until date' do
        let(:options) { { until_date: Date.new(2024, 1, 1) } }

        it 'keeps purchases before it' do
          expect(items.keys).to contain_exactly('a100')
        end
      end

      context 'with a date range' do
        let(:options) { { since: Date.new(2024, 1, 1), until_date: Date.new(2025, 1, 1) } }

        it 'keeps purchases inside it' do
          expect(items.keys).to contain_exactly('a200')
        end
      end

      context 'without a filter' do
        it 'keeps every purchase' do
          expect(items.keys).to contain_exactly('a100', 'a200', 'a300')
        end
      end

      context 'with an item bought before filtering existed' do
        let(:albums) do
          [sale_item(id: 400, artist: 'Four', title: 'Album Four')]
        end
        let(:options) { { since: Date.new(2024, 1, 1) } }

        it 'keeps the item' do
          expect(items.keys).to eq(['a400'])
        end
      end

      context 'with an unparseable purchase date' do
        let(:albums) do
          [sale_item(id: 400, artist: 'Four', title: 'Album Four', 'purchased' => 'not-a-date')]
        end
        let(:options) { { since: Date.new(2024, 1, 1) } }

        it 'keeps the item' do
          expect(items.keys).to eq(['a400'])
        end
      end
    end

    # Bandcamp's collection endpoint treats `count` as a page size but advances
    # its cursor by a fixed step, so a 100-item page yields only a handful of
    # new items and the rest repeat the previous page. A client that budgets
    # requests against the item count advertised on the profile page therefore
    # burns that budget on duplicates and truncates the walk; the server's
    # `more_available` flag is the only authoritative end-of-collection signal.
    context 'when pages overlap' do
      subject(:client) { described_class.new(identity, page_size: page_size) }

      let(:cursor_step) { 20 }
      let(:total_items) { 172 }
      let(:page_size) { BandcampDlRb::DEFAULT_PAGE_SIZE }
      let(:requested_counts) { [] }
      let(:all_items) do
        Array.new(total_items) { |n| sale_item(id: 1_000_000 + n, artist: "Artist #{n}", title: "Album #{n}") }
      end
      let(:blob) { collection_blob([], last_token: 'tok-0') }

      # One page as the real API serves it: a window of `page_size` items
      # starting at the cursor, with the cursor then advanced by cursor_step.
      def page_from(offset)
        window = all_items[offset, page_size] || []
        next_offset = [offset + cursor_step, total_items].min
        page_response(window, more_available: next_offset < total_items, last_token: "tok-#{next_offset}")
      end

      before do
        stub_request(:post, BandcampDlRb::COLLECTION_ITEMS_URL).to_return do |request|
          payload = JSON.parse(request.body)
          requested_counts << payload['count']
          offset = payload.fetch('older_than_token').split('-').last.to_i
          { body: JSON.generate(page_from(offset)) }
        end
      end

      it 'walks past the first page' do
        expect(items.length).to eq(total_items)
      end

      it 'reaches the tail of the collection' do
        expect(items.keys).to include(item_key(all_items.last))
      end

      it 'asks for the configured page size' do
        items
        expect(requested_counts).to all(eq(page_size))
      end

      it 'defaults the page size' do
        items
        expect(requested_counts).to all(eq(BandcampDlRb::DEFAULT_PAGE_SIZE))
      end

      context 'when the cursor stops advancing' do
        before do
          stub_request(:post, BandcampDlRb::COLLECTION_ITEMS_URL).to_return(
            body: JSON.generate(page_response(all_items.first(3), more_available: true, last_token: 'tok-0'))
          )
        end

        it 'stops after one page' do
          items
          expect(a_request(:post, BandcampDlRb::COLLECTION_ITEMS_URL)).to have_been_made.once
        end
      end

      context 'when a page comes back empty' do
        before do
          stub_request(:post, BandcampDlRb::COLLECTION_ITEMS_URL).to_return(
            body: JSON.generate(page_response([], more_available: true, last_token: 'tok-9'))
          )
        end

        it 'stops after one page' do
          items
          expect(a_request(:post, BandcampDlRb::COLLECTION_ITEMS_URL)).to have_been_made.once
        end
      end

      context 'when a page returns no token' do
        before do
          stub_request(:post, BandcampDlRb::COLLECTION_ITEMS_URL).to_return(
            body: JSON.generate(page_response(all_items.first(3), more_available: true, last_token: nil))
          )
        end

        it 'stops after one page' do
          items
          expect(a_request(:post, BandcampDlRb::COLLECTION_ITEMS_URL)).to have_been_made.once
        end
      end
    end
  end

  describe '#collection_summary' do
    let(:expected) { { 'item_count' => 42 } }
    let(:api_body) { '{"collection_summary": {"item_count": 42}}' }
    let(:api_url) { BandcampDlRb::COLLECTION_SUMMARY_URL }
    let(:reader_args) { [] }
    let(:reader_method) { :collection_summary }

    it_behaves_like 'a JSON API reader'
  end

  describe '#fetch_collection_items' do
    let(:expected) { { 'items' => [{ 'id' => 1 }], 'more_available' => false } }
    let(:api_body) { '{"items": [{"id": 1}], "more_available": false}' }
    let(:api_url) { BandcampDlRb::COLLECTION_ITEMS_URL }
    let(:reader_args) { [BandcampFixtures::FAN_ID, 'token', 100] }
    let(:reader_method) { :fetch_collection_items }

    it_behaves_like 'a JSON API reader'
  end

  describe '#fetch_hidden_items' do
    let(:expected) { { 'items' => [{ 'id' => 1 }], 'more_available' => false } }
    let(:api_body) { '{"items": [{"id": 1}], "more_available": false}' }
    let(:api_url) { BandcampDlRb::HIDDEN_ITEMS_URL }
    let(:reader_args) { [BandcampFixtures::FAN_ID, 'token', 100] }
    let(:reader_method) { :fetch_hidden_items }

    it_behaves_like 'a JSON API reader'
  end

  describe '#parse_tralbum' do
    subject(:parsed) { client.parse_tralbum(html) }

    context 'with an album page' do
      let(:html) { tralbum_page(artist: 'Radiohead', title: 'In Rainbows', id: 2_162_872_411) }

      let(:expected_item) do
        {
          'band_name' => 'Radiohead',
          'item_title' => 'In Rainbows',
          'tralbum_id' => 2_162_872_411,
          'tralbum_type' => 'a'
        }
      end

      it 'maps the page onto a download item' do
        expect(parsed).to eq(
          expected_item
        )
      end
    end

    context 'with a track page' do
      let(:html) { tralbum_page(artist: 'Aphex Twin', title: 'Windowlicker', id: 123_456, item_type: 'track') }

      it { expect(parsed['tralbum_type']).to eq('t') }
    end

    context 'without a tralbum attribute' do
      let(:html) { '<html><body>No data here</body></html>' }

      it { is_expected.to be_nil }
    end

    context 'with malformed tralbum JSON' do
      let(:html) { '<div data-tralbum="NOT_JSON"></div>' }

      it { is_expected.to be_nil }
    end
  end

  # A collection entry is keyed by sale item ("p403398974") while a Bandcamp
  # page URL carries a tralbum id ("a1546900568"). The two keyspaces never
  # overlap, so the lookup has to join on tralbum_id/tralbum_type.
  describe '#find_item_in_collection' do
    subject(:found) { client.find_item_in_collection(items, tralbum) }

    let(:items) do
      {
        'p403398974' => sale_item(id: 403_398_974, artist: 'Dizgo', title: 'Globe Hall', type: 'p',
                                  'tralbum_id' => 1_546_900_568, 'tralbum_type' => 'a'),
        'i390012675' => sale_item(id: 390_012_675, artist: 'Aphex Twin', title: 'Windowlicker', type: 'i',
                                  'tralbum_id' => 1_188_310_021, 'tralbum_type' => 't')
      }
    end

    context 'with a matching album' do
      let(:tralbum) { { 'tralbum_id' => 1_546_900_568, 'tralbum_type' => 'a' } }

      it { is_expected.to eq(items['p403398974']) }
    end

    context 'with a matching physical item' do
      let(:tralbum) { { 'tralbum_id' => 1_188_310_021, 'tralbum_type' => 't' } }

      it { is_expected.to eq(items['i390012675']) }
    end

    context 'with no matching tralbum id' do
      let(:tralbum) { { 'tralbum_id' => 999, 'tralbum_type' => 'a' } }

      it { is_expected.to be_nil }
    end

    context 'with a matching id but a different type' do
      let(:tralbum) { { 'tralbum_id' => 1_546_900_568, 'tralbum_type' => 't' } }

      it { is_expected.to be_nil }
    end

    context 'without any tralbum id' do
      let(:tralbum) { { 'tralbum_type' => 'a' } }

      it { is_expected.to be_nil }
    end

    context 'with a tralbum id that is not a sale id' do
      # The old lookup built "a1546900568" and asked for that key, which can
      # never be a collection key.
      it 'does not key on it' do
        expect(items.keys).not_to include('a1546900568')
      end
    end
  end

  describe '#filter_by_ids' do
    subject(:filtered) { client.filter_by_ids(items, ids) }

    let(:items) do
      {
        'a100' => { 'band_name' => 'Radiohead', 'item_title' => 'Kid A' },
        'a200' => { 'band_name' => 'Radiohead', 'item_title' => 'Amnesiac' },
        't300' => { 'band_name' => 'Aphex Twin', 'item_title' => 'Windowlicker' }
      }
    end

    context 'with a single id' do
      let(:ids) { 'a100' }

      it { expect(filtered.keys).to eq(['a100']) }
    end

    context 'with comma-separated ids' do
      let(:ids) { 'a100,t300' }

      it { expect(filtered.keys).to contain_exactly('a100', 't300') }
    end

    context 'with an array of ids' do
      let(:ids) { %w[a100 a200] }

      it { expect(filtered.keys).to contain_exactly('a100', 'a200') }
    end

    context 'with padded ids' do
      let(:ids) { ' a100 , t300 ' }

      it { expect(filtered.keys).to contain_exactly('a100', 't300') }
    end

    context 'with an id the collection does not hold' do
      let(:ids) { 'a999' }

      it { is_expected.to eq({}) }
    end

    context 'with an empty list' do
      let(:ids) { '' }

      it { is_expected.to eq({}) }
    end
  end

  describe '#filter_collection' do
    subject(:filtered) { client.filter_collection(items, pattern) }

    let(:items) do
      {
        'a100' => { 'band_name' => 'Radiohead', 'item_title' => 'Kid A' },
        'a200' => { 'band_name' => 'Radiohead', 'item_title' => 'Amnesiac' },
        't300' => { 'band_name' => 'Aphex Twin', 'item_title' => 'Windowlicker' },
        't400' => { 'band_name' => nil, 'item_title' => 'Kid A Mnesia' }
      }
    end

    context 'with an artist substring' do
      let(:pattern) { 'Aphex' }

      it { expect(filtered.keys).to eq(['t300']) }
    end

    context 'with a title substring' do
      let(:pattern) { 'windowlicker' }

      it { expect(filtered.keys).to eq(['t300']) }
    end

    context 'with a differently cased pattern' do
      let(:pattern) { 'AMNESIAC' }

      it { expect(filtered.keys).to eq(['a200']) }
    end

    context 'with a substring spanning both fields' do
      let(:pattern) { 'kid' }

      it { expect(filtered.keys).to contain_exactly('a100', 't400') }
    end

    context 'with a precompiled Regexp' do
      let(:pattern) { Regexp.new('aphex', Regexp::IGNORECASE) }

      it { expect(filtered.keys).to eq(['t300']) }
    end

    context 'with a pattern nothing matches' do
      let(:pattern) { 'zzzz' }

      it { is_expected.to eq({}) }
    end

    context 'with an item whose artist is nil' do
      # "a mnesia" rather than "mnesia": the latter is a substring of
      # "Amnesiac" and would silently match the wrong item.
      let(:pattern) { 'a mnesia' }

      it { expect(filtered.keys).to eq(['t400']) }
    end
  end
end
