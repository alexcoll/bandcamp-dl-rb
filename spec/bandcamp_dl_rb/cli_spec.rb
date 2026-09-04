# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe BandcampDlRb::CLI do
  describe '.parse_args' do
    it 'parses library and username' do
      options = described_class.parse_args(['--library', '/mnt/music', 'myuser'])
      expect(options[:library]).to eq('/mnt/music')
      expect(options[:username]).to eq('myuser')
    end

    it 'defaults format to flac' do
      options = described_class.parse_args(['--library', '/x', 'u'])
      expect(options[:format]).to eq('flac')
    end

    it 'accepts a custom format' do
      options = described_class.parse_args(['--library', '/x', '--format', 'wav', 'u'])
      expect(options[:format]).to eq('wav')
    end

    it 'parses include-hidden flag' do
      options = described_class.parse_args(['--library', '/x', '--include-hidden', 'u'])
      expect(options[:include_hidden]).to eq(true)
    end

    it 'parses since/until dates' do
      options = described_class.parse_args(['--library', '/x', '--since', '2024-01-01', 'u'])
      expect(options[:since]).to eq(Date.new(2024, 1, 1))
    end

    it 'parses the browser option' do
      options = described_class.parse_args(['--library', '/x', '--browser', 'chrome', 'u'])
      expect(options[:browser]).to eq('chrome')
    end

    it 'accepts safari as a browser option' do
      options = described_class.parse_args(['--library', '/x', '--browser', 'safari', 'u'])
      expect(options[:browser]).to eq('safari')
    end

    it 'defaults browser to auto' do
      options = described_class.parse_args(['--library', '/x', 'u'])
      expect(options[:browser]).to eq('auto')
    end
  end

  describe '.run' do
    it 'returns exit code 1 when username and library are missing' do
      err = StringIO.new
      out = StringIO.new
      code = described_class.run([], out: out, err: err)
      expect(code).to eq(1)
    end
  end
end
