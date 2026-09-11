# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe BandcampDlRb::Client do
  let(:identity) { 'test-identity-value' }
  subject(:client) { described_class.new(identity) }

  it 'exposes the identity' do
    expect(client.identity).to eq(identity)
  end

  describe '#get' do
    def capture_get_request(url)
      request = nil
      allow(Net::HTTP).to receive(:start) do |_host, _port, **_opts, &block|
        http = double('http')
        allow(http).to receive(:request) do |r|
          request = r
          instance_double(Net::HTTPSuccess, body: '{}')
        end
        block.call(http)
      end
      client.get(url)
      request
    end

    it 'sets the Cookie header for bandcamp.com hosts' do
      req = capture_get_request('https://bandcamp.com/api/test')
      expect(req['Cookie']).to eq('identity=test-identity-value')
    end

    it 'sets the Cookie header for *.bandcamp.com hosts' do
      req = capture_get_request('https://radiohead.bandcamp.com/album/in-rainbows')
      expect(req['Cookie']).to eq('identity=test-identity-value')
    end

    it 'omits the Cookie header for non-bandcamp hosts' do
      req = capture_get_request('https://example.com/api/test')
      expect(req['Cookie']).to be_nil
    end

    it 'omits the Cookie header for lookalike subdomains' do
      req = capture_get_request('https://notbandcamp.com/api/test')
      expect(req['Cookie']).to be_nil
    end
  end

  describe '#get_pagedata' do
    let(:ok_response) do
      Class.new do
        def body
          blob = { 'collection_count' => 1, 'fan_data' => { 'fan_id' => 4242 } }
          format('<div id="pagedata" data-blob="%s"></div>', CGI.escapeHTML(JSON.generate(blob)))
        end

        def is_a?(_klass)
          true
        end
      end.new
    end

    it 'parses the data-blob json from the pagedata div' do
      allow(client).to receive(:get).and_return(ok_response)
      expect(client.get_pagedata('https://bandcamp.com/testuser'))
        .to eq('collection_count' => 1, 'fan_data' => { 'fan_id' => 4242 })
    end

    it 'returns nil for a non-success response' do
      bad = Class.new { def is_a?(_klass) = false }.new
      allow(client).to receive(:get).and_return(bad)
      expect(client.get_pagedata('https://bandcamp.com/testuser')).to be_nil
    end
  end

  describe '#post_json' do
    def capture_post_request(url)
      request = nil
      allow(Net::HTTP).to receive(:start) do |_host, _port, **_opts, &block|
        http = double('http')
        allow(http).to receive(:request) do |r|
          request = r
          instance_double(Net::HTTPSuccess, body: '{}')
        end
        block.call(http)
      end
      client.post_json(url, { 'a' => 1 })
      request
    end

    it 'sends the Cookie header and a JSON body' do
      req = capture_post_request('https://bandcamp.com/api/x')
      expect(req['Cookie']).to eq('identity=test-identity-value')
      expect(req['Content-Type']).to eq('application/json')
      expect(JSON.parse(req.body)).to eq('a' => 1)
    end

    it 'omits the Cookie header for non-bandcamp hosts' do
      req = capture_post_request('https://example.com/api/x')
      expect(req['Cookie']).to be_nil
      expect(req['Content-Type']).to eq('application/json')
      expect(JSON.parse(req.body)).to eq('a' => 1)
    end
  end

  describe '#get_collection' do
    let(:pagedata) do
      {
        'collection_count' => 2,
        'fan_data' => { 'fan_id' => 123 },
        'item_cache' => {
          'collection' => {
            'a100' => {
              'sale_item_type' => 'a',
              'sale_item_id' => 100,
              'band_name' => 'Artist One',
              'item_title' => 'Album One',
              'tralbum_type' => 'a',
              'featured_track' => {},
              'purchased' => '01 Jan 2025 00:00:00 GMT'
            }
          },
          'hidden' => {}
        },
        'collection_data' => {
          'item_count' => 2,
          'last_token' => nil,
          'redownload_urls' => { 'a100' => 'https://bandcamp.com/redownload/1' }
        },
        'hidden_data' => { 'item_count' => 0, 'last_token' => nil }
      }
    end

    before do
      allow(client).to receive(:get_pagedata).and_return(pagedata)
      allow(client).to receive(:fetch_collection_items).and_return(
        'items' => [{
          'sale_item_type' => 'a',
          'sale_item_id' => 200,
          'band_name' => 'Artist Two',
          'item_title' => 'Album Two',
          'tralbum_type' => 'a'
        }],
        'redownload_urls' => { 'a200' => 'https://bandcamp.com/redownload/2' },
        'last_token' => nil
      )
      allow(client).to receive(:fetch_hidden_items).and_return(
        'items' => [],
        'redownload_urls' => {},
        'last_token' => nil
      )
    end

    it 'returns items with redownload urls' do
      items = client.get_collection('testuser')
      expect(items.keys).to include('a100')
      expect(items['a100']['redownload_url']).to eq('https://bandcamp.com/redownload/1')
    end

    it 'returns empty hash when pagedata is missing' do
      allow(client).to receive(:get_pagedata).and_return(nil)
      expect(client.get_collection('nouser')).to eq({})
    end

    it 'includes hidden items when requested' do
      pagedata['item_cache']['hidden'] = {
        'a300' => {
          'sale_item_type' => 'a',
          'sale_item_id' => 300,
          'band_name' => 'Hidden Artist',
          'item_title' => 'Hidden Album',
          'tralbum_type' => 'a'
        }
      }
      pagedata['visible_item_count'] = nil
      pagedata['hidden_data'] = {
        'item_count' => 1,
        'last_token' => nil,
        'redownload_urls' => { 'a300' => 'https://bandcamp.com/redownload/3' }
      }
      pagedata['collection_data']['redownload_urls'] = {
        'a100' => 'https://bandcamp.com/redownload/1',
        'a300' => 'https://bandcamp.com/redownload/3'
      }

      items = client.get_collection('testuser', include_hidden: true)
      expect(items.keys).to include('a300')
      expect(items['a300']['redownload_url']).to eq('https://bandcamp.com/redownload/3')
    end
  end

  describe '#get_html' do
    it 'returns the response body on success' do
      resp = instance_double(Net::HTTPSuccess, body: '<html>OK</html>')
      allow(resp).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
      allow(client).to receive(:get).and_return(resp)

      expect(client.get_html('https://radiohead.bandcamp.com/album/in-rainbows')).to eq('<html>OK</html>')
    end

    it 'returns nil on non-success response' do
      resp = instance_double(Net::HTTPNotFound)
      allow(resp).to receive(:is_a?).with(Net::HTTPSuccess).and_return(false)
      allow(client).to receive(:get).and_return(resp)

      expect(client.get_html('https://radiohead.bandcamp.com/album/missing')).to be_nil
    end

    it 'returns nil on error' do
      allow(client).to receive(:get).and_raise(StandardError, 'timeout')

      expect(client.get_html('https://radiohead.bandcamp.com/album/in-rainbows')).to be_nil
    end
  end

  describe '#parse_tralbum' do
    it 'extracts artist, title, id, and item_type from album page HTML' do
      tralbum_data = {
        'artist' => 'Radiohead',
        'current' => { 'title' => 'In Rainbows' },
        'id' => 2_162_872_411,
        'item_type' => 'album'
      }
      html = <<~HTML
        <div id="pagedata" data-blob="{}"></div>
        <div data-tralbum='#{CGI.escapeHTML(JSON.generate(tralbum_data))}'></div>
      HTML

      result = client.parse_tralbum(html)
      expect(result).to eq(
        'band_name' => 'Radiohead',
        'item_title' => 'In Rainbows',
        'sale_item_id' => 2_162_872_411,
        'sale_item_type' => 'a'
      )
    end

    it 'maps item_type "track" to sale_item_type "t"' do
      tralbum_data = {
        'artist' => 'Aphex Twin',
        'current' => { 'title' => 'Windowlicker' },
        'id' => 123_456,
        'item_type' => 'track'
      }
      html = %(<div data-tralbum='#{CGI.escapeHTML(JSON.generate(tralbum_data))}'></div>)

      result = client.parse_tralbum(html)
      expect(result['sale_item_type']).to eq('t')
    end

    it 'returns nil when data-tralbum attribute is missing' do
      expect(client.parse_tralbum('<html><body>No data here</body></html>')).to be_nil
    end

    it 'returns nil when tralbum JSON is malformed' do
      html = %(<div data-tralbum="NOT_JSON"></div>)
      expect(client.parse_tralbum(html)).to be_nil
    end
  end

  describe '#find_item_in_collection' do
    let(:items) do
      {
        'a100' => {
          'sale_item_type' => 'a', 'sale_item_id' => 100,
          'band_name' => 'Radiohead', 'item_title' => 'Kid A'
        },
        't200' => {
          'sale_item_type' => 't', 'sale_item_id' => 200,
          'band_name' => 'Aphex Twin', 'item_title' => 'Windowlicker'
        }
      }
    end

    it 'finds an album by sale_item_id and type' do
      tralbum = { 'sale_item_type' => 'a', 'sale_item_id' => 100 }
      result = client.find_item_in_collection(items, tralbum)
      expect(result).to eq(items['a100'])
    end

    it 'finds a track by sale_item_id and type' do
      tralbum = { 'sale_item_type' => 't', 'sale_item_id' => 200 }
      result = client.find_item_in_collection(items, tralbum)
      expect(result).to eq(items['t200'])
    end

    it 'returns nil when no match exists' do
      tralbum = { 'sale_item_type' => 'a', 'sale_item_id' => 999 }
      expect(client.find_item_in_collection(items, tralbum)).to be_nil
    end

    it 'returns nil when type does not match' do
      tralbum = { 'sale_item_type' => 't', 'sale_item_id' => 100 }
      expect(client.find_item_in_collection(items, tralbum)).to be_nil
    end
  end

  describe '#filter_by_ids' do
    let(:items) do
      {
        'a100' => { 'band_name' => 'Radiohead', 'item_title' => 'Kid A' },
        'a200' => { 'band_name' => 'Radiohead', 'item_title' => 'Amnesiac' },
        't300' => { 'band_name' => 'Aphex Twin', 'item_title' => 'Windowlicker' }
      }
    end

    it 'filters items by a single ID' do
      result = client.filter_by_ids(items, 'a100')
      expect(result.keys).to eq(['a100'])
    end

    it 'filters items by comma-separated IDs' do
      result = client.filter_by_ids(items, 'a100,t300')
      expect(result.keys).to contain_exactly('a100', 't300')
    end

    it 'filters items by an array of IDs' do
      result = client.filter_by_ids(items, %w[a100 a200])
      expect(result.keys).to contain_exactly('a100', 'a200')
    end

    it 'strips whitespace from IDs' do
      result = client.filter_by_ids(items, ' a100 , t300 ')
      expect(result.keys).to contain_exactly('a100', 't300')
    end

    it 'returns empty hash when no IDs match' do
      result = client.filter_by_ids(items, 'a999')
      expect(result).to eq({})
    end

    it 'returns empty hash for empty input' do
      result = client.filter_by_ids(items, '')
      expect(result).to eq({})
    end
  end

  describe '#filter_collection' do
    let(:items) do
      {
        'a100' => { 'band_name' => 'Radiohead', 'item_title' => 'Kid A' },
        'a200' => { 'band_name' => 'Radiohead', 'item_title' => 'Amnesiac' },
        't300' => { 'band_name' => 'Aphex Twin', 'item_title' => 'Windowlicker' },
        't400' => { 'band_name' => nil, 'item_title' => 'Kid A Mnesia' }
      }
    end

    it 'matches on artist name' do
      result = client.filter_collection(items, 'Aphex')
      expect(result.keys).to eq(['t300'])
    end

    it 'matches on title' do
      result = client.filter_collection(items, 'windowlicker')
      expect(result.keys).to eq(['t300'])
    end

    it 'is case-insensitive' do
      result = client.filter_collection(items, 'AMNESIAC')
      expect(result.keys).to eq(['a200'])
    end

    it 'matches a substring anywhere in artist or title' do
      result = client.filter_collection(items, 'kid')
      expect(result.keys).to contain_exactly('a100', 't400')
    end

    it 'accepts a precompiled Regexp' do
      result = client.filter_collection(items, Regexp.new('aphex', Regexp::IGNORECASE))
      expect(result.keys).to eq(['t300'])
    end

    it 'returns empty hash when nothing matches' do
      result = client.filter_collection(items, 'zzzz')
      expect(result).to eq({})
    end

    it 'does not raise when a field is nil' do
      expect { client.filter_collection(items, 'mnesia') }.not_to raise_error
    end
  end

  describe 'host allowlisting' do
    it 'matches bandcamp.com and its subdomains' do
      expect(BandcampDlRb.bc_host?('bandcamp.com')).to be true
      expect(BandcampDlRb.bc_host?('radiohead.bandcamp.com')).to be true
      expect(BandcampDlRb.bc_host?('example.com')).to be false
      expect(BandcampDlRb.bc_host?('notbandcamp.com')).to be false
    end

    it 'extends the allowlist to bcbits.com for downloads' do
      expect(BandcampDlRb.download_host?('bandcamp.com')).to be true
      expect(BandcampDlRb.download_host?('bcbits.com')).to be true
      expect(BandcampDlRb.download_host?('d1.bcbits.com')).to be true
      expect(BandcampDlRb.download_host?('example.com')).to be false
    end
  end
end
