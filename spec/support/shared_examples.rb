# frozen_string_literal: true

# Gives the example group a private temp directory in +dest+.
#
# The directory is created only if something asks for it and always removed
# afterwards, which replaces the `around { Dir.mktmpdir { @dest = dir } }`
# boilerplate that repeated in seven describes.
RSpec.shared_context 'with a temporary directory' do
  let(:dest) { @dest ||= Dir.mktmpdir('bandcamp-dl-rb-spec') }

  after { FileUtils.rm_rf(@dest) if @dest }
end

# Writes a Netscape-format cookie jar and exposes its path in +cookie_file+.
# Body comes from +cookie_lines+, built with BandcampFixtures#cookie_line.
RSpec.shared_context 'with a cookie file' do
  let(:cookie_lines) { [BandcampFixtures.cookie_line('identity', 'file-cookie-value')] }

  let(:cookie_file) do
    @cookie_file = Tempfile.new(['bandcamp-cookies', '.txt'])
    @cookie_file.write(cookie_lines.join("\n"))
    @cookie_file.close
    @cookie_file
  end

  after { @cookie_file&.unlink }
end
