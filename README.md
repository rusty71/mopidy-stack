# Mopidy + Qobuz + Icecast stack

A local music server that streams Qobuz (hi-res) to an Icecast server as two
parallel streams: a small MP3 stream and a lossless high-resolution stream.

Everything runs as your own user (no root, no system packages installed) and
every Python component is an **editable git checkout**, so you can change code
and just restart the service.

There is also a **YunoHost package** of this stack, see
[Installation on YunoHost](#installation-on-yunohost) below.

## The repositories

| Repository | What it is |
|---|---|
| [rusty71/mopidy](https://github.com/rusty71/mopidy) | Mopidy 3.4.2, with a patch that pushes the tag events into the audio sink (so the stream can announce the track title) |
| [rusty71/mopidy-iris](https://github.com/rusty71/mopidy-iris) | Iris, the web interface, with a fix for the `pkg_resources` removal |
| [rusty71/mopidy-qobuz](https://github.com/rusty71/mopidy-qobuz) | The Qobuz extension: browser login, timeouts, retries and the album cache |
| [rusty71/mopidy_ynh](https://github.com/rusty71/mopidy_ynh) | The YunoHost package: Mopidy + Iris + Qobuz + the publisher |
| [rusty71/icecast2_ynh](https://github.com/rusty71/icecast2_ynh) | The YunoHost package: Icecast with the two mounts and their fallbacks |
| [rusty71/mopidy-stack](https://github.com/rusty71/mopidy-stack) | This repository: the local (non YunoHost) setup and the documentation |

Every patched repository has a branch `ynh-stack` with the changes, and a tag
`ynh-1.0` pointing at them.

## Installation on YunoHost

Two packages, installed from the GitHub repositories:

```bash
# The streaming server: the two mounts and their silent fallbacks
yunohost app install icecast2 \
    --domain="music.example.org" \
    --path="/icecast" \
    --admin="admin" \
    --password="<the Icecast password>"

# Mopidy, Iris, Qobuz and the publisher
yunohost app install mopidy \
    --domain="music.example.org" \
    --path="/mopidy" \
    --qobuz_auth_token="<the token of the Qobuz web player>" \
    --icecast_password="<the Icecast password>"
```

The two apps share one password: the publisher authenticates with it on the
mounts of the Icecast app.

The Qobuz auth token is the token that the Qobuz web player holds.  Get it on
your own machine (the sign-in flow needs a browser):

```bash
git clone https://github.com/rusty71/mopidy_ynh.git
cd mopidy_ynh/sources/extra_files
./qobuz-login.py --print
```

Then the web interface is on `https://music.example.org/mopidy/iris/` and the
streams on `https://music.example.org/icecast/low.mp3` and
`https://music.example.org/icecast/high.ogg`.

The [administration guide of the Mopidy package](https://github.com/rusty71/mopidy_ynh/blob/main/doc/ADMIN.md)
has the details.

## The local setup

```
/home/opencode/mopidy-stack/
├── config/
│   ├── mopidy.conf.template  # the real mopidy.conf holds the credentials
│   ├── icecast.xml           # Icecast config (2 mounts + fallback streams)
│   └── mime.types            # Icecast mime types (ogg -> application/ogg)
├── src/                      # editable git checkouts - change code here
│   ├── mopidy-3.4/           # Mopidy 3.4.2 core (patched)
│   ├── mopidy-iris/          # Mopidy-Iris 3.70.0 (the web UI)
│   ├── mopidy-local/         # Mopidy-Local 3.3.0 (local music index)
│   ├── mopidy-qobuz/         # the Qobuz extension
│   └── mopidy/               # Mopidy 4.0.5 - unused leftover, see below
├── venv3/                    # Python env for Mopidy + Iris + Local + Qobuz
├── icecast/                  # Icecast 2.4.4 built from source into this prefix
├── data/                     # Mopidy data/cache, local index
├── log/                      # Icecast access/error logs
├── web/                      # silence.mp3 / silence.ogg fallback streams
├── bin/                      # helper scripts
└── run/                      # pidfiles, publisher state
```

### Services (systemd --user, so no root needed)

| Service  | Unit                                            | Address                |
|----------|-------------------------------------------------|------------------------|
| Mopidy   | `~/.config/systemd/user/mopidy.service`          | http://127.0.0.1:6680/ |
| Icecast  | `~/.config/systemd/user/icecast.service`         | http://127.0.0.1:8000/ |
| Publisher| `~/.config/systemd/user/icecast-publisher.service`| -                      |

```bash
systemctl --user status mopidy icecast icecast-publisher
systemctl --user restart mopidy
journalctl --user -u mopidy -f
```

Linger is enabled, so all three start at boot without logging in.

### Streams

| Mount       | Format              | Content                                    |
|-------------|---------------------|--------------------------------------------|
| `/low.mp3`  | MP3, 128 kbps CBR   | 48 kHz stereo, low bandwidth               |
| `/high.ogg` | Ogg FLAC, lossless  | 24-bit/96 kHz stereo, hi-res from Qobuz     |

Both are produced by **`bin/icecast-publisher.py`**, not by Mopidy directly:

```
Mopidy --PCM over TCP--> icecast-publisher --Icecast-->
```

**Why not let Mopidy publish directly?** Mopidy changes track by taking its
GStreamer playbin through `READY`, which tears down the audio output -
including the Shoutcast client.  The Icecast source then disconnects and
reconnects on *every* track change, Icecast moves the listeners to the
fallback file (a different bitstream), and the fallback is served at full
speed rather than in real time.  Players that care about timing fall apart:
VLC reported `Timestamp conversion failed` and `lost synchronisation` on
every skip.

The publisher decouples the two: Mopidy only hands over raw PCM, the
encoding happens in the publisher, so the sample counter, the timestamps and
the container keep running across track changes, and the Icecast session
stays open.  Gaps (while Mopidy fetches the next track) are filled with
silence, so the stream is continuous in wall clock time as well.

The publisher also publishes the track title to Icecast.  It gets the title
from Mopidy's JSON-RPC API, because Qobuz serves tagless FLAC and the Mopidy
core's tag events do not reach the audio sink (see the patch in
`src/mopidy-3.4/mopidy/audio/actor.py`).  Icecast only supports titles on
formats with a tag handler, so the title shows on the MP3 mount but not on the
Ogg one.

**Keep the formats pinned.** The publisher resamples to a fixed rate per
output, so the format never changes mid-stream.  If you change the rates,
regenerate the fallbacks to match:

```bash
bin/make-fallbacks.sh            # 48 kHz MP3 / 96 kHz FLAC
```

> GStreamer's `shout2send` cannot send raw FLAC (its sink only accepts
> `audio/mpeg`, `application/ogg`, ...), which is why the lossless stream is
> Ogg FLAC rather than bare FLAC.
>
> A side effect of the Ogg container: the Ogg muxer swallows tag events, so
> the Shoutcast metadata (the track title shown by Icecast) only reaches the
> MP3 mount.
>
> Icecast also has to agree on the content type: the publisher announces
> `application/ogg` while the fallback file would be served as `audio/ogg`
> (from the system mime types), and Icecast refuses to switch a mount
> between streams of different types.  `config/mime.types` fixes that.
>
> VLC prints `an error in the stream caused the decoder to lose
> synchronization` once, when it connects to the Ogg mount.  That is a quirk
> of VLC's Ogg-FLAC handling, not a broken stream: it shows the same warning
> for an Ogg FLAC file made by ffmpeg, while the same audio in a plain FLAC
> file is clean, and `ffmpeg` decodes the stream without a single error.
> The MP3 mount is completely clean, and track changes produce no warnings
> on either mount.

### Usage

```bash
# Open the web UI (Iris)
xdg-open http://127.0.0.1:6680/iris/

# Check both mounts are live
bin/check-streams.sh

# Verify the Qobuz login
bin/check-qobuz.sh

# Watch what the publisher is doing
journalctl --user -u icecast-publisher -f
```

### Web interfaces

| URL                             | Interface                             |
|---------------------------------|---------------------------------------|
| http://127.0.0.1:6680/iris/    | **Iris** - the web UI (browse, search, play) |
| http://127.0.0.1:6680/mopidy/  | Mopidy's default web client (a client index) |
| http://127.0.0.1:6680/local/   | Mopidy-Local's web page (album art gallery) |

### Why Mopidy 3 and not Mopidy 4

The stack ran on Mopidy 4 for a while, but Mopidy 4 has **no built-in player
UI**: `/mopidy/` is only a page that lists the web clients that extensions
provide, and the old ExtJS client was removed back in Mopidy 3.0.  The
community UI (Iris) is Mopidy 3 only - it uses `mopidy.models.serialize`,
which Mopidy 4 replaced with pydantic models - so on Mopidy 4 there was
nothing to open in the browser.

Mopidy 3.4.2 with Iris 3.70.0 is therefore what this stack runs.  The
Mopidy 4 checkout in `src/mopidy` and `venv4/` are leftovers of that
experiment and are not used by any service.

### The album cache (Qobuz -> local FLAC)

The Qobuz extension caches whole albums as local, tagged FLAC files.  When an
album is queued (in Iris: click the album), the extension downloads every
track of it in the background and stores it for Mopidy-Local:

```
~/Music/Nirvana/Nevermind/01 - Smells Like Teen Spirit.flac
~/Music/Nirvana/Nevermind/02 - In Bloom.flac
...
```

The files carry the Qobuz metadata (title, artist, album, album artist, track
number, release date, length) and the album cover, and Mopidy-Local rescans
automatically when an album is done, so the tracks show up in the library
right away.

```ini
[qobuz]
cache_enabled = true
cache_dir = ~/Music
```

* `cache_dir` has to be a directory that Mopidy-Local scans.
* The files are named `<track number> - <title>.flac`: Mopidy-Local sorts a
  directory by file name, so the number keeps the album in order.
* An album counts as queued when at least two of its tracks are in the track
  list, so playing a single track does not pull in the whole album.
* The quality is the `quality` setting: with `27` the cache holds the
  24/192 kHz masters (the Nirvana album is 1.1 GB), with `6` the 16/44.1 kHz
  files.  Qobuz decides per album what is available, so some albums land as
  16/44.1 kHz even at `27`.
* The cache never re-downloads a track that is already there, and it is
  skipped entirely if the album is already cached.

### Local files (Mopidy-Local)

Local music is served by **Mopidy-Local**, which keeps an indexed library in
SQLite and can browse by album, artist, genre and release year:

```ini
[local]
media_dir = ~/Music
scan_timeout = 3000
scan_follow_symlinks = false
max_search_results = 100
```

Build or update the index with:

```bash
cd /home/opencode/mopidy-stack
./venv3/bin/mopidy local scan          # scan for new and changed files
./venv3/bin/mopidy local clear         # empty the index first
```

The index is fast (a few hundred files in well under a second) and the files
show up under "Local media" in Iris.

The built-in `file` extension is **disabled** - it would show the same files
a second time, and it rescans the whole home directory on every start.

The files themselves are expected as `artist/album/track`, which is also the
layout the album cache writes.

### Qobuz setup

**Qobuz blocks programmatic e-mail/password logins since April 2026** (the API
answers `401 User authentication is required` before it even looks at your
credentials). The extension in this stack was patched to authenticate with a
browser auth token instead:

```bash
bin/qobuz-login.sh
```

This opens `https://www.qobuz.com/signin/oauth` in your browser, listens on a
local port for the redirect, exchanges the OAuth code for an auth token and
writes `auth_token` into the `[qobuz]` section of `config/mopidy.conf`.

If the browser flow is unavailable, log in at <https://play.qobuz.com>, open
devtools -> Application -> Local Storage -> `localuser` -> `token`, and use:

```bash
bin/qobuz-login.sh --token <token>
```

`username`/`password` are still supported as a fallback for the day Qobuz
brings app logins back, but they do not work today.

The extension also needs `app_id`/`secret` to sign stream URL requests:

```bash
bin/update-qobuz-keys.sh
```

Quality codes: `5` = 320 kbps MP3, `6` = 16/44.1 FLAC, `7` = 24-bit FLAC up
to 96 kHz, `27` = 24-bit FLAC up to 192 kHz.

#### app_id / secret

Qobuz's web player bundle contains several app IDs, and each one only works
with its own secret:

| app_id         | environment | secret                            |
|----------------|-------------|-----------------------------------|
| `798273057`    | production  | `abb21364945c0583309667d13ca3d93a` |
| `377257687`    | integration | `806331c3b0b641da923b890aed01d04a` |
| `724307056`    | recette     | `f69a7734686cb9427629378a4b7ac381` |

The auth token is bound to the app ID as well: a token issued for one app ID
is rejected by the other.

### Credentials

The Qobuz credentials (the account, the auth token and the app secret) live
in `config/mopidy.conf` on the machine that runs the stack, and in the
settings of the YunoHost app (`/etc/yunohost/apps/mopidy/settings.yml`, only
readable by root).  **They are not in any repository.**  The files in this
repository only hold templates.
