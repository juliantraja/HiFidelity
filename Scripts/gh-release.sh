#!/usr/bin/env bash
# Create a GitHub Release with changelog and assets
#
# Usage: ./gh-release.sh [options]
#
# Examples:
#   ./gh-release.sh --version 1.0.10
#   ./gh-release.sh --version 1.0.10 --dmg "build/HiFidelity-1.0.10-Universal.dmg"
#   ./gh-release.sh --version 1.0.10 --changelog "Release notes"
#
# This script can:
# - Create a GitHub release with a tag
# - Generate changelog from git commits
# - Upload DMG files as release assets
# - Work with GitHub CLI (gh) or GitHub API

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging
log() { echo -e "${GREEN}✅${NC} $1"; }
error() { echo -e "${RED}❌${NC} $1" >&2; }
warning() { echo -e "${YELLOW}⚠️${NC} $1"; }
info() { echo -e "${BLUE}ℹ️${NC} $1"; }

# Configuration
VERSION=""
DMG_PATH=""
AUTO_CHANGELOG=false
DRAFT=false
PRERELEASE=false
REPO=""
GITHUB_TOKEN=""
USE_GH_CLI=true

# Get script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

# Parse arguments
print_usage() {
    cat << EOF
Usage: $0 [options]

Options:
  --version <version>     Version number (e.g., 1.0.10) [required]
  --dmg <path>           Path to DMG file to upload (can be used multiple times)
  --asset <path>         Path to any asset file to upload (zip, dmg, etc.) (can be used multiple times)
  --auto-changelog        [DEPRECATED] Generate changelog from git commits (use --changelog instead)
  --changelog <text>      Use custom changelog text
  --update-only          Only update release notes, don't create new release
  --draft                 Create as draft release
  --prerelease           Mark as pre-release
  --repo <owner/repo>     GitHub repository (default: auto-detect from git remote)
  --token <token>        GitHub token (default: from GITHUB_TOKEN env or gh auth)
  --no-gh-cli            Use GitHub API instead of gh CLI
  --help                 Show this help message

Examples:
  # Create release with auto-generated changelog
  $0 --version 1.0.10 --auto-changelog

  # Create release with DMG asset
  $0 --version 1.0.10 --dmg "build/HiFidelity-1.0.10-Universal.dmg"

  # Create draft release
  $0 --version 1.0.10 --draft --auto-changelog

EOF
}

DMG_PATHS=()
ASSET_PATHS=()

while [[ $# -gt 0 ]]; do
    case $1 in
        --version)
            VERSION="$2"
            shift 2
            ;;
        --dmg)
            DMG_PATHS+=("$2")
            ASSET_PATHS+=("$2")
            shift 2
            ;;
        --asset)
            ASSET_PATHS+=("$2")
            shift 2
            ;;
        --auto-changelog)
            AUTO_CHANGELOG=true
            shift
            ;;
        --changelog)
            CHANGELOG="$2"
            shift 2
            ;;
        --draft)
            DRAFT=true
            shift
            ;;
        --prerelease)
            PRERELEASE=true
            shift
            ;;
        --repo)
            REPO="$2"
            shift 2
            ;;
        --token)
            GITHUB_TOKEN="$2"
            shift 2
            ;;
        --no-gh-cli)
            USE_GH_CLI=false
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

# Remove 'v' prefix if present
VERSION="${VERSION#v}"
TAG="v${VERSION}"

# Auto-detect repository from git remote
if [[ -z "$REPO" ]]; then
    if git remote get-url origin &>/dev/null; then
        REMOTE_URL=$(git remote get-url origin)
        # Extract owner/repo from various URL formats
        if [[ "$REMOTE_URL" =~ github\.com[:/]([^/]+)/([^/]+)(\.git)?$ ]]; then
            REPO="${BASH_REMATCH[1]}/${BASH_REMATCH[2]%.git}"
            log "Auto-detected repository: $REPO"
        else
            error "Could not detect GitHub repository from git remote"
            error "Please specify with --repo <owner/repo>"
            exit 1
        fi
    else
        error "No git remote found. Please specify --repo <owner/repo>"
        exit 1
    fi
