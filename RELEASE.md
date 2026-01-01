# Release Guide

Quick reference for releasing new versions of HiFidelity.

## Quick Start

### Complete Release Workflow (Recommended)

The easiest way to create a full release:

```bash
# Build, create Sparkle update, and create GitHub Release
./Scripts/release.sh --version 1.1.0 --all
```

This will:

1. Build the app and create DMG
2. Create Sparkle update (zip + appcast)
3. Create GitHub Release with changelog and DMG asset

### Manual Steps

#### 1. Sparkle Update Release

1. **Build your app in Xcode** (or use build script)
2. **Copy app to Exports folder** (e.g., `Exports/HiFidelity v1.1.0/`)
3. **Run the Sparkle script:**

   ```bash
   ./Scripts/sparkle.sh "Exports/HiFidelity v1.1.0/HiFidelity.app"
   ```

4. **Commit and push** the changes (zip + appcast.xml)

#### 2. GitHub Release

Create a GitHub Release with changelog and assets:

```bash
# Create release with auto-generated changelog
./Scripts/create-release.sh --version 1.1.0 --auto-changelog

# Or with DMG asset
./Scripts/create-release.sh --version 1.1.0 --dmg "build/HiFidelity-1.1.0-Universal.dmg" --auto-changelog
```

## Script Help

For detailed help on any script:

```bash
./Scripts/sparkle.sh --help
./Scripts/create-release.sh --help
./Scripts/release.sh --help
```

## Full Workflow Examples

### Option 1: Automated (All-in-One)

```bash
# Build, Sparkle, and GitHub Release in one command
./Scripts/release.sh --version 1.1.0 --all
```

### Option 2: Step-by-Step

```bash
# 1. Build app
./Scripts/build.sh --version 1.1.0

# 2. Create Sparkle update (if you have app bundle)
./Scripts/sparkle.sh "Exports/HiFidelity v1.1.0/HiFidelity.app"

# 3. Create GitHub Release
./Scripts/create-release.sh --version 1.1.0 \
  --dmg "build/HiFidelity-1.1.0-Universal.dmg" \
  --auto-changelog

# 4. Commit and push
git add docs/HiFidelity-*.zip docs/appcast.xml
git commit -m "Release version 1.1.0"
git push
```

### Option 3: Using GitHub Actions

You can also trigger a release from GitHub:

1. Go to **Actions** → **Create Release** workflow
2. Click **Run workflow**
3. Enter version number (e.g., `1.1.0`)
4. Choose options (auto-changelog, draft, etc.)
5. Click **Run workflow**

Or push a tag:

```bash
git tag v1.1.0
git push origin v1.1.0
```

## Available Scripts

- **`./Scripts/release.sh`** - Complete release workflow (build + sparkle + github)
- **`./Scripts/build.sh`** - Build DMG installers
- **`./Scripts/sparkle.sh`** - Prepare Sparkle update (zip, sign, update appcast)
- **`./Scripts/create-release.sh`** - Create GitHub Release with changelog

## GitHub Release Features

The `create-release.sh` script can:

- ✅ **Auto-generate changelog** from git commits since last tag
- ✅ **Upload DMG files** as release assets
- ✅ **Create draft releases** for review before publishing
- ✅ **Mark as pre-release** for beta versions
- ✅ **Use GitHub CLI or API** (auto-detects what's available)

### Changelog Generation

The script automatically generates changelogs by:

1. Finding the previous git tag
2. Listing all commits between previous tag and current version
3. Formatting them as a markdown changelog

Example output:

```markdown
## What's Changed

- Add new feature X (#123)
- Fix bug Y (#124)
- Update dependencies (#125)

**Full Changelog**: https://github.com/owner/repo/compare/v1.0.9...v1.1.0
```

## GitHub Actions Workflow

A GitHub Actions workflow (`.github/workflows/release.yml`) is available that can:

- Create releases when you push a tag (e.g., `v1.1.0`)
- Create releases manually via workflow dispatch
- Auto-generate changelogs
- Upload DMG assets if available

## Notes

- **Sparkle script** automatically finds Sparkle tools (Homebrew or /tmp)
- **Old appcast entries** are automatically removed (only latest version kept)
- **GitHub token** can be set via `GITHUB_TOKEN` environment variable or `gh auth login`
- **Repository** is auto-detected from git remote, or specify with `--repo owner/repo`
- Use `--commit` flag with sparkle.sh to auto-commit changes
- Use `--draft` flag to create draft releases for review
