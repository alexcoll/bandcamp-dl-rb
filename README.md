# bandcamp-to-plex

Download all your [Bandcamp](https://bandcamp.com/) purchases (FLAC or the
highest available quality) and organize them into a Plex-friendly library.

- **Firefox-only** cookie auth (macOS, Windows, Linux)
- FLAC by default, with automatic fallback through a quality ladder
- Outputs to a clean `Artist/Album/track` layout
- Fast re-runs via a small local state file
- Cross-platform: macOS, Windows, Linux

---

## What it does

1. Reads your Bandcamp **`identity` session cookie** from your local Firefox
   profile (the same cookie your logged-in browser uses).
2. Scans your Bandcamp **collection** for all purchased items.
3. Downloads each as FLAC (or the best format available).
4. Organizes everything into a Plex-friendly layout:
   ```
   <library>/
     <Artist Name>/
       <Album Name>/
         track.flac
   ```
5. Writes a `.bandcamp-sync.json` state file so subsequent runs skip
   already-downloaded albums.

---

## Requirements

- **Ruby** 3.1 or newer
- **Bundler** (optional, but recommended)

### Install dependencies

```bash
# If you have Bundler
bundle install

# ...or install the gems directly
gem install rubyzip sqlite3 rspec
```

| Gem        | Used for                                     |
|------------|----------------------------------------------|
| `rubyzip`  | Extracting album zip archives                |
| `sqlite3`  | Reading the Firefox cookie database          |
| `rspec`    | Only needed to run the tests                 |

---

## Getting your Bandcamp username

Visit `bandcamp.com`, go to your profile, and look at the URL — it ends in
your username:

```
https://bandcamp.com/yourname
```

You'll pass `yourname` as the final argument.

---

## Quick start

```bash
# With a Firefox profile already logged into bandcamp.com
ruby bandcamp_to_plex.rb --library ~/Music/Bandcamp yourname
```

That's it — the script finds your `identity` cookie in Firefox, downloads
your collection as FLAC, and files it under `~/Music/Bandcamp/<Artist>/<Album>/`.

---

## Authentication

Bandcamp's **official API is only for labels/merch partners** — there is no
public download endpoint. This tool uses the same **undocumented
`/api/fancollection/*` endpoints** the website does, authenticated with your
session `identity` cookie.

### Automatic (Firefox)

The script detects your Firefox profile directory on every OS:

| OS      | Profile directory                                   |
|---------|-----------------------------------------------------|
| macOS   | `~/Library/Application Support/Firefox/Profiles/`   |
| Windows | `%APPDATA%\Mozilla\Firefox\Profiles\`               |
| Linux   | `~/.mozilla/firefox/`                               |

Make sure you are **logged into bandcamp.com in Firefox**, then run the script.

> Note: If any running Firefox process is actively using its profile, the
> cookie database may be locked. Close Firefox (or quit it) if auto-detection
> fails for that reason, or use `--cookie-file`.

### Manual (fallback)

If automatic extraction fails, provide the cookie manually with
`--cookie-file`:

**Option A — cookie file.** Use a browser extension such as *"Get cookies.txt
LOCALLY"* to export a Netscape-format `cookies.txt`:

```bash
ruby bandcamp_to_plex.rb --library ~/Music/Bandcamp \
  --cookie-file /path/to/cookies.txt yourname
```

**Option B — raw cookie value.** Open your browser's DevTools (F12) →
Application → Cookies → `bandcamp.com`, copy the value of the `identity`
cookie, and pass it directly:

```bash
ruby bandcamp_to_plex.rb --library ~/Music/Bandcamp \
  --cookie-file "RAW-IDENTITY-VALUE" yourname
```

> **Security note:** The `identity` cookie is a full-session credential. Treat
> it like a password — don't commit it, don't share it, and don't leave it in
> shell history.

---

## Full usage

```
ruby bandcamp_to_plex.rb [options] <bandcamp-username>

