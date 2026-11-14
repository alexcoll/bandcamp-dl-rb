complete -c bandcamp_dl_rb -s l -l library -d 'Plex library root path (required)' -r -F
complete -c bandcamp_dl_rb -s f -l format -d 'Audio format (default: flac)' -x -a 'flac mp3-320 mp3-v0 wav aiff-lossless aac-hi alac vorbis'
complete -c bandcamp_dl_rb -s b -l browser -d 'Browser to extract cookies from (default: auto)' -x -a 'firefox safari auto'
complete -c bandcamp_dl_rb -s c -l cookie-file -d 'Path to cookies.txt file, or raw identity cookie value' -r -F
complete -c bandcamp_dl_rb -s H -l include-hidden -d 'Also download hidden items'
complete -c bandcamp_dl_rb -l since -d 'Only download items purchased on or after this date (YYYY-MM-DD)' -r
complete -c bandcamp_dl_rb -l until -d 'Only download items purchased before this date (YYYY-MM-DD)' -r
complete -c bandcamp_dl_rb -l force -d 'Re-download even if album already exists'
complete -c bandcamp_dl_rb -l no-unzip -d 'Save album downloads as ZIPs without extracting track files'
complete -c bandcamp_dl_rb -l entry-encoding -d 'Source encoding for non-UTF-8 zip entry names (default: auto-detect)' -r
complete -c bandcamp_dl_rb -l temp-dir -d 'Directory for temporary download files (default: a cache dir on disk). Override to place working files on a specific filesystem' -r -F
complete -c bandcamp_dl_rb -l state-file -d 'Path for the sync state file (default: <library>/.bandcamp-sync.json)' -r -F
complete -c bandcamp_dl_rb -l no-state-file -d 'Do not write a sync state file'
complete -c bandcamp_dl_rb -l dry-run -d 'Show what would be downloaded without downloading'
complete -c bandcamp_dl_rb -l url -d 'Download a specific album/track by Bandcamp URL (repeatable)' -r
complete -c bandcamp_dl_rb -s j -l jobs -d 'Download up to N albums in parallel (1-16, default: 1)' -r
complete -c bandcamp_dl_rb -l page-size -d 'Collection page size to request (1-500, default: 100)' -r
complete -c bandcamp_dl_rb -l items -d 'Download specific items by ID, e.g. a100,t200 (requires username)' -r
complete -c bandcamp_dl_rb -l filter -d 'Download only items whose artist or title matches REGEX (requires username)' -r
complete -c bandcamp_dl_rb -l no-progress -d 'Do not draw progress bars for downloads'
complete -c bandcamp_dl_rb -l progress-interval -d 'Repaint progress bars at most once every SECONDS seconds (default: 1.0)' -r
complete -c bandcamp_dl_rb -s v -l verbose -d 'Verbose output'
complete -c bandcamp_dl_rb -s h -l help -d 'Show this help'
complete -c bandcamp_dl_rb -s V -l version -d 'Show version'
