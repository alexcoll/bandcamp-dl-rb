# frozen_string_literal: true

require_relative 'lib/bandcamp_to_plex/version'

Gem::Specification.new do |spec|
  spec.name = 'bandcamp-to-plex'
  spec.version = BandcampToPlex::VERSION
  spec.authors = ['Alex Collier']
  spec.email = ['alex.coll@babylist.com']

  spec.summary = 'Download your Bandcamp purchases and organize them for a Plex library'
  spec.description = 'Authenticates to Bandcamp with your browser identity cookie ' \
                     '(Firefox, Safari, or Chrome), scans your collection, and downloads each ' \
                     'purchase into a Plex-friendly <Artist>/<Album>/track layout.'
  spec.homepage = 'https://github.com/alexcoll/bandcamp-to-plex'
  spec.license = 'GPL-3.0-only'

  spec.required_ruby_version = '>= 3.1'

  spec.files = Dir['lib/**/*.rb'] + Dir['exe/*'] + %w[README.md LICENSE]
  spec.bindir = 'exe'
  spec.executables = ['bandcamp_to_plex']
  spec.require_paths = ['lib']

  spec.add_dependency 'rubyzip', '>= 2.3'
  spec.add_dependency 'sqlite3', '>= 1.6'
  spec.metadata['rubygems_mfa_required'] = 'true'
end
