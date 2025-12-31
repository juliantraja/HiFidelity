#!/usr/bin/env bash
# Bump app version/build, build Release, and produce a signed Sparkle zip + appcast snippet.
set -euo pipefail

PBXPROJ="HiFidelity.xcodeproj/project.pbxproj"
SCHEME="${SCHEME:-HiFidelity}"
CONFIG="${CONFIG:-Release}"
DERIVED_DATA="${DERIVED_DATA:-build}"
SPARKLE_BIN="${SPARKLE_BIN:-/tmp/Sparkle-2.8.1/bin}"
FEED_BASE_URL="${FEED_BASE_URL:-https://juliantraja.github.io/HiFidelity}"
OUT_DIR="${OUT_DIR:-releases}"

if [[ ! -f "$PBXPROJ" ]]; then
  echo "Missing $PBXPROJ" >&2
  exit 1
fi
if [[ ! -x "$SPARKLE_BIN/sign_update" ]]; then
  echo "Sparkle sign_update not found/executable at $SPARKLE_BIN/sign_update" >&2
  exit 1
fi

# Read current versions without requiring ripgrep
read_versions() {
  python3 - "$PBXPROJ" <<'PY'
import sys, re, pathlib
pbx = pathlib.Path(sys.argv[1]).read_text()
def pick(pattern):
    m = re.search(pattern, pbx)
    return m.group(1) if m else ""
ver = pick(r"MARKETING_VERSION = ([^;]+);")
build = pick(r"CURRENT_PROJECT_VERSION = ([^;]+);")
print(ver)
print(build)
PY
}
CURR_VER=$(read_versions | sed -n '1p')
CURR_BUILD=$(read_versions | sed -n '2p')

if [[ -z "$CURR_VER" ]]; then
  echo "Could not read MARKETING_VERSION from $PBXPROJ" >&2
  exit 1
fi
if [[ -z "$CURR_BUILD" ]]; then
  echo "Could not read CURRENT_PROJECT_VERSION from $PBXPROJ" >&2
  exit 1
fi

NEXT_VER=$(python3 - "$CURR_VER" <<'PY'
import sys
curr = sys.argv[1]
parts = curr.split(".")
if not parts or not all(p.isdigit() for p in parts):
    print(curr)
    sys.exit()
nums = list(map(int, parts))
nums[-1] += 1
print(".".join(map(str, nums)))
PY
)
NEXT_BUILD=$(( ${CURR_BUILD:-0} + 1 ))

read -r -p "Release version [$NEXT_VER]: " INPUT_VER
RELEASE_VER=${INPUT_VER:-$NEXT_VER}
read -r -p "Build number [$NEXT_BUILD]: " INPUT_BUILD
RELEASE_BUILD=${INPUT_BUILD:-$NEXT_BUILD}

PBXPROJ="$PBXPROJ" RELEASE_VER="$RELEASE_VER" RELEASE_BUILD="$RELEASE_BUILD" python3 - <<'PY'
from pathlib import Path
import os, re
pbx = Path(os.environ["PBXPROJ"])
release_ver = os.environ["RELEASE_VER"]
release_build = os.environ["RELEASE_BUILD"]
text = pbx.read_text()
text = re.sub(r"MARKETING_VERSION = [^;]+;", f"MARKETING_VERSION = {release_ver};", text)
text = re.sub(r"CURRENT_PROJECT_VERSION = [^;]+;", f"CURRENT_PROJECT_VERSION = {release_build};", text)
pbx.write_text(text)
PY

echo "Cleaning extended attributes in derived data (to avoid codesign FinderInfo/resource fork issues)..."
xattr -cr "$DERIVED_DATA" 2>/dev/null || true
# Also strip attributes from the workspace itself (helps prevent FinderInfo/resource forks being copied into the product).
xattr -cr . 2>/dev/null || true

echo "Clearing previous derived data..."
rm -rf "$DERIVED_DATA"

echo "Building $SCHEME ($CONFIG)..."
COPYFILE_DISABLE=1 xcodebuild -scheme "$SCHEME" -configuration "$CONFIG" -derivedDataPath "$DERIVED_DATA" -quiet build

APP_BUNDLE="$DERIVED_DATA/Build/Products/$CONFIG/HiFidelity.app"
if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "Built app not found at $APP_BUNDLE" >&2
  exit 1
fi

APP_BUNDLE="$APP_BUNDLE" SPARKLE_BIN="$SPARKLE_BIN" FEED_BASE_URL="$FEED_BASE_URL" OUT_DIR="$OUT_DIR" bash Scripts/sparkle_release.sh

echo ""
echo "Release prep complete."
echo "pbxproj updated to version $RELEASE_VER (build $RELEASE_BUILD)."
