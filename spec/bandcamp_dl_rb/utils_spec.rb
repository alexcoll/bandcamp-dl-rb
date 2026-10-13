# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe BandcampDlRb::Utils do
  describe '.sanitize_path' do
    subject(:sanitized) { described_class.sanitize_path(name) }

    context 'with a forward slash' do
      let(:name) { 'AC/DC' }

      it { is_expected.to eq('AC-DC') }
    end

    context 'with a backslash' do
      let(:name) { 'Foo\\Bar' }

      it { is_expected.to eq('Foo-Bar') }
    end

    context 'with reserved filename characters' do
      let(:name) { 'A:B*C?D"E<F>G|H' }

      it { is_expected.to eq('A-B-C-D-E-F-G-H') }
    end

    context 'with surrounding whitespace' do
      let(:name) { '  Artist Name  ' }

      it { is_expected.to eq('Artist Name') }
    end

    context 'with an ordinary name' do
      let(:name) { 'Radiohead' }

      it { is_expected.to eq('Radiohead') }
    end

    context 'with a single dot' do
      let(:name) { '.' }

      it { is_expected.to eq('-') }
    end

    context 'with a dotdot segment' do
      let(:name) { '..' }

      it { is_expected.to eq('-') }
    end

    context 'with dots inside words' do
      let(:name) { 'Dots and Loops' }

      it { is_expected.to eq('Dots and Loops') }
    end

    context 'with internal dots' do
      let(:name) { 'a..b' }

      it { is_expected.to eq('a..b') }
    end

    context 'with a trailing dot' do
      let(:name) { 'title.' }

      it { is_expected.to eq('title') }
    end

    context 'with an empty name' do
      let(:name) { '' }

      it { is_expected.to eq('-') }
    end

    context 'with a whitespace-only name' do
      let(:name) { '   ' }

      it { is_expected.to eq('-') }
    end
  end

  describe '.human_size' do
    subject(:formatted) { described_class.human_size(bytes) }

    context 'with zero bytes' do
      let(:bytes) { 0 }

      it { is_expected.to eq('0 B') }
    end

    context 'with nil' do
      let(:bytes) { nil }

      it { is_expected.to eq('0 B') }
    end

    context 'with a byte count' do
      let(:bytes) { 512 }

      it { is_expected.to eq('512.0 B') }
    end

    context 'with a kilobyte count' do
      let(:bytes) { 800_000 }

      it { is_expected.to eq('781.2 KB') }
    end

    context 'with a megabyte count' do
      let(:bytes) { 1_200_000 }

      it { is_expected.to eq('1.1 MB') }
    end

    context 'with a gigabyte count' do
      let(:bytes) { 1_073_741_824 }

      it { is_expected.to eq('1.0 GB') }
    end
  end
end
