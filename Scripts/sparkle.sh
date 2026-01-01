#!/usr/bin/env bash
# Prepare Sparkle update: zip, sign, and update appcast.xml
#
# Usage: ./sparkle.sh <path-to-app-bundle> [--commit]
#
# Examples:
#   ./sparkle.sh "Exports/HiFidelity v1.1.2/HiFidelity.app"
#   ./sparkle.sh "Exports/HiFidelity v1.1.2/HiFidelity.app" --commit
#
# Quick reference:
#   1. Build app in Xcode → Copy to Exports folder
#   2. Run: ./Scripts/sparkle.sh "Exports/HiFidelity vX.X.X/HiFidelity.app"
#   3. Commit & push the changes
#
# For more details, see: RELEASE.md or run: ./Scripts/sparkle.sh --help
# Example: ./sparkle.sh "Exports/HiFidelity v1.1.2/HiFidelity.app" --commit

set -euo pipefail

# Parse arguments
APP_BUNDLE=""
AUTO_COMMIT=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --commit)
      AUTO_COMMIT=true
      shift
      ;;
    --help|-h)
      echo "Usage: $0 <path-to-app-bundle> [--commit]"
      echo ""
      echo "Options:"
      echo "  --commit    Automatically commit and push changes to git"
      echo "  --help, -h  Show this help message"
      echo ""
      echo "Example:"
      echo "  $0 \"Exports/HiFidelity v1.0.9/HiFidelity.app\""
      echo "  $0 \"Exports/HiFidelity v1.0.9/HiFidelity.app\" --commit"
      exit 0
      ;;
    *)
      if [[ -z "$APP_BUNDLE" ]]; then
        APP_BUNDLE="$1"
      else
        echo "Error: Unexpected argument: $1" >&2
        exit 1
      fi
      shift
      ;;
  esac
done

if [[ -z "$APP_BUNDLE" ]]; then
  echo "Error: App bundle path is required" >&2
  echo "Usage: $0 <path-to-app-bundle> [--commit]" >&2
  echo "Run '$0 --help' for more information" >&2
  exit 1
fi

