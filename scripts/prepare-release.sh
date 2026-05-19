#!/usr/bin/env bash
# Quick pre-release checks. Archive, notarize, and zip are done in Xcode — see docs/RELEASE.md.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "==> Running unit tests…"
xcodebuild -scheme Ingestr -destination 'platform=macOS' test

echo "==> Release build…"
xcodebuild -scheme Ingestr -configuration Release -destination 'platform=macOS' build

APP="$(find ~/Library/Developer/Xcode/DerivedData/Ingestr-*/Build/Products/Release -name 'Ingestr.app' -maxdepth 1 2>/dev/null | head -1)"
if [[ -n "$APP" ]]; then
  VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
  BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
  echo "==> Built Ingestr $VERSION ($BUILD) at:"
  echo "    $APP"
else
  echo "==> Release build succeeded (could not locate Ingestr.app in DerivedData)."
fi

echo ""
echo "Next: Product → Archive in Xcode, then follow docs/RELEASE.md"
