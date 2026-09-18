#!/bin/bash
# Build a standalone, relocatable Pyramid Principle.app plus a .dmg installer.
# Needs only the Xcode command line tools — no Node, no Rust, no packages.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/../governing-thought.html"
OUT="$HERE/build"
APP="$OUT/Pyramid Principle.app"
C="$APP/Contents"
WWW="$C/Resources/www"

[ -f "$SRC" ] || { echo "error: cannot find $SRC"; exit 1; }

echo "› cleaning"
rm -rf "$OUT"; mkdir -p "$C/MacOS" "$WWW/fonts"

# ── fonts ────────────────────────────────────────────────────────────────────
# Bundled so the app is genuinely offline. Newsreader and IBM Plex are both
# SIL Open Font License 1.1, which permits redistribution inside an app.
echo "› fetching fonts (for offline use)"
UA="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Safari/537.36"
GF="https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@400;500;600&family=IBM+Plex+Sans:wght@400;500;600&family=Newsreader:ital,opsz,wght@0,6..72,400;0,6..72,500;0,6..72,600;1,6..72,400&family=Orbitron:wght@400;500;600;700;800&family=Exo+2:ital,wght@0,400;0,500;0,600;0,700;1,400&family=Share+Tech+Mono&display=swap"  # + the ClaudWorkSpace/ui-kit HUD skin's three families
FONTS_OK=0
if curl -sS -m 45 -A "$UA" "$GF" -o "$OUT/fonts.css" 2>/dev/null && [ -s "$OUT/fonts.css" ]; then
  n=0
  while read -r u; do
    f="$(basename "$u")"
    curl -sS -m 45 -o "$WWW/fonts/$f" "$u" 2>/dev/null && n=$((n+1))
  done < <(grep -o 'https://fonts.gstatic.com[^)]*' "$OUT/fonts.css" | sort -u)
  # point the stylesheet at the bundled copies
  sed -E 's#https://fonts\.gstatic\.com[^)]*/([^/)]+\.woff2)#fonts/\1#g' "$OUT/fonts.css" > "$WWW/fonts.css"
  echo "  bundled $n font files"
  [ "$n" -gt 0 ] && FONTS_OK=1
else
  echo "  offline — the app will pull fonts from the network, or fall back to system faces"
fi

# ── page ─────────────────────────────────────────────────────────────────────
# The web app is authored as a fragment: the Artifact host supplies the doctype,
# a charset meta and a small reset at publish time. Standing alone it needs the
# same skeleton — without the charset every curly quote and £ becomes mojibake.
echo "› wrapping the page"
python3 - "$SRC" "$WWW/index.html" "$FONTS_OK" <<'PY'
import io, re, sys
frag = io.open(sys.argv[1], encoding='utf-8').read()
if sys.argv[3] == '1':
    # use the bundled stylesheet instead of the CDN, and drop the preconnects
    frag = re.sub(r'<link rel="preconnect"[^>]*>\s*', '', frag)
    frag = re.sub(r'<link rel="stylesheet" href="https://fonts\.googleapis\.com[^"]*">',
                  '<link rel="stylesheet" href="fonts.css">', frag)
page = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
  :root { color-scheme: light dark; }
  body { margin: 0; font: 14px -apple-system, BlinkMacSystemFont, sans-serif; background: #fbfbfa; }
  img { max-width: 100%; }
  [hidden] { display: none !important; }
</style>
</head>
<body>
""" + frag + """
</body>
</html>
"""
io.open(sys.argv[2], 'w', encoding='utf-8').write(page)
print("  page is %d KB, fonts %s" % (len(page.encode('utf-8')) // 1024,
      "bundled" if sys.argv[3] == '1' else "from CDN"))
PY

# ── binary ───────────────────────────────────────────────────────────────────
# Universal, so it runs on both Apple Silicon and Intel Macs.
echo "› compiling (arm64 + x86_64)"
for ARCH in arm64 x86_64; do
  swiftc -O -target "$ARCH-apple-macosx11.0" \
    -framework Cocoa -framework WebKit \
    "$HERE/main.swift" -o "$OUT/gt-$ARCH"
done
lipo -create "$OUT/gt-arm64" "$OUT/gt-x86_64" -output "$C/MacOS/PyramidPrinciple"
rm -f "$OUT/gt-arm64" "$OUT/gt-x86_64"
echo "  $(lipo -archs "$C/MacOS/PyramidPrinciple")"

echo "› drawing the icon"
ICONSET="$OUT/AppIcon.iconset"; mkdir -p "$ICONSET"
"$C/MacOS/PyramidPrinciple" --emit-iconset "$ICONSET"
iconutil -c icns "$ICONSET" -o "$C/Resources/AppIcon.icns"
rm -rf "$ICONSET" "$OUT/fonts.css"

echo "› writing Info.plist"
cat > "$C/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>              <string>Pyramid Principle</string>
  <key>CFBundleDisplayName</key>       <string>Pyramid Principle</string>
  <key>CFBundleExecutable</key>        <string>PyramidPrinciple</string>
  <key>CFBundleIdentifier</key>        <string>com.governingthought.app</string>
  <key>CFBundleIconFile</key>          <string>AppIcon</string>
  <key>CFBundlePackageType</key>       <string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key>           <string>1</string>
  <key>LSMinimumSystemVersion</key>    <string>11.0</string>
  <key>LSApplicationCategoryType</key> <string>public.app-category.productivity</string>
  <key>NSHighResolutionCapable</key>   <true/>
</dict>
PLIST
echo "</plist>" >> "$C/Info.plist"

echo "› signing"
if [ -n "${GT_SIGN_ID:-}" ]; then
  codesign --force --deep --options runtime --timestamp --sign "$GT_SIGN_ID" "$APP"
  echo "  signed with Developer ID: $GT_SIGN_ID"
else
  codesign --force --deep --sign - "$APP"
  echo "  ad-hoc signed (fine on this Mac; see README to distribute)"
fi

# ── installer ────────────────────────────────────────────────────────────────
echo "› building the disk image"
STAGE="$OUT/dmg"; rm -rf "$STAGE"; mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Pyramid Principle" -srcfolder "$STAGE" \
  -ov -format UDZO -quiet "$OUT/PyramidPrinciple.dmg"
rm -rf "$STAGE"

echo
echo "App: $APP  ($(du -sh "$APP" | cut -f1))"
echo "DMG: $OUT/PyramidPrinciple.dmg  ($(du -sh "$OUT/PyramidPrinciple.dmg" | cut -f1))"
echo
echo "Verify:  \"$C/MacOS/PyramidPrinciple\" --selftest"
echo "Install: open \"$OUT/PyramidPrinciple.dmg\"   then drag across"
