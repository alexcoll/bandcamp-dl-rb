# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe BandcampDlRb::CompletionsGenerator do
  let(:generator) { described_class.new }
  let(:temp_dir) { Dir.mktmpdir }

  after { FileUtils.rm_rf(temp_dir) }

  describe '#write' do
    before { generator.write(temp_dir) }

    it 'creates the bash completion file' do
      expect(File.exist?(File.join(temp_dir, 'bandcamp_dl_rb.bash'))).to be true
    end

    it 'creates the zsh completion file' do
      expect(File.exist?(File.join(temp_dir, '_bandcamp_dl_rb'))).to be true
    end

    it 'creates the fish completion file' do
      expect(File.exist?(File.join(temp_dir, 'bandcamp_dl_rb.fish'))).to be true
    end
  end

  describe '#bash' do
    it 'includes every CLI long option' do
      switches = BandcampDlRb::CLI.option_parser.top.list.grep(OptionParser::Switch)
      longs = switches.flat_map(&:long)
      longs.each { |long| expect(generator.bash).to include(long) }
    end
  end

  describe '#zsh' do
    it 'includes every CLI long option' do
      switches = BandcampDlRb::CLI.option_parser.top.list.grep(OptionParser::Switch)
      switches.flat_map(&:long).each { |long| expect(generator.zsh).to include(long) }
    end
  end

  describe '#fish' do
    it 'includes every CLI long option' do
      switches = BandcampDlRb::CLI.option_parser.top.list.grep(OptionParser::Switch)
      switches.flat_map(&:long).each do |long|
        expect(generator.fish).to include(long.sub(/\A--/, ''))
      end
    end
  end

  describe '.generate' do
    it 'writes files through the class method' do
      described_class.generate(output_dir: temp_dir)
      expect(File.exist?(File.join(temp_dir, 'bandcamp_dl_rb.bash'))).to be true
    end
  end

  describe '.generate with dir' do
    it 'writes files through the dir alias' do
      described_class.generate(dir: temp_dir)
      expect(File.exist?(File.join(temp_dir, 'bandcamp_dl_rb.fish'))).to be true
    end
  end

  describe 'aliases' do
    it 'exposes CompletionGenerator' do
      expect(BandcampDlRb::CompletionGenerator).to eq(described_class)
    end

    it 'exposes Completions::Generator' do
      expect(BandcampDlRb::Completions::Generator).to eq(described_class)
    end

    it 'exposes Completion::Generator' do
      expect(BandcampDlRb::Completion::Generator).to eq(described_class)
    end

    it 'exposes CLI::CompletionsGenerator' do
      expect(BandcampDlRb::CLI::CompletionsGenerator).to eq(described_class)
    end
  end
end
