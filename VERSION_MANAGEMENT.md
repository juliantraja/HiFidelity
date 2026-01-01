# Version & Build Number Management

## Overview

Version and build numbers are managed in multiple places. This document explains where they are stored, how they're used, and how to update them.

## Version Number Locations

### 1. **Xcode Project** (Primary Source of Truth) ⭐
**File:** `HiFidelity.xcodeproj/project.pbxproj`

- `MARKETING_VERSION` = Version number (e.g., `1.0.9`)
- `CURRENT_PROJECT_VERSION` = Build number (e.g., `109`)

**Location in file:**
- Lines 424, 481: `MARKETING_VERSION = 1.0.9;`
- Lines 397, 453: `CURRENT_PROJECT_VERSION = 109;`

**How it's used:**
- Xcode reads these values when building
- `build.sh` script automatically reads from here if no version is specified
- These values are injected into `Info.plist` at build time

### 2. **Info.plist** (Dynamic - Auto-populated)
**File:** `HiFidelity/Info.plist`

```xml
<key>CFBundleShortVersionString</key>
<string>$(MARKETING_VERSION)</string>
<key>CFBundleVersion</key>
<string>$(CURRENT_PROJECT_VERSION)</string>
```

**How it's used:**
- Uses variables that reference Xcode project settings
- Populated automatically at build time
- **You don't need to manually edit this file**

### 3. **Constants.swift** (Fallback Values)
**File:** `HiFidelity/AppData/Constants.swift`

```swift
static let appVersion = "1.0.9"  // Fallback - should match Xcode MARKETING_VERSION
static let appBuild = "109"      // Fallback - should match Xcode CURRENT_PROJECT_VERSION
```

**How it's used:**
- Only used if `Bundle.main.infoDictionary` doesn't have version info (rare edge case)
- Should be kept in sync with Xcode project values
- Used by `AppInfo.swift` as a fallback

### 4. **AppInfo.swift** (Runtime Reading)
**File:** `HiFidelity/AppData/AppInfo.swift`

```swift
static var version: String {
    Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? About.appVersion
}

static var build: String {
    Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? About.appBuild
}
```

**How it's used:**
- Reads from Bundle (which comes from Info.plist) at runtime
- Falls back to `Constants.swift` if Bundle values are missing
- **You don't need to edit this file**

## Build Number Calculation

The build number follows this formula:
```
Build = (Major × 100) + (Minor × 10) + Patch
```

**Examples:**
- `1.0.9` → `109` (1×100 + 0×10 + 9)
- `1.1.0` → `110` (1×100 + 1×10 + 0)
- `1.2.5` → `125` (1×100 + 2×10 + 5)
- `2.0.0` → `200` (2×100 + 0×10 + 0)

## How to Update Version Numbers

### ✅ Recommended: Update in Xcode (Automatic Sync)

1. Open `HiFidelity.xcodeproj` in Xcode
2. Select the project in the navigator
3. Select the target "HiFidelity"
4. Go to "General" tab
5. Update:
   - **Version**: `1.0.9` → `1.0.10`
   - **Build**: `109` → `110`

**That's it!** `Constants.swift` will be automatically synced when you:
- Run `./Scripts/build.sh` (syncs from Xcode project)
- Run `./Scripts/sparkle-update.sh` (syncs from built app bundle)

### Alternative: Manual Edit of project.pbxproj

**⚠️ Not recommended** - Easy to make mistakes

1. Edit `HiFidelity.xcodeproj/project.pbxproj`
2. Find and replace:
   - `MARKETING_VERSION = 1.0.9;` → `MARKETING_VERSION = 1.0.10;`
   - `CURRENT_PROJECT_VERSION = 109;` → `CURRENT_PROJECT_VERSION = 110;`
3. Update `Constants.swift` to match

## Automatic Version Sync

Both `build.sh` and `sparkle-update.sh` automatically sync `Constants.swift` with the version numbers:

### build.sh Behavior

1. **If you pass `--version` and `--build` flags:**
   ```bash
   ./Scripts/build.sh --version 1.0.10 --build 110
   ```
   - Uses your specified values
   - Overrides Xcode project settings during build
   - **Automatically syncs `Constants.swift`** before building

2. **If you don't specify version:**
   - Reads from Xcode project (`MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`)
   - **Automatically syncs `Constants.swift`** to match
   - If not found, tries to get from git tags
   - If still not found, uses `dev-<commit-sha>`

3. **Build number calculation:**
   - If you specify `--build`, uses that
   - Otherwise, reads from Xcode project
   - If not found, calculates from version using the formula above

### sparkle-update.sh Behavior

- Reads version/build from the built app bundle's `Info.plist`
- **Automatically syncs `Constants.swift`** to match the app bundle version
- Ensures `Constants.swift` always matches what was actually built

## Release Workflow

When creating a new release:

1. **Update version in Xcode:**
   - Open Xcode → General tab
   - Update Version: `1.0.9` → `1.0.10`
   - Update Build: `109` → `110`

2. **Build the app:**
   ```bash
   ./Scripts/build.sh
   ```
   - Automatically reads version from Xcode project
   - **Automatically syncs `Constants.swift`** before building

3. **Create Sparkle update:**
   ```bash
   ./Scripts/sparkle-update.sh "Exports/HiFidelity v1.0.10/HiFidelity.app"
   ```
   - **Automatically syncs `Constants.swift`** to match built app

4. **Commit the changes:**
   ```bash
   git add HiFidelity.xcodeproj/project.pbxproj HiFidelity/AppData/Constants.swift docs/appcast.xml docs/HiFidelity-*.zip
   git commit -m "Bump version to 1.0.10 (build 110)"
   ```

5. **Create GitHub release:**
   ```bash
   ./Scripts/gh-release.sh --version 1.0.10
   ```

## Current Version

- **Version:** `1.0.9`
- **Build:** `109`

## Troubleshooting

### Version mismatch between Xcode and Constants.swift

If you see different versions in the app vs. what you expect:

1. Check Xcode project: `grep MARKETING_VERSION HiFidelity.xcodeproj/project.pbxproj`
2. Check Constants.swift: `grep appVersion HiFidelity/AppData/Constants.swift`
3. **Just run `build.sh` or `sparkle-update.sh`** - they will automatically sync `Constants.swift`

### Build number doesn't match version

The build number should follow the formula: `(Major × 100) + (Minor × 10) + Patch`

If `1.0.9` shows build `109`, that's correct. If it shows something else, update it manually or use the script.

## Summary

✅ **What to update:** Xcode project settings (Version and Build in General tab)  
✅ **How to update:** Update in Xcode → Constants.swift syncs automatically  
✅ **When to update:** Before each release  
✅ **Automatic sync:** `build.sh` and `sparkle-update.sh` keep `Constants.swift` in sync  
❌ **Don't edit:** Info.plist (it's auto-populated)  
❌ **Don't edit:** AppInfo.swift (it reads from Bundle)  
❌ **Don't manually edit:** Constants.swift (it's auto-synced)

