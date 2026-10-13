# frozen_string_literal: true

module BandcampDlRb
  class Progress
    # A single in-flight download. Owns its byte count and throughput estimate;
    # the shared renderer reads these under its own lock, so nothing here is
    # synchronized on its own.
    class Entry
      def initialize(label:, total:)
        @label = label
        # A reported size of 0 is not a real target, and dividing by it would
        # make the bar nonsense; treat it as unknown.
        @total = total&.positive? ? total : nil
        @current = 0
        @started_at = monotonic
        @painted_at = nil
        @samples = []
      end

      attr_reader :label, :total, :current

      # Clamped: the size Bandcamp reports is rounded to one decimal, so a
      # transfer can legitimately run slightly past it. Showing 103% would
      # look like a bug.
      def ratio
        return 0.0 unless @total

        [@current.to_f / @total, 1.0].min
      end

      def percent
        ratio * 100
      end

      def elapsed
        monotonic - @started_at
      end

      def add(bytes)
        @current += bytes
      end

      # Rewinds to zero for a retry, discarding the throughput history, which
      # described a transfer that no longer exists.
      def reset
        @current = 0
        @samples = []
        @started_at = monotonic
        @painted_at = nil
      end

      # Marks the entry as freshly painted, resampling throughput. Called once
      # per repaint rather than per chunk: chunk sizes vary with network
      # conditions, and a windowed average over a few seconds is what keeps
      # the displayed rate from flickering.
      def painted!
        @painted_at = monotonic
        now = @painted_at
        @samples << [now, @current]
        @samples.shift while @samples.size > 2 && @samples.first[0] < now - Progress::RATE_WINDOW
      end

      # True once +interval+ has passed since this entry was last painted, so
      # the renderer can coalesce a burst of chunk writes into one repaint.
      def ready?(interval)
        return true if @painted_at.nil?

        monotonic - @painted_at >= interval
      end

      def rate
        first = @samples.first
        last = @samples.last
        return 0.0 unless first && last && last[0] > first[0]

        (last[1] - first[1]) / (last[0] - first[0])
      end

      def eta(rate)
        return nil unless @total && rate.positive?

        (@total - @current) / rate
      end

      private

      def monotonic
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end
