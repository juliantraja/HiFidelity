# Changelog

All notable changes to HiFidelity will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Planned

- Add your planned features here

---

## [1.0.11] - TBD

### Changed

- Removed rounded corners on the right side of artwork in mini player for
  better visual alignment with controls

### Added

- (Add new features here)

### Fixed

- (Add bug fixes here)

### Improved

- Balanced top and bottom margins for currently playing track in mini player
  queue for better visual centering
- Enhanced playing indicator animation in mini player queue with 7 animated
  bars and dynamic random movement for more visual feedback

---

## [1.0.10] - Released

See GitHub releases for full changelog.

---

## [1.0.9] - Released

See GitHub releases for full changelog.

---

## How to Use This Changelog

### When Making Changes

1. **Add entries immediately** when you make improvements:

   ```markdown
   ### Changed
   - Removed rounded corners on the right side of artwork in mini player
   ```

2. **Categorize your changes:**
   - **Added**: New features
   - **Changed**: Changes to existing functionality
   - **Deprecated**: Features that will be removed
   - **Removed**: Removed features
   - **Fixed**: Bug fixes
   - **Improved**: Performance improvements, UI refinements, code quality improvements

3. **Be descriptive but concise:**
   - ✅ Good: "Removed rounded corners on the right side of artwork in mini player"
   - ❌ Bad: "Fixed artwork"

### When Releasing

1. **Update the version date:**

   ```markdown
   ## [1.0.11] - 2024-01-15
   ```

2. **Copy to release notes:**
   - When running `gh-release.sh`, copy the relevant section to the
     `--changelog` parameter
   - Or use the changelog as a reference when writing release notes

3. **Move Unreleased items:**
   - Move any "Planned" items that were completed to the appropriate section
   - Clear the "Unreleased" section for the next version

### Example Workflow

```bash
# 1. Make a change (e.g., fix a bug)
# 2. Add to CHANGELOG.md under [Unreleased] > Fixed
# 3. Commit: git commit -m "Fix: Resolve audio playback issue"
# 4. When ready to release:
#    - Update version date in CHANGELOG.md
#    - Copy changelog section to gh-release.sh --changelog
#    - Create release
```
