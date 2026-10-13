# frozen_string_literal: true

require_relative '../spec_helper'

# The shell completions are hand-maintained lists of options, so they drift
# whenever the CLI gains one. --no-unzip and --temp-dir were both missing for a
# long time because nothing diffed the completions against the parser; these
# examples are that guard.
RSpec.describe 'completions' do
  let(:bash_source) { File.read(File.expand_path('../../completions/bandcamp_dl_rb.bash', __dir__)) }
  let(:zsh_source) { File.read(File.expand_path('../../completions/_bandcamp_dl_rb', __dir__)) }
  let(:fish_source) { File.read(File.expand_path('../../completions/bandcamp_dl_rb.fish', __dir__)) }

  let(:cli_help) { BandcampDlRb::CLI.parse_args([])[:parser].to_s }

  # Extract the long options actually defined by the CLI's OptionParser, so
  # this check cannot drift from the real option set.
  let(:cli_long_options) do
    cli_help.scan(/^\s*(?:-[A-Za-z], )?--([a-z][a-z0-9-]*)/).flatten.uniq.map { |name| "--#{name}" }
  end

  # The bash file lists every option in one quoted, backslash-continued
  # `local opts="..."` assignment. Scanning the whole file would also pick up
  # the `case "$prev"` argument-taking list, so capture that one string first.
  let(:bash_options) do
    opts = bash_source[/local opts="(.*?)"/m, 1].to_s
    opts.scan(/--([a-z][a-z0-9-]*)/).flatten.uniq.map { |name| "--#{name}" }
  end

  # zsh writes long-only flags as '--name[description]' and short/long pairs as
  # '{-s,--name}[description]', so a plain '--' scan catches both. zsh's own
  # _-prefixed helpers (_files, _users, ...) never follow '--', and the
  # leading-underscore filter keeps them out even if that ever changes.
  let(:zsh_options) do
    names = zsh_source.scan(/--([a-z_][a-z0-9_-]*)/).flatten.uniq.reject { |name| name.start_with?('_') }
    names.map { |name| "--#{name}" }
  end

  # fish spells long options `-l name`, without the '--' prefix, so it is
  # re-added when comparing against the CLI's set.
  let(:fish_options) do
    fish_source.scan(/-l ([a-z][a-z0-9-]*)/).flatten.uniq.map { |name| "--#{name}" }
  end

  # Each completion file below points `completion_options` at its own parsed
  # set, so the same two assertions run against all three.
  shared_examples 'a completion in sync with the CLI' do
    it 'offers every CLI long option' do
      missing = cli_long_options - completion_options
      expect(missing).to be_empty, "completions are missing #{missing.join(', ')}"
    end

    it 'offers no options the CLI does not define' do
      extras = completion_options - cli_long_options
      expect(extras).to be_empty, "completions offer unknown options: #{extras.join(', ')}"
    end
  end

  describe 'completions/bandcamp_dl_rb.bash' do
    let(:completion_options) { bash_options }

    it_behaves_like 'a completion in sync with the CLI'
  end

  describe 'completions/_bandcamp_dl_rb' do
    let(:completion_options) { zsh_options }

    it_behaves_like 'a completion in sync with the CLI'
  end

  describe 'completions/bandcamp_dl_rb.fish' do
    let(:completion_options) { fish_options }

    it_behaves_like 'a completion in sync with the CLI'
  end
end
