#!/bin/zsh
# Baut build/KundidaToolbox.app (Universal, Sparkle eingebettet, ad-hoc signiert).
# Signieren, Notarisieren und Veröffentlichen übernimmt:
#   ~/Developer/signing/release.sh KundidaToolbox <Version>
# Version:  RELEASE_VERSION (vom Release-Aufruf) oder CFBundleShortVersionString aus Distribution/Info.plist
# Build:    BUILD_NUMBER oder automatisch JJJJ.MM.TT.HHMM (monoton steigend, wie bei Forseti)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP="build/KundidaToolbox.app"
PLIST_SRC="Distribution/Info.plist"
VERSION="${RELEASE_VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST_SRC")}"
BUILD="${BUILD_NUMBER:-$(date +%Y.%m.%d.%H%M)}"

echo "▸ Baue Kundida Toolbox $VERSION ($BUILD)…"
swift build -c release --arch arm64 --arch x86_64
BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"

rm -rf "$APP" build/KundidaToolbox.zip
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN_DIR/KundidaToolbox" "$APP/Contents/MacOS/KundidaToolbox"
cp Distribution/KundidaToolbox.icns "$APP/Contents/Resources/KundidaToolbox.icns"
cp "$PLIST_SRC" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" -c "Set :CFBundleVersion $BUILD" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "▸ Bette Sparkle.framework ein…"
SPARKLE_FW="$(find .build -type d -name Sparkle.framework -path '*macos*' | head -n 1)"
[[ -n "$SPARKLE_FW" ]] || { echo "❌ Sparkle.framework nicht gefunden"; exit 1; }
/usr/bin/ditto "$SPARKLE_FW" "$APP/Contents/Frameworks/Sparkle.framework"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/KundidaToolbox" 2>/dev/null || true

echo "▸ Ad-hoc-Signatur (Developer ID folgt in release.sh)…"
xattr -cr "$APP"
codesign --force --deep -s - --timestamp=none "$APP"

echo "✓ Fertig: $APP"
