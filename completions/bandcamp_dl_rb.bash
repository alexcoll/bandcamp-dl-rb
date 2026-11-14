_bandcamp_dl_rb() {
  local cur prev words cword
  cur="${COMP_WORDS[COMP_CWORD]}"

  local opts="--library --format --browser --cookie-file --include-hidden --since --until --force --no-unzip --entry-encoding --temp-dir --state-file --no-state-file --dry-run --url --jobs --page-size --items --filter --no-progress --progress-interval --verbose --help --version"
  local format_values="flac mp3-320 mp3-v0 wav aiff-lossless aac-hi alac vorbis"
  local browser_values="firefox safari auto"

  case "$prev" in
    --format|-f) COMPREPLY=( $(compgen -W "$format_values" -- "$cur") ); return ;;
    --browser|-b) COMPREPLY=( $(compgen -W "$browser_values" -- "$cur") ); return ;;
    --library|-l|--format|-f|--browser|-b|--cookie-file|-c|--since|--until|--entry-encoding|--temp-dir|--state-file|--url|--jobs|-j|--page-size|--items|--filter|--progress-interval) return ;;
  esac

  COMPREPLY=( $(compgen -W "$opts" -- "$cur") )
}

complete -o default -F _bandcamp_dl_rb bandcamp_dl_rb
