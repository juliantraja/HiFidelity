# Complete Release Workflow Guide

A step-by-step guide for releasing new versions of HiFidelity, from building in Xcode to publishing on GitHub.

---

## 📋 Prerequisites

Before you start, make sure you have:

- ✅ Xcode installed and configured
- ✅ GitHub CLI installed (`brew install gh`)
- ✅ GitHub CLI authenticated (`gh auth login`)
- ✅ Sparkle tools installed (for auto-updates)

---

## 🚀 Complete Release Process

### Step 1: Update Version in Xcode

1. Open `HiFidelity.xcodeproj` in Xcode
2. Select the **HiFidelity** project in the navigator
3. Select the **HiFidelity** target
4. Go to the **General** tab
5. Update:
   - **Marketing Version**: `1.4.4` (or your new version)
   - **Current Project Version**: `144` (or your build number)
6. **Save** the project

### Step 2: Build and Archive in Xcode

1. In Xcode, select **Product → Archive**
2. Wait for the archive to complete (this may take a few minutes)
3. The **Organizer** window will open automatically
4. Select your archive and click **Distribute App**
5. Choose **Copy App** (for local distribution)
6. Click **Next** and select your signing options
7. Click **Export**
8. Choose a location to save (e.g., `Desktop/HiFidelity-1.4.4`)
9. Click **Export**

### Step 3: Prepare App Bundle

1. Navigate to your exported app location
2. Copy the `HiFidelity.app` bundle to the Exports folder:

   ```bash
   cp -R "Desktop/HiFidelity-1.4.4/HiFidelity.app" "Exports/HiFidelity v1.4.4/"
   ```

   Or create the folder and copy manually:

   ```bash
   mkdir -p "Exports/HiFidelity v1.4.4"
   cp -R "path/to/exported/HiFidelity.app" "Exports/HiFidelity v1.4.4/"
   ```

### Step 4: Create Sparkle Update (Auto-Update System)

This creates the zip file and updates the appcast.xml for in-app updates.

```bash
./Scripts/sparkle-update.sh "Exports/HiFidelity v1.4.4/HiFidelity.app"
```

**What this does:**

- ✅ Creates a signed zip file: `releases/HiFidelity-1.4.4-144.zip`
- ✅ Copies zip to `docs/` folder
- ✅ Updates `docs/appcast.xml` with the new version
- ✅ Signs the update with Sparkle

**Output:**

- `releases/HiFidelity-1.4.4-144.zip`
- `docs/HiFidelity-1.4.4-144.zip`
- `docs/appcast.xml` (updated)

### Step 5: Create GitHub Release

This creates a release on GitHub with your zip file attached.

```bash
./Scripts/gh-release.sh --version 1.0.10 \
  --asset "releases/HiFidelity-1.0.10-1010.zip" \
  --changelog "Your release notes here

## What's New
- Feature 1
- Feature 2
- Bug fix 1

## Improvements
- Improvement 1
- Improvement 2"
```

**What this does:**

- ✅ Creates a GitHub release with tag `v1.4.4`
- ✅ Uploads the zip file as a release asset
- ✅ Sets your custom release notes

**Release Notes Tips:**

- Write user-friendly descriptions
- Group changes by category (Features, Fixes, Improvements)
- Use bullet points for readability
- Include links to issues/PRs if relevant

### Step 6: Commit and Push Changes

Only commit the files that should be in the repository:

```bash
# Review what changed
git status

# Add only the necessary files
git add docs/appcast.xml
git add docs/HiFidelity-1.0.10-1010.zip  # Only if you want to host it on GitHub Pages
git add HiFidelity.xcodeproj/project.pbxproj  # Version changes

# Commit
git commit -m "Release version 1.0.10"

# Push
git push
```

**⚠️ Important:** Don't commit:

- `releases/*.zip` (already in .gitignore)
- `Exports/` folder (already in .gitignore)
- Build artifacts
- Temporary files

---

## 📝 Quick Reference Commands

### Full Release Workflow

```bash
# 1. After exporting from Xcode, copy to Exports folder
cp -R "path/to/HiFidelity.app" "Exports/HiFidelity v1.0.10/"

# 2. Create Sparkle update
./Scripts/sparkle-update.sh "Exports/HiFidelity v1.0.10/HiFidelity.app"

# 3. Create GitHub Release (with your custom changelog)
./Scripts/gh-release.sh --version 1.0.10 \
  --asset "releases/HiFidelity-1.0.10-1010.zip" \
  --changelog "Your release notes here"

# 4. Commit and push
git add docs/appcast.xml docs/HiFidelity-1.0.10-1010.zip HiFidelity.xcodeproj/project.pbxproj
git commit -m "Release version 1.0.10"
git push
```

