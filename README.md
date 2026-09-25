# Spotlightify

Spotlightify is a tiny macOS menu bar app for Spotify. Press a hotkey, search tracks in a polished popup, then play or queue them without switching to the Spotify window.

Features:

- `Cmd+Shift+Space` opens the search popup
- live track search with album art
- native translucent popup with Liquid Glass controls on macOS 26+ and native controls on macOS 14–15
- `Enter` plays the selected track
- `Cmd+Enter` queues the selected track
- `Ctrl+Option+P` play/pause
- `Ctrl+Option+N` next
- `Ctrl+Option+B` previous

Requirements:

- macOS 14 or later
- Spotify desktop app installed
- Spotify Premium
- your own Spotify Developer app `Client ID`

## Install

Download `Spotlightify.dmg` from [Releases](https://github.com/anudeep-gad12/spotlightify/releases/latest), open it, and drag `Spotlightify` into **Applications**. Then open Spotlightify from Applications.

Or with Homebrew:

```bash
brew install --cask anudeep-gad12/tap/spotlightify
```

## Updates

After Spotlightify is in **Applications**, use **Check for Updates…** in the menu bar.

## First-Time Spotify Setup

Each user needs their own Spotify developer app. Spotlightify does not ship with your credentials.

1. Go to `https://developer.spotify.com/dashboard`
2. Create an app
3. Add this exact redirect URI:

```text
http://127.0.0.1:43821/callback
```

4. Save the app settings
5. Copy the app’s `Client ID`
6. Open Spotlightify
7. Choose `Spotify Setup` from the menu bar icon, or open the popup
8. Paste the `Client ID` into the setup screen and save it locally
9. Click `Login / Reconnect`

Do not paste your `Client secret`. Spotlightify does not use it.

## Build From Source

Requirements:

- Xcode 26+
- `xcodegen`

Commands:

```bash
xcodegen generate
open Spotlightify.xcodeproj
```

For a local debug build:

```bash
./dev.sh fresh
```

Log tail:

```bash
./dev.sh traces
```

## Project Notes

- user tokens are stored in the macOS Keychain under service `app.spotlightify`
- logs are stored locally in `~/Library/Logs/Spotlightify/app.log`
- user client IDs are stored locally in app preferences
- the repo does not need a real `SPOTIFY_CLIENT_ID` to build

## License

MIT. See [LICENSE](LICENSE).
