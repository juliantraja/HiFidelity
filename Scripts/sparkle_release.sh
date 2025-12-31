#!/usr/bin/env bash
# Minimal helper to package and sign a Sparkle update for HiFidelity.
set -euo pipefail

# Path to the built .app (set APP_BUNDLE env or pass as first arg).
# No hardcoded default to avoid packaging an old export by mistake.
APP_BUNDLE="${APP_BUNDLE:-${1:-""}}"

# Where Sparkle tools live (adjust if you unpacked elsewhere).
SPARKLE_BIN="${SPARKLE_BIN:-/tmp/Sparkle-2.8.1/bin}"

# Where to write the zip and snippet.
OUT_DIR="${OUT_DIR:-releases}"

# Public URL base where the zip will be hosted (used in the snippet).
FEED_BASE_URL="${FEED_BASE_URL:-https://juliantraja.github.io/HiFidelity}"

if [[ -z "$APP_BUNDLE" ]]; then
  echo "APP_BUNDLE not specified. Set APP_BUNDLE env or pass the .app path as first arg." >&2
  exit 1
fi

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "App bundle not found: $APP_BUNDLE" >&2
  exit 1
fi

if [[ ! -x "$SPARKLE_BIN/sign_update" ]]; then
  echo "sign_update not found or not executable at $SPARKLE_BIN/sign_update" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"

PLIST="$APP_BUNDLE/Contents/Info.plist"
SHORT_VER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PLIST")
BUILD_VER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$PLIST")

ZIP_NAME="HiFidelity-${SHORT_VER}-${BUILD_VER}.zip"
ZIP_PATH="$OUT_DIR/$ZIP_NAME"

echo "Zipping $APP_BUNDLE -> $ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ZIP_PATH"

echo "Signing update with Sparkle"
SIGN_OUTPUT=$("$SPARKLE_BIN/sign_update" "$ZIP_PATH" | tail -1)
# Extract only the signature value from the sign_update output (which looks like: sparkle:edSignature="..." length="...")
SIG=$(echo "$SIGN_OUTPUT" | sed -E 's/.*sparkle:edSignature=\"([^\"]+)\".*/\1/')

SIZE=$(stat -f%z "$ZIP_PATH")
PUBDATE=$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")
ZIP_URL="${FEED_BASE_URL}/${ZIP_NAME}"

SNIPPET_PATH="$OUT_DIR/appcast-item-${SHORT_VER}-${BUILD_VER}.xml"
cat > "$SNIPPET_PATH" <<EOF
    <item>
      <title>Version ${SHORT_VER}</title>
      <pubDate>${PUBDATE}</pubDate>
      <enclosure
        url="${ZIP_URL}"
        sparkle:edSignature="${SIG}"
        length="${SIZE}"
        type="application/octet-stream"
        sparkle:version="${BUILD_VER}"
        sparkle:shortVersionString="${SHORT_VER}" />
    </item>
EOF

echo ""
echo "Done."
echo "Zip:        $ZIP_PATH"
echo "Signature:  $SIG"
echo "Size:       $SIZE bytes"
echo "Snippet:    $SNIPPET_PATH"
echo ""
echo "Next:"
echo "1) Upload ${ZIP_PATH} to ${ZIP_URL}"
echo "2) Insert ${SNIPPET_PATH} into your appcast.xml"
echo "3) Commit/push the zip + appcast to GitHub Pages (or your host)"
