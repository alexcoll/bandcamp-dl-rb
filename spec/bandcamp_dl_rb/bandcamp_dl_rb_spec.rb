# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe BandcampDlRb do
  after { described_class.verbose = nil }

  describe '.run' do
    it 'delegates to CLI.run' do
      expect(BandcampDlRb::CLI).to receive(:run).with(['--version'], out: $stdout, err: $stderr)
      described_class.run(['--version'], out: $stdout, err: $stderr)
    end
  end

  describe '.log' do
    it 'writes to stderr' do
      expect { described_class.log('test message') }.to output("test message\n").to_stderr
    end
  end

  describe '.log_verbose' do
    before { described_class.verbose = verbose }

    let(:verbose) { true }

    context 'when verbose' do
      it 'writes to stderr' do
        expect { described_class.log_verbose('test') }.to output("test\n").to_stderr
      end
    end

    context 'when not verbose' do
      let(:verbose) { false }

      it 'writes nothing' do
        expect { described_class.log_verbose('test') }.not_to output.to_stderr
      end
    end
  end

  describe '.bc_host?' do
    subject(:allowed) { described_class.bc_host?(host) }

    context 'with the apex domain' do
      let(:host) { 'bandcamp.com' }

      it { is_expected.to be true }
    end

    context 'with a subdomain' do
      let(:host) { 'radiohead.bandcamp.com' }

      it { is_expected.to be true }
    end

    context 'with a lookalike domain' do
      let(:host) { 'notbandcamp.com' }

      it { is_expected.to be false }
    end

    context 'with an unrelated host' do
      let(:host) { 'example.com' }

      it { is_expected.to be false }
    end
  end

  describe '.download_host?' do
    subject(:allowed) { described_class.download_host?(host) }

    context 'with the apex domain' do
      let(:host) { 'bandcamp.com' }

      it { is_expected.to be true }
    end

    context 'with a bandcamp.com subdomain' do
      let(:host) { 'radiohead.bandcamp.com' }

      it { is_expected.to be true }
    end

    context 'with the bcbits apex domain' do
      let(:host) { 'bcbits.com' }

      it { is_expected.to be true }
    end

    context 'with a bcbits subdomain' do
      let(:host) { 'd1.bcbits.com' }

      it { is_expected.to be true }
    end

    context 'with a lookalike domain' do
      let(:host) { 'notbcbits.com' }

      it { is_expected.to be false }
    end

    context 'with an unrelated host' do
      let(:host) { 'example.com' }

      it { is_expected.to be false }
    end
  end
end
