# frozen_string_literal: true

require_relative '../spec_helper'

# Stands in for a terminal. `tty?` decides whether anything renders at all, so
# it is configurable; `winsize` drives line-width fitting.
class FakeTerminal
  attr_reader :output

  def initialize(tty: true, width: 80)
    @tty = tty
    @width = width
    @output = +''
    @mutex = Mutex.new
  end

  def tty?
    @tty
  end

  def print(data)
    @mutex.synchronize { @output << data }
  end

  # rubocop:disable RSpec/Output -- a stand-in for a terminal, not spec output
  def puts(msg)
    print("#{msg}\n")
  end
  # rubocop:enable RSpec/Output

  def flush; end

  def winsize
    [24, @width]
  end

  # Every line in the order it was painted, cursor sequences stripped.
  def lines
    @output.scan(/\r\e\[2K([^\n]*)/).flatten
  end

  # The most recently painted line.
  def line
    lines.last
  end

  # How many rows each repaint rewound over. A renderer that leaked a row per
  # finished download would show counts growing with the number of downloads.
  def rewinds
    @output.scan(/\e\[(\d+)A/).flatten.map(&:to_i)
  end
end

RSpec.describe BandcampDlRb::Progress do
  subject(:progress) { described_class.new(out: terminal) }

  let(:terminal) { FakeTerminal.new }

  # Repaints are throttled and throughput is measured against the monotonic
  # clock, so both are driven by hand here. That keeps the examples
  # deterministic instead of dependent on how fast the machine runs them.
  include_context 'with a frozen clock'

  # Advances far enough to repaint and records where the indeterminate block
  # ended up, so a run of steps can be compared.
  def step_spinner
    tick(described_class::SPINNER_PERIOD / 2)
    handle.advance(bytes)
    block_positions << terminal.line[/\[(.*)\]/, 1]
  end

  describe '#enabled?' do
    subject(:enabled) { progress.enabled? }

    context 'with a terminal' do
      it { is_expected.to be true }
    end

    context 'without a terminal' do
      let(:terminal) { FakeTerminal.new(tty: false) }

      it { is_expected.to be false }
    end

    context 'when disabled' do
      before { progress.enabled = false }

      it { is_expected.to be false }
    end
  end

  describe '#start' do
    subject(:handle) { progress.start('Artist - Album', total: 1000) }

    context 'with a terminal' do
      it 'paints the label straight away' do
        handle
        expect(terminal.line).to include('Artist - Album')
      end
    end

    context 'without a terminal' do
      let(:terminal) { FakeTerminal.new(tty: false) }

      it { is_expected.to be_a(described_class::Null) }

      it 'writes nothing at all' do
        handle
        expect(terminal.output).to be_empty
      end
    end

    context 'when disabled' do
      before { progress.enabled = false }

      it { is_expected.to be_a(described_class::Null) }

      it 'writes nothing at all' do
        handle
        expect(terminal.output).to be_empty
      end
    end

    context 'with several downloads active' do
      subject(:line) { terminal.lines.last(4) }

      before do
        freeze_clock
        4.times { |i| progress.start("Album #{i}", total: 1000) }
      end

      it 'renders one row per active download' do
        expect(line.map { |l| l[/\w+ \d/] }).to eq(['Album 0', 'Album 1', 'Album 2', 'Album 3'])
      end
    end
  end

  describe '#advance' do
    subject(:line) { terminal.line }

    let(:total) { 2048 }
    let(:bytes) { 512 }
    let(:handle) { progress.start('Album', total: total) }

    # Register the download with the clock frozen, step past the repaint
    # throttle, then transfer `bytes`. Contexts that need a different history
    # override this.
    before do
      freeze_clock
      handle
      tick
      handle.advance(bytes)
    end

    context 'with a known total' do
      it { is_expected.to include('25.0%') }

      it { is_expected.to include('512.0 B/2.0 KB') }
    end

    context 'with an unknown total' do
      let(:total) { nil }
      let(:bytes) { 4096 }

      it { is_expected.to include('4.0 KB') }

      it { is_expected.not_to include('%') }
    end

    context 'with a total of zero' do
      let(:total) { 0 }
      let(:bytes) { 4096 }

      # Zero is not a size, so it must not be divided by.
      it { is_expected.not_to include('%') }
    end

    context 'with more bytes than the reported total' do
      let(:total) { 1000 }
      let(:bytes) { 1500 }

      # Bandcamp rounds size_mb to one decimal, so a transfer can legitimately
      # finish a little past it.
      it { is_expected.to include('100.0%') }

      it { is_expected.to match(/\[=+\s*\]/) }
    end

    context 'with an unknown total and elapsed time' do
      let(:total) { nil }
      let(:bytes) { 1 }
      # Read through the terminal rather than the memoized subject, which would
      # return the same string every time within one example.
      let(:block_positions) { [] }

      it 'slides the block along the bar' do
        4.times { step_spinner }

        expect(block_positions.uniq.length).to be > 1
      end
    end

    context 'with no bytes transferred yet' do
      let(:bytes) { 0 }

      # Nothing has been transferred, so there is no rate to measure yet.
      it { is_expected.not_to include('/s') }
    end

    context 'with the first chunk received' do
      it { is_expected.to include('512.0 B/s') }
    end

    context 'with two throughput samples' do
      let(:bytes) { 0 }

      before { handle.advance(1024) }

      it { is_expected.to include('1.0 KB/s') }

      it { is_expected.to include('ETA') }
    end

    context 'with an unknown total and throughput' do
      let(:total) { nil }
      let(:bytes) { 0 }

      before { handle.advance(1024) }

      # No total means no ETA to estimate, so only the rate is shown.
      it { is_expected.not_to include('ETA') }
    end

    context 'with repeated updates' do
      it 'coalesces them into a single repaint' do
        painted = terminal.lines.length
        10.times { |i| handle.advance(i + 1) }
        expect(terminal.lines.length).to eq(painted)
      end
    end

    context 'with a zero-sized update' do
      let(:bytes) { 0 }

      it { is_expected.to include('0.0%') }
    end

    context 'with a negative update' do
      let(:bytes) { 0 }

      before { handle.advance(-5) }

      it 'does not run the bar backwards' do
        expect(line).to include('0.0%')
      end
    end

    context 'with many small chunks' do
      let(:total) { 10_000 }
      let(:bytes) { 0 }

      before do
        10.times do
          tick
          handle.advance(700)
        end
      end

      it { is_expected.to include('70.0%') }
    end

    context 'with a narrow terminal' do
      let(:terminal) { FakeTerminal.new(width: 60) }
      let(:handle) { progress.start('A Band Name - An Album Title That Goes On', total: 4096) }

      it 'never draws wider than the terminal' do
        expect(line.length).to be <= 60
      end

      it 'truncates the label with an ellipsis' do
        expect(line).to include('...')
      end
    end

    context 'with a wide terminal' do
      let(:terminal) { FakeTerminal.new(width: 120) }
      let(:bar_width) { line[/\[(.*)\]/, 1].length }

      context 'with a name too long to fit' do
        let(:handle) { progress.start(long_name, total: 4096) }
        let(:long_name) do
          'Godspeed You! Black Emperor - F♯A♯∞ (Live at the 4th A McGill University 2001)'
        end

        before { handle.advance(2048) }

        # The name is what the user is reading, so it keeps the columns and the
        # bar stays as narrow as it is allowed to.
        it 'spends them on the name first' do
          expect(bar_width).to eq(described_class::MIN_BAR_WIDTH)
        end
      end

      context 'with a name that fits easily' do
        let(:handle) { progress.start('Kid A', total: 4096) }

        before { handle.advance(2048) }

        it 'widens the bar with the rest' do
          expect(bar_width).to eq(described_class::MAX_BAR_WIDTH)
        end
      end
    end

    context 'with a tiny terminal' do
      let(:terminal) { FakeTerminal.new(width: 20) }
      let(:handle) { progress.start('A Band Name - An Album Title That Goes On', total: 4096) }

      # The label and bar give way rather than wrapping onto the next row.
      it 'never draws wider than the terminal' do
        expect(line.length).to be <= 20
      end
    end
  end

  describe '#reset' do
    subject(:line) { terminal.line }

    let(:handle) { progress.start('Album', total: 1000) }

    before do
      freeze_clock
      handle
      tick
    end

    context 'with a partial transfer to rewind' do
      before do
        handle.advance(900)
        handle.reset
        tick
        handle.advance(100)
      end

      # A retry restarts the transfer, so the bar rewinds rather than
      # accumulating both attempts and overshooting the total.
      it { is_expected.to include('10.0%') }
    end

    context 'with throughput already measured' do
      before do
        handle.advance(500)
        handle.reset
        tick
        handle.advance(500)
      end

      # 500 bytes over the second since the reset. Had the reset left the
      # abandoned attempt's samples in place, this would report the 1000 bytes
      # spread over two seconds instead.
      it 'measures the rate from the retry alone' do
        expect(line).to include('500.0 B/s')
      end
    end
  end

  describe '#finish' do
    subject(:line) { terminal.line }

    before { freeze_clock }

    context 'with the only download running' do
      let(:handle) { progress.start('Album', total: 1000) }

      before do
        handle
        tick
        handle.advance(500)
      end

      # Removing the last line means repainting an empty block, so nothing new
      # is drawn at all.
      it 'draws nothing further' do
        painted = terminal.lines.length
        handle.finish
        expect(terminal.lines.length).to eq(painted)
      end

      it 'leaves the block cleared' do
        handle.finish
        expect(terminal.output).to end_with("\e[1A\e[J")
      end
    end

    context 'with another download still running' do
      let(:finished) { progress.start('Album A', total: 1000) }

      before do
        finished
        progress.start('Album B', total: 1000)
        tick
        finished.finish
      end

      it { is_expected.to include('Album B') }

      it 'drops the finished download' do
        expect(terminal.line).not_to include('Album A')
      end
    end

    context 'with several downloads running' do
      before do
        Array.new(3) { |i| progress.start("Album #{i}", total: 1000) }.each(&:finish)
        progress.close
      end

      # Filling the block (1 + 2 + 3) and emptying it again (2 + 1 + 0) never
      # needed a rewind wider than the number of downloads in flight.
      it 'never rewinds over more rows than are active' do
        expect(terminal.rewinds.max).to eq(3)
      end
    end

    context 'with many sequential downloads' do
      before do
        10.times do |i|
          handle = progress.start("Album #{i}", total: 1000)
          tick
          handle.advance(1000)
          handle.finish
        end
      end

      it 'keeps one row per active download, not per download' do
        expect(terminal.rewinds.max).to eq(1)
      end
    end

    context 'with threads working at once' do
      before do
        Array.new(8) do |i|
          Thread.new do
            handle = progress.start("Album #{i}", total: 1000)
            5.times { |n| handle.advance(n * 10) }
            handle.finish
          end
        end.each(&:join)
        progress.close
      end

      it 'survives without raising' do
        expect(terminal.output).to end_with("\e[J")
      end
    end
  end

  describe '#log' do
    let(:handle) { progress.start('Album', total: 1000) }

    context 'with bars on screen' do
      before do
        freeze_clock
        handle
        tick
        handle.advance(400)
        progress.log('  Saved to /library/Album')
      end

      # The message has to land on a cleared row, not in the middle of the
      # block, or the bars below it are left stranded.
      it 'clears the block before writing' do
        expect(terminal.output).to match(%r{\e\[1A\e\[J {2}Saved to /library/Album\n})
      end

      it 'repaints the block underneath' do
        expect(terminal.output.split('Saved to /library/Album').last).to include('Album')
      end
    end

    context 'without a terminal' do
      let(:terminal) { FakeTerminal.new(tty: false) }

      it 'writes plainly, with no cursor movement' do
        progress.log('a message')
        expect(terminal.output).to eq("a message\n")
      end
    end
  end

  describe '#close' do
    let(:handle) { progress.start('Album', total: 1000) }

    before do
      freeze_clock
      handle
      tick
      handle.advance(500)
    end

    # The bars share stderr with the log, so nothing may be left on screen for
    # the summary to overwrite.
    context 'with a bar on screen' do
      it 'erases the block' do
        progress.close
        expect(terminal.output).to end_with("\e[1A\e[J")
      end
    end
  end
end
