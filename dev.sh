#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h}"
cd "$ROOT_DIR"
APP_LOG_DIR="$HOME/Library/Logs/Spotlightify"
APP_LOG_FILE="$APP_LOG_DIR/app.log"
PROD_APP="/Applications/Spotlightify.app"
TEST_APP="/Applications/Spotlightify Dev.app"

# Both builds share a bundle ID and hotkeys, so only one may run at a time.
stop_running_app() {
  osascript -e 'quit app id "app.spotlightify"' >/dev/null 2>&1 || true
  for _ in {1..20}; do
    pgrep -f "Spotlightify.*/Contents/MacOS/Spotlightify" >/dev/null || return 0
    sleep 0.25
  done
  echo "Spotlightify did not quit." >&2
  exit 1
}

case "${1:-open}" in
  open)
    xcodegen generate
    open Spotlightify.xcodeproj
    ;;
  fresh)
    rm -rf .build/DerivedData
    xcodegen generate
    xcodebuild -project Spotlightify.xcodeproj -scheme Spotlightify -destination 'platform=macOS' -derivedDataPath .build/DerivedData build
    open Spotlightify.xcodeproj
    ;;
  traces)
    mkdir -p "$APP_LOG_DIR"
    touch "$APP_LOG_FILE"
    tail -n 200 -f "$APP_LOG_FILE"
    ;;
  test)
    # Build the working tree and run it in place of the installed app. Signing with the
    # same Developer ID keeps the existing Spotify login readable without keychain prompts.
    team_id=$(security find-identity -v -p codesigning | sed -nE 's/.*"Developer ID Application: .*\(([A-Z0-9]{10})\)".*/\1/p' | head -1)
    if [[ -z "$team_id" ]]; then
      echo "No Developer ID Application signing identity found in the keychain." >&2
      exit 1
    fi
    xcodegen generate
    xcodebuild -project Spotlightify.xcodeproj -scheme Spotlightify -configuration Release \
      -destination 'platform=macOS' -derivedDataPath .build/DerivedData \
      DEVELOPMENT_TEAM="$team_id" build | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
    stop_running_app
    rm -rf "$TEST_APP"
    # Run from /Applications so the app doesn't turn off Launch at Login.
    cp -R .build/DerivedData/Build/Products/Release/Spotlightify.app "$TEST_APP"
    open "$TEST_APP"
    echo "Running test build: $TEST_APP (switch back with ./dev.sh prod)"
    ;;
  prod)
    stop_running_app
    open "$PROD_APP"
    echo "Running installed app: $PROD_APP"
    ;;
  which)
    pgrep -fl "Spotlightify.*/Contents/MacOS/Spotlightify" || echo "Spotlightify is not running"
    ;;
  *)
    echo "usage: ./dev.sh [open|fresh|traces|test|prod|which]" >&2
    exit 1
    ;;
esac
