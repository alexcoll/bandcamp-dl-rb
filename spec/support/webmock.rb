# frozen_string_literal: true

require 'webmock/rspec'

# Every spec that touches the network goes through stub_request. A spec that
# reaches a real host fails loudly instead of hanging on a timeout or, worse,
# quietly asserting against whatever live Bandcamp happens to be serving.
WebMock.disable_net_connect!
