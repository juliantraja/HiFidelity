# Release Guide

Quick reference for releasing new versions of HiFidelity.

## Quick Start

### Sparkle Update Release

1. **Build your app in Xcode** (or use build script)
2. **Copy app to Exports folder** (e.g., `Exports/HiFidelity v1.1.0/`)
3. **Run the Sparkle script:**
   ```bash
   ./Scripts/sparkle.sh "Exports/HiFidelity v1.1.0/HiFidelity.app"
   ```
4. **Commit and push** the changes (zip + appcast.xml)

That's it! Users will automatically see the update.

## Script Help

For detailed help on the sparkle script:
```bash
./Scripts/sparkle.sh --help
```

## Full Workflow Example

```bash
# 1. Build app in Xcode (Product → Archive → Export)
# 2. Copy exported app to Exports folder
cp -R "path/to/exported/HiFidelity.app" "Exports/HiFidelity v1.1.0/"

# 3. Run Sparkle script
./Scripts/sparkle.sh "Exports/HiFidelity v1.1.0/HiFidelity.app"

# 4. Review changes in git
git status

# 5. Commit and push
git add docs/HiFidelity-*.zip docs/appcast.xml
git commit -m "Release version 1.1.0"
git push
```

## Available Scripts

- **`./Scripts/sparkle.sh`** - Prepare Sparkle update (zip, sign, update appcast)
- **`./Scripts/build.sh`** - Build DMG installers (with `--bypass-notary` for testing)

## Notes

- The script automatically finds Sparkle tools (Homebrew or /tmp)
- Old appcast entries are automatically removed (only latest version kept)
- Use `--commit` flag to auto-commit changes: `./Scripts/sparkle.sh "..." --commit`

