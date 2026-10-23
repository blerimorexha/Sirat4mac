#!/bin/zsh
# Builds build/sirat4mac.app. Pass --install to copy it to /Applications and start it.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/sirat4mac.app"

rm -rf build
mkdir -p "$APP/Contents/MacOS"
cp Info.plist "$APP/Contents/Info.plist"

swiftc -O -swift-version 5 -target arm64-apple-macos13.0 \
  -framework Cocoa -framework ServiceManagement \
  Sources/main.swift -o "$APP/Contents/MacOS/sirat4mac"

codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x sirat4mac 2>/dev/null || true
  rm -rf /Applications/sirat4mac.app
  cp -R "$APP" /Applications/sirat4mac.app
  open /Applications/sirat4mac.app
  echo "Installed to /Applications/sirat4mac.app"
fi
