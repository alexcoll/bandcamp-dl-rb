# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe BandcampDlRb::Client do
  let(:identity) { 'test-identity-value' }
  subject(:client) { described_class.new(identity) }

  it 'exposes the identity' do
    expect(client.identity).to eq(identity)
  end

  describe '#get' do
    it 'sets the Cookie header from the identity' do
      req = nil
      allow(Net::HTTP).to receive(:start) do |_host, _port, **_opts, &block|
        http = double('http')
        allow(http).to receive(:request) do |r|
          req = r
          instance_double(Net::HTTPSuccess, body: '{}')
        end
        block.call(http)
      end

      client.get('https://bandcamp.com/api/test')
      expect(req['Cookie']).to eq('identity=test-identity-value')
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
    it 'sends the Cookie header and a JSON body' do
      req = nil
      allow(Net::HTTP).to receive(:start) do |_host, _port, **_opts, &block|
        http = double('http')
        allow(http).to receive(:request) do |r|
          req = r
          instance_double(Net::HTTPSuccess, body: '{}')
        end
        block.call(http)
      end

      client.post_json('https://bandcamp.com/api/x', { 'a' => 1 })
      expect(req['Cookie']).to eq('identity=test-identity-value')
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
end
