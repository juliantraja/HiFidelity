#!/usr/bin/env bash
# Complete release workflow: Build, Sparkle update, and GitHub Release
#
# Usage: ./release.sh [options]
#
# This script combines:
# 1. Building the app (optional, if DMG not provided)
# 2. Creating Sparkle update (optional)
# 3. Creating GitHub Release with changelog
#
# Examples:
#   ./release.sh --version 1.0.10 --build
#   ./release.sh --version 1.0.10 --dmg "build/HiFidelity-1.0.10-Universal.dmg"
#   ./release.sh --version 1.0.10 --build --sparkle --github

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}✅${NC} $1"; }
error() { echo -e "${RED}❌${NC} $1" >&2; }
warning() { echo -e "${YELLOW}⚠️${NC} $1"; }
info() { echo -e "${BLUE}ℹ️${NC} $1"; }

# Configuration
VERSION=""
BUILD=false
SPARKLE=false
GITHUB_RELEASE=false
DMG_PATH=""
APP_BUNDLE=""
AUTO_CHANGELOG=true
DRAFT=false
PRERELEASE=false

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

print_usage() {
    cat << EOF
Usage: $0 [options]

Options:
  --version <version>     Version number (e.g., 1.0.10) [required]
  --build                 Build the app first (runs build.sh)
  --sparkle              Create Sparkle update (requires --app-bundle)
  --github               Create GitHub Release
  --app-bundle <path>    Path to app bundle (for Sparkle)
  --dmg <path>           Path to DMG file (for GitHub release)
  --auto-changelog        Generate changelog from git commits (default: true)
  --draft                Create draft release
  --prerelease           Mark as pre-release
  --all                  Do everything: build, sparkle, and github release
  --help                 Show this help message

Examples:
  # Full release workflow
  $0 --version 1.0.10 --all

  # Just create GitHub release from existing DMG
  $0 --version 1.0.10 --dmg "build/HiFidelity-1.0.10-Universal.dmg" --github

  # Build and create GitHub release
  $0 --version 1.0.10 --build --github

EOF
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --version)
            VERSION="$2"
            shift 2
            ;;
        --build)
            BUILD=true
            shift
            ;;
        --sparkle)
            SPARKLE=true
            shift
            ;;
        --github)
            GITHUB_RELEASE=true
            shift
            ;;
        --app-bundle)
            APP_BUNDLE="$2"
            shift 2
            ;;
        --dmg)
            DMG_PATH="$2"
            shift 2
            ;;
        --auto-changelog)
            AUTO_CHANGELOG=true
            shift
            ;;
        --draft)
            DRAFT=true
            shift
            ;;
        --prerelease)
            PRERELEASE=true
            shift
            ;;
        --all)
            BUILD=true
            SPARKLE=true
            GITHUB_RELEASE=true
            shift
            ;;
        --help|-h)
            print_usage
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            print_usage
            exit 1
            ;;
    esac
done

# Validate version
if [[ -z "$VERSION" ]]; then
    error "Version is required. Use --version <version>"
    exit 1
fi

VERSION="${VERSION#v}"

# Step 1: Build
if [[ "$BUILD" == true ]]; then
    info "Building app..."
    if ! "$SCRIPT_DIR/build.sh" --version "$VERSION"; then
        error "Build failed"
        exit 1
    fi
    
    # Find the created DMG
    if [[ -z "$DMG_PATH" ]]; then
        DMG_PATH=$(find build -name "HiFidelity-${VERSION}*.dmg" -type f | head -1)
        if [[ -n "$DMG_PATH" ]]; then
            log "Found DMG: $DMG_PATH"
        fi
    fi
    
    # Find app bundle for Sparkle
    if [[ -z "$APP_BUNDLE" && "$SPARKLE" == true ]]; then
        # Look in Exports folder
        APP_BUNDLE="Exports/HiFidelity v${VERSION}/HiFidelity.app"
        if [[ ! -d "$APP_BUNDLE" ]]; then
            warning "App bundle not found at $APP_BUNDLE"
            warning "You may need to export the app from Xcode first"
        fi
    fi
fi

# Step 2: Sparkle update
if [[ "$SPARKLE" == true ]]; then
    if [[ -z "$APP_BUNDLE" ]]; then
        error "App bundle required for Sparkle update. Use --app-bundle <path>"
        exit 1
    fi
    
    if [[ ! -d "$APP_BUNDLE" ]]; then
        error "App bundle not found: $APP_BUNDLE"
        exit 1
    fi
    
    info "Creating Sparkle update..."
    if ! "$SCRIPT_DIR/sparkle.sh" "$APP_BUNDLE"; then
        error "Sparkle update failed"
        exit 1
    fi
fi

# Step 3: GitHub Release
if [[ "$GITHUB_RELEASE" == true ]]; then
    info "Creating GitHub Release..."
    
    RELEASE_ARGS=(
        --version "$VERSION"
        --auto-changelog
    )
    
    [[ "$DRAFT" == true ]] && RELEASE_ARGS+=(--draft)
    [[ "$PRERELEASE" == true ]] && RELEASE_ARGS+=(--prerelease)
    
    # Add DMG if available
    if [[ -n "$DMG_PATH" && -f "$DMG_PATH" ]]; then
        RELEASE_ARGS+=(--dmg "$DMG_PATH")
    else
        # Try to find DMG in build directory
        FOUND_DMG=$(find build -name "HiFidelity-${VERSION}*.dmg" -type f 2>/dev/null | head -1)
        if [[ -n "$FOUND_DMG" ]]; then
            RELEASE_ARGS+=(--dmg "$FOUND_DMG")
            log "Found DMG: $FOUND_DMG"
        fi
    fi
    
    if ! "$SCRIPT_DIR/create-release.sh" "${RELEASE_ARGS[@]}"; then
        error "GitHub Release failed"
        exit 1
    fi
fi

# Summary
echo ""
log "Release workflow completed!"
echo ""
echo "  Version: ${VERSION}"
[[ "$BUILD" == true ]] && echo "  ✅ Built app"
[[ "$SPARKLE" == true ]] && echo "  ✅ Created Sparkle update"
[[ "$GITHUB_RELEASE" == true ]] && echo "  ✅ Created GitHub Release"
echo ""

