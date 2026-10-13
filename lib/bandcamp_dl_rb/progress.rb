# frozen_string_literal: true

module BandcampDlRb
  # Renders one progress bar per in-flight download.
  #
  # Downloads run concurrently under --jobs, so each active transfer gets its
  # own line and the whole block is repainted as bytes arrive. A finished
  # download's line is dropped again rather than left behind, so the block
  # stays exactly as tall as the number of active transfers no matter how
  # large the collection is.
  #
  # Output is suppressed entirely when the stream is not a terminal: a piped or
  # redirected run gets plain log lines with no cursor movement, so logs and CI
  # output stay clean.
  class Progress
    # Seconds between repaints. Net::HTTP yields chunks as small as 16KB, far
    # more often than a terminal can usefully redraw.
    REFRESH_INTERVAL = 0.1
    # Trailing window the throughput estimate is averaged over.
    RATE_WINDOW = 3.0
    MIN_WIDTH = 20
    DEFAULT_WIDTH = 80
    MIN_BAR_WIDTH = 8
    MAX_BAR_WIDTH = 30
    LABEL_RESERVE = 12
    ELLIPSIS = '...'
    SPINNER_PERIOD = 0.9
    SPINNER_WIDTH = 3

    class << self
      def current
        @current ||= new
      end

      attr_writer :current
    end

    def initialize(out: nil)
      @out = out
      @enabled = true
      @lock = Mutex.new
      @entries = []
      @painted = 0
    end

    # Resolved lazily rather than memoized so a caller that swaps $stderr, as
    # the specs do, is still honored.
    def out
      @out || $stderr
    end

    def enabled=(value)
      @enabled = value
      clear
    end

    def enabled?
      @enabled && tty?
    end

    # Registers a download and returns a handle to advance it. +total+ is nil
    # when the size is unknown, which renders as an indeterminate bar.
    def start(label, total: nil)
      return Null.new unless enabled?

      entry = Entry.new(label: label, total: total)
      @lock.synchronize do
        @entries << entry
        paint
      end
      Handle.new(self, entry)
    end

    # Advances a download by +bytes+ and repaints, throttled so a fast
    # transfer cannot flood the terminal.
    def advance(entry, bytes)
      return unless enabled?
      return if bytes.nil? || bytes <= 0

      @lock.synchronize do
        entry.add(bytes)
        paint if entry.ready?(REFRESH_INTERVAL)
      end
    end

    # Rewinds a download to zero bytes, for a retry of the same transfer.
    def reset(entry)
      return unless enabled?

      @lock.synchronize do
        entry.reset
        paint
      end
    end

    # Drops a download's line, whether the transfer succeeded or not.
    def finish(entry)
      return unless enabled?

      @lock.synchronize do
        @entries.delete(entry)
        paint
      end
    end

    # Writes a log line without corrupting the bar block: the block is erased,
    # the message printed, and the block repainted underneath it.
    def log(msg)
      return out.puts(msg) unless enabled?

      @lock.synchronize do
        erase
        out.puts(msg)
        paint
      end
    end

    # Erases the block for good, so no cursor movement escapes past the
    # summary at the end of a run.
    def close
      return unless enabled?

      clear
    end

    # Forgets every in-flight download and wipes the block.
    def clear
      @lock.synchronize do
        erase
        @entries.clear
      end
    end

    private

    def tty?
      out.respond_to?(:tty?) && out.tty?
    end

    def erase
      return if @painted.zero?

      out.print("\e[#{@painted}A\e[J")
      @painted = 0
    end

    # Repaints the block from scratch: rewind over the rows drawn last time,
    # clear everything below them, then redraw. Clearing to the end of the
    # screen rather than clearing row by row is what lets a finished
    # download's line actually disappear.
    def paint
      # Sample before rendering, so the throughput on screen covers the bytes
      # this repaint is about to draw rather than lagging a frame behind them.
      @entries.each(&:painted!)
      lines = @entries.map { |entry| line_for(entry) }
      erase if @painted.positive?
      lines.each { |line| out.print("\r\e[2K#{line}\n") }
      @painted = lines.length
      out.flush
    end

    def line_for(entry)
      tail = tail_for(entry)
      # " [] " is the two brackets plus their padding; whatever is left is
      # split between the label and the bar, label first so a truncated album
      # name still reads as "Artist - Alb...".
      spare = terminal_width - tail.length - 4
      line = if spare < LABEL_RESERVE
               tail
             else
               bar_width = clamp(spare / 2, MIN_BAR_WIDTH, MAX_BAR_WIDTH)
               "#{truncate(entry.label, spare - bar_width)} [#{bar_for(entry, bar_width)}] #{tail}"
             end
      # A narrow enough terminal leaves the tail itself overflowing, and a line
      # wider than the terminal wraps and corrupts the block below it.
      truncate(line, terminal_width)
    end

    # Everything after the bar: percentage and byte counts when the size is
    # known, throughput whenever it can be measured, and an ETA only when both
    # halves of that are available.
    def tail_for(entry)
      parts = [entry.total ? transfer_summary(entry) : Utils.human_size(entry.current)]
      add_rate(entry, parts)
      parts.join(' ')
    end

    def transfer_summary(entry)
      format('%<percent>5.1f%% %<current>s/%<total>s',
             percent: entry.percent,
             current: Utils.human_size(entry.current),
             total: Utils.human_size(entry.total))
    end

    def add_rate(entry, parts)
      rate = entry.rate
      return unless rate.positive?

      parts << "#{Utils.human_size(rate)}/s"
      parts << "ETA #{format_eta(entry.eta(rate))}" if entry.total
    end

    def bar_for(entry, width)
      return indeterminate_bar(entry, width) unless entry.total

      ('=' * (width * entry.ratio).round).ljust(width, ' ')
    end

    # A block sliding back and forth, so a download of unknown size still
    # shows that bytes are moving without implying a percentage.
    def indeterminate_bar(entry, width)
      cycle = (entry.elapsed / SPINNER_PERIOD) % 2.0
      travel = cycle <= 1.0 ? cycle : 2.0 - cycle
      head = [(travel * (width + SPINNER_WIDTH)).round, width - SPINNER_WIDTH].min
      buffer = [' '] * width
      SPINNER_WIDTH.times { |i| buffer[head + i] = '=' if head + i < width }
      buffer.join
    end

    def truncate(label, budget)
      return label if label.length <= budget

      "#{label[0, budget - ELLIPSIS.length]}#{ELLIPSIS}"
    end

    def format_eta(seconds)
      return '--:--' unless seconds&.finite? && seconds >= 0

      seconds = seconds.round
      format('%<minutes>d:%<seconds>02d', minutes: seconds / 60, seconds: seconds % 60)
    end

    def terminal_width
      width = out.winsize.last if out.respond_to?(:winsize)
      return DEFAULT_WIDTH unless width&.positive?

      [width, MIN_WIDTH].max
    rescue StandardError
      DEFAULT_WIDTH
    end

    def clamp(value, low, high)
      value.clamp(low, high)
    end

    # A handle to advance a registered download. Null is handed out instead
    # when progress is disabled, so callers never branch on it.
    class Null
      def advance(_bytes); end

      def reset; end

      def finish; end
    end

    class Handle
      def initialize(progress, entry)
        @progress = progress
        @entry = entry
      end

      def advance(bytes)
        @progress.advance(@entry, bytes)
      end

      # Zeroes the byte count for a retry of the same transfer, so the bar
      # restarts rather than accumulating across attempts.
      def reset
        @progress.reset(@entry)
      end

      def finish
        @progress.finish(@entry)
      end
    end
  end
end