fi

# Check for GitHub CLI and get token
if [[ "$USE_GH_CLI" == true ]]; then
    if ! command -v gh &>/dev/null; then
        warning "GitHub CLI (gh) not found. Falling back to API method."
        USE_GH_CLI=false
    else
        # Try to get token from gh CLI
        GITHUB_TOKEN=$(gh auth token 2>/dev/null || echo "")
        if [[ -z "$GITHUB_TOKEN" ]]; then
            warning "GitHub CLI not authenticated. Falling back to API method."
            USE_GH_CLI=false
        else
            log "Using GitHub CLI for authentication"
        fi
    fi
fi

# Get GitHub token if not already set
if [[ -z "$GITHUB_TOKEN" ]]; then
    # Try environment variable
    GITHUB_TOKEN="${GITHUB_TOKEN:-}"
    
    if [[ -z "$GITHUB_TOKEN" ]]; then
        error "GitHub token required. Set GITHUB_TOKEN environment variable or use 'gh auth login'"
        exit 1
    fi
fi

# Generate changelog with smart filtering
generate_changelog() {
    local tag="$1"
    local prev_tag
    
    # Find previous tag (get all tags, sort, find the one before current)
    prev_tag=$(git tag -l | grep -E "^v[0-9]+\.[0-9]+\.[0-9]+" | sort -V | grep -B1 "^${tag}$" | head -1)
    
    # Fallback: try git describe method
    if [[ -z "$prev_tag" ]]; then
        prev_tag=$(git describe --tags --abbrev=0 "${tag}^" 2>/dev/null || echo "")
    fi
    
    # Patterns to exclude (maintenance/script commits)
    local exclude_patterns=(
        "updated.*script"
        "update.*script"
        "script.*improvement"
        "update readme"
        "update.*readme"
        "update license"
        "update.*license"
        "delete.*zip"
        "deleted.*file"
        "publish.*sparkle"
        "sparkle.*update"
        "updated project.pbxproj"
        "describe your changes"
        "stop tracking.*xcode"
        "release.*helper"
        "update.*feed"
        "^Merge"
        "^Revert"
        "bump.*version"
    )
    
    # Build exclude pattern for grep
    local exclude_grep=""
    for pattern in "${exclude_patterns[@]}"; do
        exclude_grep="${exclude_grep}|${pattern}"
    done
    exclude_grep="${exclude_grep#|}"  # Remove leading |
    
    if [[ -z "$prev_tag" ]]; then
        info "No previous tag found. Generating changelog from all commits..."
        git log --pretty=format:"%s|%h" --reverse | \
            grep -ivE "$exclude_grep" | \
            sed 's/|/ (/; s/$/)/' | \
            sed 's/^/- /' | \
            head -50
    else
        info "Generating changelog from $prev_tag to $tag (filtering maintenance commits)..."
        # Count commits first
        local commit_count=$(git rev-list --count "${prev_tag}..HEAD" 2>/dev/null || echo "0")
        local filtered_count=$(git log --pretty=format:"%s" "${prev_tag}..HEAD" --reverse | grep -ivE "$exclude_grep" | wc -l | tr -d ' ')
        
        if [[ "$commit_count" -gt 50 ]]; then
            info "Found $commit_count total commits, $filtered_count app-related commits"
        fi
        
        # Get commits, filter out maintenance ones, and format
        git log --pretty=format:"%s|%h" "${prev_tag}..HEAD" --reverse | \
            grep -ivE "$exclude_grep" | \
            sed 's/|/ (/; s/$/)/' | \
            sed 's/^/- /' | \
            head -100
    fi
}

# Prepare changelog
if [[ "$AUTO_CHANGELOG" == true ]]; then
    info "Generating changelog..."
    CHANGELOG=$(generate_changelog "$TAG" 2>&1)
    changelog_exit=$?
    
    if [[ $changelog_exit -ne 0 ]] || [[ -z "$CHANGELOG" ]]; then
        warning "No commits found for changelog or error occurred. Using default message."
        CHANGELOG="Release version ${VERSION}"
    else
        # Add header
        prev_tag_for_link=$(git describe --tags --abbrev=0 2>/dev/null || echo "HEAD")
        CHANGELOG="## What's Changed

