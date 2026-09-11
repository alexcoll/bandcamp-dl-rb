# bandcamp-dl-rb

[![CI](https://github.com/alexcoll/bandcamp-dl-rb/actions/workflows/ci.yml/badge.svg)](https://github.com/alexcoll/bandcamp-dl-rb/actions/workflows/ci.yml)

Download all your [Bandcamp](https://bandcamp.com/) purchases (FLAC or the
highest available quality) and organize them into a clean `Artist/Album`
library.

- **Firefox, Safari, or Chrome** cookie auth (Safari: macOS only)
- FLAC by default, with automatic fallback through a quality ladder
- Outputs to a clean `Artist/Album/track` layout
- Sync your whole collection, or download specific albums via **URL** or by **item ID**
- Fast re-runs via a small local state file
- Cross-platform: macOS, Windows, Linux

> **Testing status:** only **macOS with Firefox and Safari** has been
> exercised so far. The Chrome extractor and the Windows/Linux profile paths
> are implemented but untested — please open an issue if something doesn't
> work on your setup.

---

## What it does

1. Reads your Bandcamp **`identity` session cookie** from your local Firefox,
   Safari, or Chrome profile (the same cookie your logged-in browser uses).
2. Scans your Bandcamp **collection** for all purchased items.
3. Downloads each as FLAC (or the best format available).
4. Organizes everything into a clean layout:
   ```
   <library>/
     <Artist Name>/
       <Album Name>/
         track.flac
   ```
5. Writes a `.bandcamp-sync.json` state file so subsequent runs skip
   already-downloaded albums.
6. Saves **cover art** (`cover.jpg`, fetched from Bandcamp's CDN) and a small
   **`album.json`** sidecar (release date, label, credits, tracklist) next to
   each album's audio.

You can instead download a single album or track by passing its Bandcamp URL
with `--url`, or pick specific items from your collection by ID with
`--items` (see [Individual items](#individual-items)).

---

## Requirements

- **Ruby** 3.4 or newer
- **Bundler** (optional, but recommended)

### Install with Homebrew

```bash
brew tap alexcoll/tap
brew install bandcamp-dl-rb

# The `bandcamp_dl_rb` command is then on your PATH
bandcamp_dl_rb --help

# A manpage is installed too
man bandcamp_dl_rb
```

Updating later:

```bash
brew update
brew upgrade bandcamp-dl-rb
```

### Install as a gem

```bash
gem build bandcamp-dl-rb.gemspec
gem install bandcamp-dl-rb-*.gem

# The `bandcamp_dl_rb` command is then on your PATH
bandcamp_dl_rb --help
```

### Run from a checkout

```bash
git clone https://github.com/alexcoll/bandcamp-dl-rb
cd bandcamp-dl-rb
bundle install

# Run it directly from the repo
bundle exec ruby exe/bandcamp_dl_rb --help
```

| Gem        | Used for                                       |
|------------|------------------------------------------------|
| `rubyzip`  | Extracting album zip archives                  |
| `sqlite3`  | Reading the Firefox / Chrome cookie databases  |
| `rspec`    | Only needed to run the tests                   |

> **Homebrew install:** the `alexcoll/tap` formula installs the gem (and its
> dependencies) into an isolated keg under Homebrew's Ruby, building the
> `sqlite3` native extension during `brew install`. A separate Ruby/Bundler
> setup isn't needed.

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
# With a Firefox, Safari, or Chrome profile already logged into bandcamp.com
bandcamp_dl_rb --library ~/Music/Bandcamp yourname
```

That's it — the script finds your `identity` cookie in Firefox (then Safari,
then Chrome), downloads your collection as FLAC, and files it under
`~/Music/Bandcamp/<Artist>/<Album>/`.

---

## Authentication

Bandcamp's **official API is only for labels/merch partners** — there is no
public download endpoint. This tool uses the same **undocumented
`/api/fancollection/*` endpoints** the website does, authenticated with your
session `identity` cookie.

### Automatic (Firefox, Safari, or Chrome)

By default the script tries Firefox first, then Safari, then Chrome, and
detects the relevant profile directory on every OS.

**Firefox** profile directories:

| OS      | Profile directory                                   |
|---------|-----------------------------------------------------|
| macOS   | `~/Library/Application Support/Firefox/Profiles/`   |
| Windows | `%APPDATA%\Mozilla\Firefox\Profiles\`               |
| Linux   | `~/.mozilla/firefox/`                               |

**Chrome / Chromium** cookie database locations:

| OS      | Chrome cookie database                                                    | Chromium cookie database                                                    |
|---------|--------------------------------------------------------------------------|-----------------------------------------------------------------------------|
| macOS   | `~/Library/Application Support/Google/Chrome/Default/Network/Cookies`     | `~/Library/Application Support/Chromium/Default/Network/Cookies`            |
| Windows | `%LOCALAPPDATA%\Google\Chrome\User Data\Default\Network\Cookies`         | `%LOCALAPPDATA%\Chromium\User Data\Default\Network\Cookies`                 |
| Linux   | `~/.config/google-chrome/Default/Network/Cookies`                        | `~/.config/chromium/Default/Network/Cookies`                                |

> **Chrome notes:** Chrome encrypts its cookies with a key in your OS keychain
> (Keychain on macOS, DPAPI on Windows, a keyring on Linux). The script reads
> that key automatically when possible. If it cannot (e.g. an unsupported
> login keychain), use `--cookie-file` as a fallback.
>
> **Safari (macOS only):** Safari stores cookies in a macOS-specific binary
> file. The script reads it in plaintext (no decryption needed) from the
> sandboxed container at
> `~/Library/Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies`
> (on older macOS, `~/Library/Cookies/...`). Because this path is protected by
> macOS privacy controls, the terminal must be granted **Full Disk Access**
> (System Settings → Privacy & Security → Full Disk Access, toggle your
> terminal app on, then restart it) or the cookie read is denied with
> "Operation not permitted".
>
> Firefox keeps `cookies.sqlite` locked (with a WAL file) while it runs, so
> the script copies the database to a temp file before reading it. This works
> across all Firefox profiles — if you have several, each is checked until one
> yields the `identity` cookie.

Use `--browser firefox`, `--browser safari`, `--browser chrome`, or
`--browser chromium` to force one specifically.

### Manual (fallback)

If automatic extraction fails, provide the cookie manually with
`--cookie-file`:

**Option A — cookie file.** Use a browser extension such as *"Get cookies.txt
LOCALLY"* to export a Netscape-format `cookies.txt`:

```bash
bandcamp_dl_rb --library ~/Music/Bandcamp \
  --cookie-file /path/to/cookies.txt yourname
```

**Option B — raw cookie value.** Open your browser's DevTools (F12) →
Application → Cookies → `bandcamp.com`, copy the value of the `identity`
cookie, and pass it directly:

```bash
bandcamp_dl_rb --library ~/Music/Bandcamp \
  --cookie-file "RAW-IDENTITY-VALUE" yourname
```

> **Security note:** The `identity` cookie is a full-session credential. Treat
> it like a password — don't commit it, don't share it, and don't leave it in
> shell history.

---

## Full usage

```
bandcamp_dl_rb [options] <bandcamp-username>

Downloads your Bandcamp purchases and organizes them into a music library.
```

### Options

| Flag                         | Description                                                      |
|------------------------------|------------------------------------------------------------------|
| `-l, --library PATH`         | **(required)** library root path                            |
| `-f, --format FORMAT`        | Download format (default: `flac`)                                |
| `-b, --browser NAME`         | `firefox`, `safari`, `chrome`, `chromium`, or `auto` (default: `auto`, tries Firefox then Safari then Chrome [Safari is macOS-only]) |
| `-c, --cookie-file PATH`     | Path to `cookies.txt`, or a raw `identity` cookie value          |
| `-H, --include-hidden`       | Also download items hidden in your collection                    |
| `--since DATE`               | Only items purchased on/after `YYYY-MM-DD`                       |
| `--until DATE`               | Only items purchased before `YYYY-MM-DD`                         |
| `--url URL`                  | Download a specific album/track by Bandcamp URL (repeatable)     |
| `--items IDS`                | Download specific collection items by ID, e.g. `a100,t200` (requires username) |
| `--filter REGEX`             | Download only items whose artist or title matches a regex (requires username)  |
| `-j, --jobs N`               | Download up to `N` albums in parallel (1-16, default: `1`)       |
| `--force`                    | Re-download even if the album already exists                     |
| `--no-unzip`                 | Save album downloads as ZIPs without extracting track files      |
| `--dry-run`                  | List what would be downloaded without downloading                |
| `-V, --version`              | Show the version and exit                                        |
| `-v, --verbose`              | Verbose output                                                   |
| `-h, --help`                 | Show help                                                        |

### Supported formats

`flac`, `mp3-320`, `mp3-v0`, `wav`, `aiff-lossless`, `aac-hi`, `alac`,
`vorbis`.

---

## Individual items

Instead of syncing your entire collection, you can download a single album or
track by URL, or specific items from your collection by ID.

### By URL with `--url`

Pass the album/track page URL (repeatable). The script finds that item in
your collection so it can use your download access:

```bash
# A single album
bandcamp_dl_rb -l ~/Music/Bandcamp \
  --url https://radiohead.bandcamp.com/album/in-rainbows yourname

# Multiple albums / tracks
bandcamp_dl_rb -l ~/Music/Bandcamp \
  --url https://radiohead.bandcamp.com/album/in-rainbows \
  --url https://aphextwin.bandcamp.com/track/windowlicker yourname
```

If the item isn't in your collection (e.g. it was a gift or is owned by a
different account), the tool reports it as not found and moves on.

### By item ID with `--items`

Item IDs appear in dry-run output as `[a100] Artist - Album`. Pass a
comma-separated list to download just those:

```bash
# See the IDs first
bandcamp_dl_rb -l ~/Music/Bandcamp --dry-run yourname
# --- Dry Run ---
#   [a100] Radiohead - Kid A (1.1 MB)
#   [a200] Radiohead - Amnesiac (781.2 KB)

# Download just those two items
bandcamp_dl_rb -l ~/Music/Bandcamp --items a100,a200 yourname
```

Downloading by item ID requires your Bandcamp username as the positional
argument. Item IDs are the `sale_item_type` + `sale_item_id` pair Bandcamp
uses internally (`a` = album, `t` = track).

### By regex with `--filter`

Download only the collection items whose artist or title matches a regex
(case-insensitive):

```bash
# Every Radiohead album in your collection
bandcamp_dl_rb -l ~/Music/Bandcamp --filter '^radiohead' yourname

# Anything with 'acid' in the artist or title
bandcamp_dl_rb -l ~/Music/Bandcamp --filter acid yourname
```

The regex is matched against `"artist title"` for each item, so you can match
on both fields at once (e.g. `--filter 'radiohead.*amnesiac'`). An invalid
regex or a filter that matches nothing exits non-zero and downloads nothing.

### Downloading in parallel

Large collections download one album at a time by default. Pass `-j N` to
download up to `N` albums concurrently (`1`-`16`):

```bash
bandcamp_dl_rb -l ~/Music/Bandcamp -j 16 yourname
```

Downloads stream straight to disk, so parallelism isn't limited by RAM —
bandwidth and Bandcamp's own throttling are the practical limits. Start with
a modest `N` and raise it until you see download errors; stalled workers are
retried with exponential backoff, which rate-limits automatically.

### Cover art & album info

Each downloaded album gets a `cover.jpg` (from Bandcamp's CDN, via the
album's `art_id`) and an `album.json` sidecar with whatever metadata the
download page exposes — artist, title, release date, label, credits, and the
tracklist. If the CDN fetch fails, cover art is extracted from the album zip
as a fallback. Existing albums are skipped by default; `--force` re-downloads
and refreshes the sidecar.

---

## Examples

```bash
# Essentials: all purchases as FLAC
bandcamp_dl_rb --library ~/Music/Bandcamp yourname

# Windows: library on another drive
bandcamp_dl_rb -l "D:/Music/Bandcamp" yourname

# Only purchases since a date, as WAV
bandcamp_dl_rb -l ~/Music/Bandcamp --since 2025-01-01 -f wav yourname

# See what would be downloaded (does not hit the network for files)
bandcamp_dl_rb -l ~/Music/Bandcamp --dry-run yourname

# Include hidden items and force a full re-download
bandcamp_dl_rb -l ~/Music/Bandcamp --include-hidden --force yourname

# Custom cookie file (when Firefox auto-detection fails)
bandcamp_dl_rb -l ~/Music/Bandcamp -c "identity-cookie-value" yourname
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

## Shell completion

Tab completion for the CLI flags ships with the gem in `completions/`
(bash, zsh, and fish). Source the file for your shell in your dotfiles, or use a
framework that picks up completions from `gem contents bandcamp_dl_rb`:

```bash
# bash
source "$(gem contents bandcamp_dl_rb | grep bandcamp_dl_rb.bash)"

# zsh
autoload -U compinit && compinit
source "$(gem contents bandcamp_dl_rb | grep _bandcamp_dl_rb)"

# fish
source (gem contents bandcamp_dl_rb | grep bandcamp_dl_rb.fish)
```

Homebrew installs put the completions alongside the formula; for example,
copy them into zsh's `fpath` if you don't use a completion framework.

## Manpage

A manpage (`man bandcamp_dl_rb`) ships with the gem in `man/`. Homebrew
installs it into `share/man/man1/`, so it works out of the box. For a
plain `gem install`, view it with:

```bash
man "$(gem contents bandcamp_dl_rb | grep bandcamp_dl_rb.1)"
```

---

## Project layout

```
exe/bandcamp_dl_rb                  Executable entrypoint (CLI.run)
lib/bandcamp_dl_rb.rb               Loads the library and defines the module/constants
lib/bandcamp_dl_rb/version.rb       Version constant
lib/bandcamp_dl_rb/cli.rb           Argument parsing + run loop
lib/bandcamp_dl_rb/cookie_extractor.rb  Cookie extraction facade
lib/bandcamp_dl_rb/cookie_extractor/   Per-browser extractors + cookies.txt parser
lib/bandcamp_dl_rb/client.rb        HTTP client for the Bandcamp collection API
lib/bandcamp_dl_rb/downloader.rb    Download + unzip + Artist/Album layout logic
lib/bandcamp_dl_rb/utils.rb         Path sanitization helpers
man/bandcamp_dl_rb.1                Manpage (roff source)
spec/                                 RSpec tests (one spec per class)
Gemfile / bandcamp-dl-rb.gemspec    Dependencies / packaging
Rakefile                              Test task (rake spec)
LICENSE                               GPL-3.0
```

---

## Why not use the other tools?

The well-known Bandcamp downloaders are Python ([bandcamp-downloader],
[bandcampsync]) or Kotlin ([bandcamp-collection-downloader]). This is a
self-contained Ruby implementation tailored to output directly into an
`Artist/Album/track` library layout.

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
