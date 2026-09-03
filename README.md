# bandcamp-to-plex

Download all your [Bandcamp](https://bandcamp.com/) purchases (FLAC or highest
quality available) and organize them for a Plex library.

## What it does

1. Authenticates to Bandcamp using your **`identity` session cookie** (the
   same one your browser uses when logged in).
2. Scans your Bandcamp **collection** for all purchased items.
3. Downloads each as FLAC (or the best format available), falling back through
   a quality ladder.
4. Organizes downloads into a Plex-friendly layout:
   ```
   <library>/
     <Artist Name>/
       <Album Name>/
         track.flac
   ```
5. Writes a `.bandcamp-sync.json` state file so re-runs are fast and skip
   already-downloaded albums.

## How auth works

Bandcamp's **official API is only for labels/merch partners** — there is no
public download endpoint. This tool uses the same **undocumented
`/api/fancollection/*` endpoints** the website uses, authenticated with your
session `identity` cookie.

The script tries to read the cookie automatically:

1. **Firefox** — reads `cookies.sqlite` from your profile (plaintext).
2. **Chrome / Chromium / Brave / Edge** — reads the encrypted cookie DB,
   decrypting with the macOS Keychain key.

If automatic extraction fails, provide the cookie manually:

- **Option A — cookie file.** Use a browser extension such as *"Get cookies.txt
  LOCALLY"* to export a Netscape-format `cookies.txt`, then:
  ```
  bandcamp_to_plex.rb --library /path/to/plex -c /path/to/cookies.txt myusername
  ```
- **Option B — raw value.** Open DevTools (F12) → Application → Cookies →
  `bandcamp.com`, copy the value of the `identity` cookie, and pass it directly:
  ```
  bandcamp_to_plex.rb --library /path/to/plex -c "RAW-IDENTITY-VALUE" myusername
  ```

> **Security note:** The `identity` cookie is a full-session credential. Treat
> it like a password — don't commit it or share it.

## Install

```bash
bundle install
# or
gem install rubyzip sqlite3 rspec
```

Dependencies: `rubyzip` (extracting album archives), `sqlite3` (reading browser
cookie DBs), `rspec` (tests).

## Usage

```bash
bandcamp_to_plex.rb --library /path/to/plex myusername
```

### Options

| Flag | Description |
|------|-------------|
| `-l, --library PATH` | **(required)** Plex library root path |
| `-f, --format FORMAT` | Audio format. One of `flac mp3-320 mp3-v0 wav aiff-lossless aac-hi alac vorbis` (default `flac`) |
| `-b, --browser NAME` | `firefox`, `chrome`, `chromium`, `brave`, `edge`, or `auto` (default `auto`) |
| `-c, --cookie-file PATH` | Path to `cookies.txt`, or a raw `identity` cookie value |
| `-H, --include-hidden` | Also download items marked hidden in your collection |
| `--since DATE` | Only items purchased on/after date (`YYYY-MM-DD`) |
| `--until DATE` | Only items purchased before date (`YYYY-MM-DD`) |
| `--force` | Re-download even if the album already exists |
| `--dry-run` | List what would be downloaded without downloading |
| `-v, --verbose` | Verbose output |
| `-h, --help` | Show help |

### Examples

```bash
# Just the essentials
bandcamp_to_plex.rb --library /Volumes/Music myname

# Only new purchases since last year, in WAV
bandcamp_to_plex.rb -l /Volumes/Music --since 2025-01-01 -f wav myname

# List what would download (no network writes)
bandcamp_to_plex.rb -l /Volumes/Music --dry-run myname

# Hidden items too, forced re-download
bandcamp_to_plex.rb -l /Volumes/Music --include-hidden --force myname
```

## Format fallback

When the exact format isn't available, the script falls back through this
quality order:

```
flac → wav → aiff-lossless → alac → aac-hi → mp3-320 → mp3-v0 → vorbis
```

If nothing is available, the album is reported as *Unavailable* and skipped.

## Running the tests

```bash
bundle exec rspec
```

## Why not use the other tools?

The well-known Bandcamp downloaders are Python ([bandcamp-downloader],
[bandcampsync]) or Kotlin ([bandcamp-collection-downloader]). This is a
self-contained Ruby implementation tailored to output directly into a Plex
library layout.

[bandcamp-downloader]: https://github.com/easlice/bandcamp-downloader
[bandcampsync]: https://github.com/meeb/bandcampsync
[bandcamp-collection-downloader]: https://github.com/Ezwen/bandcamp-collection-downloader

## Disclaimer

Uses undocumented, unsupported Bandcamp endpoints. Bandcamp may change or
restrict these at any time (and actively discourages tooling that hits its
session endpoints). This is for downloading **music you have already paid for**
and backed a local library.
