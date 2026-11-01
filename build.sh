#!/bin/zsh
# Builds Nyheter.app (with Nyheter.saver inside) and a shareable zip.
#   ./build.sh                 build into ./build
#   ./build.sh install         also copy the app to /Applications and install the saver
#   ./build.sh snapshots       render every theme to build/snapshots (offscreen test)
#
# Sharing: by default the app is ad-hoc signed, so other Macs will ask the user to
# allow it under System Settings › Privacy & Security. With a paid Apple Developer
# account, set SIGN_ID="Developer ID Application: …" and NOTARY_PROFILE=<notarytool
# keychain profile> to sign and notarize, and it opens without warnings.
set -euo pipefail
cd "${0:A:h}"

VERSION=1.0
BUILD_NUMBER=$(date +%Y%m%d%H%M)
TARGET=14.0     # NSImage renders the bundled Lucide SVGs natively from macOS 14
OUT=build
APP=$OUT/Nyheter.app
SAVER=$OUT/Nyheter.saver
SIGN_ID=${SIGN_ID:--}

rm -rf $OUT && mkdir -p $OUT/tmp

# Universal binary from per-architecture builds: universal <output> <swiftc flags…>
universal() {
  local output=$1; shift
  for arch in arm64 x86_64; do
    swiftc -O -target "$arch-apple-macos$TARGET" "$@" -o "$OUT/tmp/bin-$arch"
  done
  lipo -create $OUT/tmp/bin-arm64 $OUT/tmp/bin-x86_64 -output "$output"
}

plist() { # plist <file> <id> <name> <executable> <type> [extra xml]
  cat > "$1" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>$2</string>
  <key>CFBundleName</key><string>$3</string>
  <key>CFBundleDisplayName</key><string>$3</string>
  <key>CFBundleExecutable</key><string>$4</string>
  <key>CFBundlePackageType</key><string>$5</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key><string>$TARGET</string>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key><array>$(for d in Resources/l10n/*.lproj; do printf '<string>%s</string>' "$(basename "$d" .lproj)"; done)</array>
  <key>NSHumanReadableCopyright</key><string>Nyheter från SVT, SR, DN och SCB.</string>
  ${6:-}
</dict>
</plist>
PLIST
}

echo "› Translations"
python3 tools/check-l10n.py

echo "› Screen saver"
mkdir -p $SAVER/Contents/MacOS
universal $SAVER/Contents/MacOS/Nyheter -emit-library -module-name Nyheter \
  -framework ScreenSaver -framework CoreImage Shared/*.swift Saver/*.swift
mkdir -p $SAVER/Contents/Resources && cp -R Resources/lucide $SAVER/Contents/Resources/
cp -R Resources/l10n/*.lproj $SAVER/Contents/Resources/
plist $SAVER/Contents/Info.plist local.nyheter.saver Nyheter Nyheter BNDL \
  "<key>NSPrincipalClass</key><string>NyheterSaverView</string>"

echo "› App"
mkdir -p $APP/Contents/MacOS $APP/Contents/Resources
universal $APP/Contents/MacOS/Nyheter -parse-as-library -module-name NyheterApp \
  -framework CoreImage Shared/*.swift App/*.swift
plist $APP/Contents/Info.plist local.nyheter.app Nyheter Nyheter APPL \
  "<key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.news</string>
  <key>NSHighResolutionCapable</key><true/>"

echo "› Icon"
swiftc -O tools/make-icon.swift -o $OUT/tmp/make-icon
$OUT/tmp/make-icon $OUT/tmp/icon.png
ICONSET=$OUT/tmp/AppIcon.iconset && mkdir -p $ICONSET
for s in 16 32 128 256 512; do
  sips -z $s $s $OUT/tmp/icon.png --out $ICONSET/icon_${s}x${s}.png >/dev/null
  sips -z $((s*2)) $((s*2)) $OUT/tmp/icon.png --out $ICONSET/icon_${s}x${s}@2x.png >/dev/null
done
iconutil -c icns $ICONSET -o $APP/Contents/Resources/AppIcon.icns
cp -R Resources/lucide $APP/Contents/Resources/
cp -R Resources/l10n/*.lproj $APP/Contents/Resources/

echo "› Sign"
SIGN_FLAGS=(--force --sign "$SIGN_ID")
[[ $SIGN_ID != - ]] && SIGN_FLAGS+=(--options runtime --timestamp)
codesign "${SIGN_FLAGS[@]}" $SAVER
cp -R $SAVER $APP/Contents/Resources/
codesign "${SIGN_FLAGS[@]}" $APP

echo "› Package"
ditto -c -k --keepParent $APP $OUT/Nyheter.zip
if [[ -n ${NOTARY_PROFILE:-} ]]; then
  xcrun notarytool submit $OUT/Nyheter.zip --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple $APP
  rm $OUT/Nyheter.zip && ditto -c -k --keepParent $APP $OUT/Nyheter.zip
fi
echo "Built $APP and $OUT/Nyheter.zip"

case "${1:-}" in
  install)
    DEST=/Applications; [[ -w $DEST ]] || DEST=$HOME/Applications
    mkdir -p "$DEST" && rm -rf "$DEST/Nyheter.app" && cp -R $APP "$DEST/"
    mkdir -p "$HOME/Library/Screen Savers"
    rm -rf "$HOME/Library/Screen Savers/Nyheter.saver" "$HOME/Library/Screen Savers/NewsSaver.saver"
    cp -R $SAVER "$HOME/Library/Screen Savers/"
    killall legacyScreenSaver 2>/dev/null || true
    echo "Installed $DEST/Nyheter.app and the screen saver"
    ;;
  snapshots)
    mkdir -p $OUT/snapshots $OUT/tmp/harness
    cp tools/harness.swift $OUT/tmp/harness/main.swift
    swiftc -O -framework CoreImage Shared/*.swift $OUT/tmp/harness/main.swift -o $OUT/tmp/harness/harness
    for theme in morgon morgonbild natt svea schweiz pastel matrix skyddsrum terminal; do
      $OUT/tmp/harness/harness $OUT/snapshots/$theme $theme 1 4 11 &
    done
    wait
    ;;
esac
rm -rf $OUT/tmp