${CHANGELOG}

**Full Changelog**: https://github.com/${REPO}/compare/${prev_tag_for_link}...${TAG}"
        log "Changelog generated successfully"
    fi
elif [[ -z "${CHANGELOG:-}" ]]; then
    CHANGELOG="Release version ${VERSION}"
fi

# Create release using GitHub CLI
create_release_gh_cli() {
    local tag="$1"
    local notes="$2"
    local draft_flag=""
    local prerelease_flag=""
    
    [[ "$DRAFT" == true ]] && draft_flag="--draft"
    [[ "$PRERELEASE" == true ]] && prerelease_flag="--prerelease"
    
    info "Creating release using GitHub CLI..."
    
    # Create release (without --json for compatibility with older gh versions)
    local output
    output=$(gh release create "$tag" \
        --title "HiFidelity ${VERSION}" \
        --notes "$notes" \
        $draft_flag \
        $prerelease_flag \
        --repo "$REPO" 2>&1)
    local exit_code=$?
    
    if [[ $exit_code -ne 0 ]]; then
        # Check if release already exists - check for 422 (validation error) or "already exists"
        # Convert to lowercase and check for key phrases
        local check_output=$(echo "$output" | tr '[:upper:]' '[:lower:]')
        if echo "$check_output" | grep -q "422\|already exists\|tag_name"; then
            warning "Release $tag already exists. Will upload assets to existing release."
            log "Release exists at: https://github.com/${REPO}/releases/tag/${tag}"
            echo "exists"
            return 0
        else
            error "Failed to create release (exit code: $exit_code):"
            echo "$output" >&2
            return 1
        fi
    fi
    
    # Check if output contains error messages
    if echo "$output" | grep -qi "error\|failed"; then
        error "Release creation may have failed:"
        echo "$output" >&2
        return 1
    fi
    
    log "Release created: https://github.com/${REPO}/releases/tag/${tag}"
    # Return a dummy ID since we can't get it without --json
    echo "created"
}

