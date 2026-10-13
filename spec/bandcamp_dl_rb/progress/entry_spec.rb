# frozen_string_literal: true

require_relative '../../spec_helper'

RSpec.describe BandcampDlRb::Progress::Entry do
  subject(:entry) { described_class.new(label: 'Album', total: total) }

  let(:total) { 1000 }

  describe '#ratio' do
    context 'with a quarter transferred' do
      subject(:ratio) { entry.ratio }

      before { entry.add(250) }

      it { is_expected.to eq(0.25) }
    end

    context 'with an unknown total' do
      subject(:ratio) { described_class.new(label: 'Album', total: nil).ratio }

      it { is_expected.to eq(0.0) }
    end

    context 'with more bytes than the total' do
      subject(:ratio) { entry.ratio }

      before { entry.add(5000) }

      it { is_expected.to eq(1.0) }
    end
  end

  describe '#rate' do
    subject(:rate) { entry.rate }

    context 'with one sample taken' do
      before { entry.painted! }

      it { is_expected.to eq(0.0) }
    end

    context 'with a long download' do
      # Samples are taken once per repaint, so a multi-hour download would
      # accumulate tens of thousands of them if the window were not pruned.
      before do
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        allow(Process).to receive(:clock_gettime).and_call_original
        allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC) { now }

        10_000.times do
          entry.add(1024)
          now += BandcampDlRb::Progress::REFRESH_INTERVAL
          entry.painted!
        end
      end

      it 'keeps the sample window bounded' do
        window = BandcampDlRb::Progress::RATE_WINDOW / BandcampDlRb::Progress::REFRESH_INTERVAL
        expect(entry.instance_variable_get(:@samples).length).to be <= window.ceil + 2
      end
    end
  end

  describe '#eta' do
    subject(:eta) { entry.eta(rate) }

    context 'with an unknown total' do
      subject(:eta) { described_class.new(label: 'Album', total: nil).eta(100.0) }

      it { is_expected.to be_nil }
    end

    context 'with an unknown rate' do
      let(:rate) { 0.0 }

      it { is_expected.to be_nil }
    end

    context 'with bytes left and a known rate' do
      before { entry.add(200) }

      let(:rate) { 100.0 }

      it { is_expected.to eq(8.0) }
    end
  end

  describe '#reset' do
    context 'with most of the total transferred' do
      before do
        entry.add(900)
        entry.painted!
        entry.reset
      end

      it 'rewinds the byte count' do
        expect(entry.current).to eq(0)
      end

      it 'discards the rate history' do
        expect(entry.rate).to eq(0.0)
      end
    end
  end
end
