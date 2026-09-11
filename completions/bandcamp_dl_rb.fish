complete -c bandcamp_dl_rb -s l -l library -d 'Plex library root path' -r -F
complete -c bandcamp_dl_rb -s f -l format -d 'Audio format' -x \
  -a 'flac wav aiff-lossless mp3-320 mp3-v0 aac-hi alac vorbis'
complete -c bandcamp_dl_rb -s b -l browser -d 'Browser to extract cookies from' -x \
  -a 'firefox chrome chromium safari auto'
complete -c bandcamp_dl_rb -s c -l cookie-file -d 'Path to cookies.txt file or identity cookie value' -r -F
complete -c bandcamp_dl_rb -s H -l include-hidden -d 'Also download hidden items'
complete -c bandcamp_dl_rb -l since -d 'Only download items purchased on/after DATE' -r
complete -c bandcamp_dl_rb -l until -d 'Only download items purchased before DATE' -r
complete -c bandcamp_dl_rb -l force -d 'Re-download even if album already exists'
complete -c bandcamp_dl_rb -l dry-run -d 'Show what would be downloaded without downloading'
complete -c bandcamp_dl_rb -l url -d 'Download a specific album/track by URL' -r
complete -c bandcamp_dl_rb -s j -l jobs -d 'Download up to N albums in parallel (1-16)' -x -a '1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16'
complete -c bandcamp_dl_rb -l items -d 'Download specific collection items by ID' -r
complete -c bandcamp_dl_rb -l filter -d 'Download only items matching a regex' -r
complete -c bandcamp_dl_rb -s v -l verbose -d 'Verbose output'
complete -c bandcamp_dl_rb -s h -l help -d 'Show help'
complete -c bandcamp_dl_rb -s V -l version -d 'Show version'