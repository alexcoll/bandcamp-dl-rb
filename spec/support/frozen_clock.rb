# frozen_string_literal: true

# A stand-in for the monotonic clock, so specs can decide exactly when time
# passes. Repaint throttling and throughput measurement both read
# Process.clock_gettime, and leaving that to the real clock makes examples
# depend on how fast the machine runs them.
class FrozenClock
  def initialize(now = Process.clock_gettime(Process::CLOCK_MONOTONIC))
    @now = now
  end

  attr_reader :now

  def advance(seconds)
    @now += seconds
    self
  end
end

# Takes over the monotonic clock for the example. Include the context, then
# call freeze_clock in a before hook and move time on with tick.
RSpec.shared_context 'with a frozen clock' do
  let(:clock) { FrozenClock.new }

  def freeze_clock
    @frozen_clock = clock
    allow(Process).to receive(:clock_gettime).and_call_original
    allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC) { @frozen_clock.now }
  end

  def tick(seconds = 1)
    @frozen_clock.advance(seconds)
  end
end
