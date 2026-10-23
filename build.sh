#!/bin/zsh
# Builds build/Sirat4mac.app. Pass --install to copy it to /Applications and start it.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Sirat4mac.app"

rm -rf build
mkdir -p "$APP/Contents/MacOS"
cp Info.plist "$APP/Contents/Info.plist"

swiftc -O -swift-version 5 -target arm64-apple-macos13.0 \
  -framework Cocoa -framework ServiceManagement \
  Sources/main.swift -o "$APP/Contents/MacOS/Sirat4mac"

codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  pkill -i -x sirat4mac 2>/dev/null || true
  rm -rf /Applications/Sirat4mac.app
  cp -R "$APP" /Applications/Sirat4mac.app
  open /Applications/Sirat4mac.app
  echo "Installed to /Applications/Sirat4mac.app"
fi