# Resolve absolute path
if [[ ! "$APP_BUNDLE" = /* ]]; then
  APP_BUNDLE="$(cd "$(dirname "$APP_BUNDLE")" && pwd)/$(basename "$APP_BUNDLE")"
fi

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "Error: App bundle not found: $APP_BUNDLE" >&2
  exit 1
fi

# Get script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

# Configuration (can be overridden with environment variables)
# Try to find Sparkle tools in common locations
if [[ -z "${SPARKLE_BIN:-}" ]]; then
  if [[ -x "/opt/homebrew/Caskroom/sparkle/2.8.1/bin/sign_update" ]]; then
    SPARKLE_BIN="/opt/homebrew/Caskroom/sparkle/2.8.1/bin"
  elif [[ -x "/tmp/Sparkle-2.8.1/bin/sign_update" ]]; then
    SPARKLE_BIN="/tmp/Sparkle-2.8.1/bin"
  else
    SPARKLE_BIN="/tmp/Sparkle-2.8.1/bin"  # Default fallback
  fi
fi
OUT_DIR="${OUT_DIR:-releases}"
FEED_BASE_URL="${FEED_BASE_URL:-https://juliantraja.github.io/HiFidelity}"

# Check for Sparkle tools
if [[ ! -x "$SPARKLE_BIN/sign_update" ]]; then
  echo "Error: sign_update not found or not executable at $SPARKLE_BIN/sign_update" >&2
  echo "Please set SPARKLE_BIN environment variable or install Sparkle tools." >&2
  exit 1
fi

# Create output directory
mkdir -p "$OUT_DIR"

# Read version info from app bundle
PLIST="$APP_BUNDLE/Contents/Info.plist"
SHORT_VER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PLIST")
BUILD_VER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$PLIST")

ZIP_NAME="HiFidelity-${SHORT_VER}-${BUILD_VER}.zip"
ZIP_PATH="$OUT_DIR/$ZIP_NAME"
SNIPPET_PATH="$OUT_DIR/appcast-item-${SHORT_VER}-${BUILD_VER}.xml"
APPCAST_XML="docs/appcast.xml"

# Step 1: Create zip file
echo "📦 Zipping $APP_BUNDLE -> $ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ZIP_PATH"

# Step 2: Sign update with Sparkle
echo "✍️  Signing update with Sparkle"
SIGN_OUTPUT=$("$SPARKLE_BIN/sign_update" "$ZIP_PATH" | tail -1)
# Extract only the signature value from the sign_update output
SIG=$(echo "$SIGN_OUTPUT" | sed -E 's/.*sparkle:edSignature=\"([^\"]+)\".*/\1/')

# Step 3: Get file size
SIZE=$(stat -f%z "$ZIP_PATH")
PUBDATE=$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")
ZIP_URL="${FEED_BASE_URL}/${ZIP_NAME}"

# Step 4: Create appcast snippet
echo "📄 Creating appcast snippet..."
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

echo "   ✓ Created $SNIPPET_PATH"

# Step 5: Copy zip to docs folder
echo "📋 Copying zip to docs folder..."
cp "$ZIP_PATH" "docs/$ZIP_NAME"
echo "   ✓ Copied to docs/$ZIP_NAME"

# Step 6: Update appcast.xml
echo "📝 Updating appcast.xml..."

# Create temporary appcast with new item at the top
TEMP_APPCAST=$(mktemp)

# Replace all old items with the new one (keep only latest version)
python3 <<PY
import sys
import re
from pathlib import Path

appcast_path = Path("$APPCAST_XML")
snippet_path = Path("$SNIPPET_PATH")
temp_path = Path("$TEMP_APPCAST")

# Read current appcast and snippet
appcast_content = appcast_path.read_text()
snippet_content = snippet_path.read_text()

# Find the position after </language> tag and before </channel> tag
# We'll remove all existing <item> entries and insert the new one
match = re.search(r'(</language>\s*\n)', appcast_content)
channel_end_match = re.search(r'(\s*</channel>)', appcast_content)

if match and channel_end_match:
    insert_pos = match.end()
    channel_end_pos = channel_end_match.start()
    
    # Remove all existing items (everything between </language> and </channel>)
    # and replace with just the new item
    new_appcast = (
        appcast_content[:insert_pos] +
        snippet_content.rstrip() + "\n" +
        appcast_content[channel_end_pos:]
    )
    
    # Write to temp file
    temp_path.write_text(new_appcast)
    sys.exit(0)
else:
    print("Error: Could not find insertion point in appcast.xml", file=sys.stderr)
    sys.exit(1)
PY

if [[ $? -ne 0 ]]; then
  echo "Error: Failed to update appcast.xml" >&2
  rm -f "$TEMP_APPCAST"
  exit 1
fi

# Replace original appcast
mv "$TEMP_APPCAST" "$APPCAST_XML"
echo "   ✓ Updated $APPCAST_XML"

echo ""
echo "✅ Sparkle update prepared successfully!"
echo ""
echo "Summary:"
echo "  Version: ${SHORT_VER} (Build ${BUILD_VER})"
echo "  Signature: ${SIG:0:20}..."
echo "  Size: ${SIZE} bytes"
echo ""
echo "Files created/updated:"
echo "  📦 docs/$ZIP_NAME"
echo "  📄 $APPCAST_XML"
echo ""

# Auto-commit if requested
if [[ "$AUTO_COMMIT" == true ]]; then
  echo "📤 Committing and pushing to git..."
  git add "docs/$ZIP_NAME" "$APPCAST_XML"
  git commit -m "Release version ${SHORT_VER} (build ${BUILD_VER})"
  git push
  echo "   ✓ Changes committed and pushed"
  echo ""
  echo "🎉 Done! The update is now live."
  echo "   Verify: https://juliantraja.github.io/HiFidelity/appcast.xml"
else
  echo "Next steps:"
  echo "1. Review the changes:"
  echo "   - docs/$ZIP_NAME"
  echo "   - docs/appcast.xml"
  echo ""
  echo "2. Commit and push to GitHub (use Cursor UI or run):"
  echo "   git add docs/$ZIP_NAME docs/appcast.xml"
  echo "   git commit -m \"Release version ${SHORT_VER} (build ${BUILD_VER})\""
  echo "   git push"
  echo ""
  echo "   Or run with --commit flag to auto-commit:"
  echo "   $0 \"$APP_BUNDLE\" --commit"
  echo ""
  echo "3. Verify the appcast is accessible:"
  echo "   https://juliantraja.github.io/HiFidelity/appcast.xml"
fi
