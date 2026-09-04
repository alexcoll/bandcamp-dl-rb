# bandcamp-dl-rb

[![CI](https://github.com/alexcoll/bandcamp-dl-rb/actions/workflows/ci.yml/badge.svg)](https://github.com/alexcoll/bandcamp-dl-rb/actions/workflows/ci.yml)

Download all your [Bandcamp](https://bandcamp.com/) purchases (FLAC or the
highest available quality) and organize them into a clean `Artist/Album`
library.

- **Firefox, Safari, or Chrome** cookie auth (Safari: macOS only)
- FLAC by default, with automatic fallback through a quality ladder
- Outputs to a clean `Artist/Album/track` layout
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

---

## Requirements

- **Ruby** 3.1 or newer
- **Bundler** (optional, but recommended)

### Install with Homebrew

```bash
brew tap alexcoll/tap
brew install bandcamp-dl-rb

# The `bandcamp_dl_rb` command is then on your PATH
bandcamp_dl_rb --help
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

Downloads all your Bandcamp purchases and organizes them into a music library.
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