### Just Sparkle Update (No GitHub Release)

```bash
./Scripts/sparkle-update.sh "Exports/HiFidelity v1.4.4/HiFidelity.app"
git add docs/appcast.xml docs/HiFidelity-1.4.4-144.zip
git commit -m "Publish 1.4.4 Sparkle update"
git push
```

### Just GitHub Release (No Sparkle)

```bash
./Scripts/gh-release.sh --version 1.4.4 \
  --asset "releases/HiFidelity-1.4.4-144.zip" \
  --changelog "Your release notes"
```

---

## 📁 File Organization

### Files You Should Commit ✅

- `docs/appcast.xml` - Sparkle update feed
- `docs/HiFidelity-*.zip` - Sparkle update files (if hosting on GitHub Pages)
- `HiFidelity.xcodeproj/project.pbxproj` - Version number changes
- Source code files
- Documentation files

### Files You Should NOT Commit ❌

- `releases/*.zip` - Local Sparkle artifacts (already in .gitignore)
- `Exports/` - Exported app bundles (already in .gitignore)
- `build/` - Build artifacts (already in .gitignore)
- `*.xcarchive` - Xcode archives (already in .gitignore)
- `DerivedData/` - Xcode derived data (already in .gitignore)

---

## 🔍 Troubleshooting

### "App bundle not found" Error

**Problem:** Sparkle script can't find your app bundle.

**Solution:**

- Make sure the path is correct
- Use absolute path: `./Scripts/sparkle-update.sh "/full/path/to/HiFidelity.app"`
- Check that the app bundle exists: `ls -la "Exports/HiFidelity v1.4.4/HiFidelity.app"`

### "Release already exists" Error

**Problem:** GitHub release with that tag already exists.

**Solution:**

- Delete the existing release: `gh release delete v1.4.4 --repo juliantraja/HiFidelity --yes`
- Or update it: `gh release edit v1.4.4 --notes "New notes" --repo juliantraja/HiFidelity`

### "GitHub CLI not authenticated" Error

**Problem:** GitHub CLI needs to be logged in.

**Solution:**

```bash
gh auth login
# Follow the prompts to authenticate
```

### Sparkle Tools Not Found

**Problem:** `sign_update` command not found.

**Solution:**

```bash
# Install Sparkle via Homebrew
brew install --cask sparkle

# Or download manually from: https://sparkle-project.org/
```

### Version Mismatch

**Problem:** Version in Xcode doesn't match what you're releasing.

**Solution:**

- Double-check Marketing Version and Build Number in Xcode
- Make sure they match your release command: `--version 1.4.4` and build `144`

---

## 📚 Additional Resources

- **Sparkle Documentation**: sparkle-project.org/documentation/
- **GitHub Releases API**: docs.github.com/en/rest/releases
- **Xcode Archive Guide**: developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases

---

## 💡 Tips

1. **Test Before Releasing**: Always test your exported app before publishing
2. **Version Numbers**: Use semantic versioning (MAJOR.MINOR.PATCH)
3. **Build Numbers**: Increment build number for each release (even if version stays the same)
4. **Release Notes**: Write clear, user-friendly release notes
5. **Backup**: Keep exported apps in `Exports/` folder as backups
6. **Git Tags**: The script automatically creates git tags (e.g., `v1.4.4`)

---

## 🎯 Example: Complete Release for v1.4.4

```bash
# 1. Update version in Xcode (1.4.4, build 144)
# 2. Archive in Xcode (Product → Archive)
# 3. Export app to Desktop

# 4. Copy to Exports
mkdir -p "Exports/HiFidelity v1.4.4"
cp -R "Desktop/HiFidelity-1.4.4/HiFidelity.app" "Exports/HiFidelity v1.4.4/"

# 5. Create Sparkle update
./Scripts/sparkle-update.sh "Exports/HiFidelity v1.4.4/HiFidelity.app"

# 6. Create GitHub Release
./Scripts/gh-release.sh --version 1.4.4 \
  --asset "releases/HiFidelity-1.4.4-144.zip" \
  --changelog "## What's New in 1.4.4

### Features
- Added new feature X
- Improved feature Y

### Fixes
- Fixed bug Z
- Resolved issue with audio playback

### Improvements
- Better performance
- UI refinements"

# 7. Commit and push
git add docs/appcast.xml docs/HiFidelity-1.4.4-144.zip HiFidelity.xcodeproj/project.pbxproj
git commit -m "Release version 1.4.4"
git push
```

That's it! Your release is now live.