# Create release using GitHub API
create_release_api() {
    local tag="$1"
    local notes="$2"
    local draft_flag="false"
    local prerelease_flag="false"
    
    [[ "$DRAFT" == true ]] && draft_flag="true"
    [[ "$PRERELEASE" == true ]] && prerelease_flag="true"
    
    info "Creating release using GitHub API..."
    
    # Escape notes for JSON
    local escaped_notes=$(echo "$notes" | jq -Rs .)
    
    # Create release
    local response=$(curl -s -w "\n%{http_code}" \
        -X POST \
        -H "Authorization: token ${GITHUB_TOKEN}" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/${REPO}/releases" \
        -d "{
            \"tag_name\": \"${tag}\",
            \"name\": \"HiFidelity ${VERSION}\",
            \"body\": ${escaped_notes},
            \"draft\": ${draft_flag},
            \"prerelease\": ${prerelease_flag}
        }")
    
    local http_code=$(echo "$response" | tail -n1)
    local body=$(echo "$response" | head -n-1)
    
    if [[ "$http_code" != "201" ]]; then
        error "Failed to create release (HTTP $http_code):"
        echo "$body" | jq -r '.message // .' 2>/dev/null || echo "$body"
        return 1
    fi
    
    local release_id=$(echo "$body" | jq -r '.id')
    local release_url=$(echo "$body" | jq -r '.html_url')
    
    log "Release created: $release_url"
    echo "$release_id"
}

# Upload asset using GitHub CLI
upload_asset_gh_cli() {
    local release_id="$1"  # Not used, but kept for compatibility
    local file_path="$2"
    
    info "Uploading $(basename "$file_path")..."
    
    # Use tag name instead of release ID (works with older gh versions)
    if gh release upload "$TAG" "$file_path" --repo "$REPO" --clobber 2>&1; then
        log "Uploaded $(basename "$file_path")"
        return 0
    else
        error "Failed to upload $(basename "$file_path")"
        return 1
    fi
}

# Upload asset using GitHub API
upload_asset_api() {
    local release_id="$1"
    local file_path="$2"
    local filename=$(basename "$file_path")
    local filesize=$(stat -f%z "$file_path" 2>/dev/null || stat -c%s "$file_path" 2>/dev/null)
    local content_type="application/octet-stream"
    
    # Determine content type
    if [[ "$filename" == *.dmg ]]; then
        content_type="application/x-apple-diskimage"
    elif [[ "$filename" == *.zip ]]; then
        content_type="application/zip"
    fi
    
    info "Uploading $filename ($(numfmt --to=iec-i --suffix=B "$filesize" 2>/dev/null || echo "${filesize} bytes"))..."
    
    local upload_url="https://uploads.github.com/repos/${REPO}/releases/${release_id}/assets?name=${filename}"
    
    local response=$(curl -s -w "\n%{http_code}" \
        -X POST \
        -H "Authorization: token ${GITHUB_TOKEN}" \
        -H "Accept: application/vnd.github.v3+json" \
        -H "Content-Type: ${content_type}" \
        --data-binary "@${file_path}" \
        "$upload_url")
    
    local http_code=$(echo "$response" | tail -n1)
    local body=$(echo "$response" | head -n-1)
    
    if [[ "$http_code" == "201" ]]; then
        log "Uploaded $filename"
        return 0
    else
        error "Failed to upload $filename (HTTP $http_code):"
        echo "$body" | jq -r '.message // .' 2>/dev/null || echo "$body"
        return 1
    fi
}

# Main execution
info "Creating GitHub release for version ${VERSION}..."

# Create release
if [[ "$USE_GH_CLI" == true ]]; then
    RELEASE_ID=$(create_release_gh_cli "$TAG" "$CHANGELOG")
    CREATE_EXIT=$?
    
    # If creation failed, check if it's because release already exists
    if [[ $CREATE_EXIT -ne 0 ]]; then
        # Try to check if release exists by attempting to view it
        if gh release view "$TAG" --repo "$REPO" &>/dev/null; then
            warning "Release $TAG already exists. Will upload assets to existing release."
            RELEASE_ID="exists"
        else
            error "Failed to create release and release does not exist"
            exit 1
        fi
    elif [[ "$RELEASE_ID" == "exists" ]]; then
        info "Release already exists, will upload assets to existing release"
    fi
else
    RELEASE_ID=$(create_release_api "$TAG" "$CHANGELOG")
    if [[ -z "$RELEASE_ID" ]]; then
        error "Failed to create release"
        exit 1
    fi
fi

# Upload assets
if [[ ${#ASSET_PATHS[@]} -gt 0 ]]; then
    info "Uploading ${#ASSET_PATHS[@]} asset(s)..."
    for dmg_path in "${ASSET_PATHS[@]}"; do
        if [[ ! -f "$dmg_path" ]]; then
            warning "File not found: $dmg_path (skipping)"
            continue
        fi
        
        if [[ "$USE_GH_CLI" == true ]]; then
            # For gh CLI, we can use the tag name directly
            upload_asset_gh_cli "$TAG" "$dmg_path" || true
        else
            upload_asset_api "$RELEASE_ID" "$dmg_path" || true
        fi
    done
fi

# Summary
echo ""
log "Release created successfully!"
echo ""
echo "  Tag: ${TAG}"
echo "  Version: ${VERSION}"
echo "  Repository: ${REPO}"
echo "  URL: https://github.com/${REPO}/releases/tag/${TAG}"
echo ""

if [[ ${#ASSET_PATHS[@]} -gt 0 ]]; then
    echo "  Assets uploaded:"
    for dmg_path in "${ASSET_PATHS[@]}"; do
        [[ -f "$dmg_path" ]] && echo "    - $(basename "$dmg_path")"
    done
    echo ""
fi

if [[ "$DRAFT" == true ]]; then
    warning "This is a draft release. Publish it on GitHub to make it public."
fi

