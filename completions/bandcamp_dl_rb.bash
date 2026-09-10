_bandcamp_dl_rb() {
  local cur prev words cword
  cur="${COMP_WORDS[COMP_CWORD]}"

  local opts="--library --format --browser --cookie-file --include-hidden \
--since --until --force --dry-run --url --jobs --items --filter \
--verbose --help --version"
  local formats="flac wav aiff-lossless mp3-320 mp3-v0 aac-hi alac vorbis"
  local browsers="firefox chrome chromium safari auto"

  case "$prev" in
    --format|-f) COMPREPLY=( $(compgen -W "$formats" -- "$cur") ); return ;;
    --browser|-b) COMPREPLY=( $(compgen -W "$browsers" -- "$cur") ); return ;;
    --library|-l|--cookie-file|-c|--url|--since|--until|--jobs|--items|--filter)
      return ;;
  esac

  COMPREPLY=( $(compgen -W "$opts" -- "$cur") )
}

complete -o default -F _bandcamp_dl_rb bandcamp_dl_rb