Downloads all your Bandcamp purchases and organizes them for Plex.
```

### Options

| Flag                         | Description                                                      |
|------------------------------|------------------------------------------------------------------|
| `-l, --library PATH`         | **(required)** Plex library root path                            |
| `-f, --format FORMAT`        | Download format (default: `flac`)                                |
| `-b, --browser NAME`         | `firefox` or `auto` (default: `auto`)                            |
| `-c, --cookie-file PATH`     | Path to `cookies.txt`, or a raw `identity` cookie value          |
| `-H, --include-hidden`       | Also download items hidden in your collection                    |
| `--since DATE`               | Only items purchased on/after `YYYY-MM-DD`                       |
| `--until DATE`               | Only items purchased before `YYYY-MM-DD`                         |
| `--force`                    | Re-download even if the album already exists                     |
| `--dry-run`                  | List what would be downloaded without downloading                |
| `-v, --verbose`              | Verbose output                                                   |
| `-h, --help`                 | Show help                                                        |

### Supported formats

`flac`, `mp3-320`, `mp3-v0`, `wav`, `aiff-lossless`, `aac-hi`, `alac`,
`vorbis`.

---

## Examples

```bash
# Essentials: all purchases as FLAC
ruby bandcamp_to_plex.rb --library ~/Music/Bandcamp yourname

# Windows: library on another drive
ruby bandcamp_to_plex.rb -l "D:/Music/Bandcamp" yourname

# Only purchases since a date, as WAV
ruby bandcamp_to_plex.rb -l ~/Music/Bandcamp --since 2025-01-01 -f wav yourname

# See what would be downloaded (does not hit the network for files)
ruby bandcamp_to_plex.rb -l ~/Music/Bandcamp --dry-run yourname

# Include hidden items and force a full re-download
ruby bandcamp_to_plex.rb -l ~/Music/Bandcamp --include-hidden --force yourname

# Custom cookie file (when Firefox auto-detection fails)
ruby bandcamp_to_plex.rb -l ~/Music/Bandcamp -c "identity-cookie-value" yourname
```

---

## Format fallback

When the exact format you requested isn't available, the script falls back
through this quality order:

```
flac → wav → aiff-lossless → alac → aac-hi → mp3-320 → mp3-v0 → vorbis
```

If nothing is available, the album is reported as *Unavailable* and skipped.

---

## Re-runs & state

The script writes `.bandcamp-sync.json` into your library directory after each
run. On subsequent runs it uses this to skip albums that are already present.
New purchases are detected and downloaded on the next run.

- A file that looks like `Radiohead/Kid A/01 Everything In Its Right Place.flac`
  exists in the library → skipped (unless `--force`).
- Use `--force` to ignore this and re-download everything.

---

## Running the tests

```bash
bundle exec rspec
# or
rspec
```

---

## Project layout

```
bandcamp_to_plex.rb         Main script (module + CLI)
spec/                       RSpec tests
Gemfile                     Gem dependencies
LICENSE                     GPL-3.0
```

---

## Why not use the other tools?

The well-known Bandcamp downloaders are Python ([bandcamp-downloader],
[bandcampsync]) or Kotlin ([bandcamp-collection-downloader]). This is a
self-contained Ruby implementation tailored to output directly into a Plex
library layout.

## Inspiration & attribution

This tool is an **original, from-scratch Ruby implementation**. We researched
the undocumented Bandcamp API flow (the `identity` cookie, the
`/api/fancollection/*` endpoints, and the `redownload_url` → `data-blob` →
download flow) by studying how the following community projects approach the
same problem:

- [bandcamp-downloader](https://github.com/easlice/bandcamp-downloader) (MIT)
- [bandcampsync](https://github.com/meeb/bandcampsync) (GPL)
- [bandcamp-collection-downloader](https://github.com/Ezwen/bandcamp-collection-downloader)

No code was copied from these projects; they were used only as research
references.

---

## License

Distributed under the **GNU General Public License v3.0**. See [LICENSE](LICENSE)
for the full text.

---

## Disclaimer

Uses undocumented, unsupported Bandcamp endpoints. Bandcamp may change or
restrict these at any time (and actively discourages tooling that hits its
session endpoints). This tool is for downloading **music you have already paid
for** into a personal, locally-backed library.
