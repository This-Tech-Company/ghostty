# Pulse: Migration to Prebuilt libghostty

## Problem

Pulse is a fork of Ghostty that carries the entire Ghostty source tree (~95% of the repo) but only customizes 10 Swift files in `macos/Sources/Features/Pulse/`. All Pulse features (session management, sidebar, command palette, workspaces) live above the libghostty C API boundary. The full Zig compilation is unnecessary overhead for Pulse development.

## Decision

Migrate Pulse from a full Ghostty fork to a lightweight Swift app that consumes a prebuilt `GhosttyKit.xcframework` from a dedicated CI pipeline. This eliminates the Zig toolchain requirement, reduces build times, and simplifies developer onboarding.

## Constraints

- **Platform**: macOS arm64 only
- **Shell integration resources**: Keep bundled (terminfo, shell completions, vim files, man pages)
- **Upstream tracking**: Follow Ghostty release tags (no custom libghostty modifications by default)
- **Artifact hosting**: GitHub Releases on `This-Tech-Company/pulse-libghostty`
- **Licensing**: Ghostty is MIT-licensed; the LICENSE file must be included in the XCFramework tarball and bundled into `Pulse.app/Contents/Resources/`

## Architecture

### Two repos

**`pulse-libghostty`** — Build pipeline repo
- GitHub Actions workflow triggered manually with a Ghostty release tag
- Clones Ghostty at that tag, runs `zig build` to produce `GhosttyKit.xcframework` (macOS arm64) + shell integration resources
- Packages into a tarball, publishes as a GitHub Release asset tagged to match upstream (e.g., `v1.2.0`)

**`pulse`** (This-Tech-Company/pulse) — Application repo
- Contains only the Swift app layer and Xcode project
- Downloads the prebuilt XCFramework at build time via a fetch script
- No Zig source, no Zig toolchain needed

### Pulse repo structure

The entire `macos/Sources/` directory is carried over. All feature modules are required — they form the complete app UI layer that links against the XCFramework.

```
pulse/
├── LIBGHOSTTY_VERSION          # Pinned upstream tag (e.g., "v1.2.0")
├── scripts/
│   └── fetch-libghostty.sh     # Downloads XCFramework + resources from GitHub Releases
├── macos/
│   ├── Sources/
│   │   ├── App/                # AppDelegate, bridging header (ghostty-bridging-header.h)
│   │   ├── Ghostty/            # Swift wrappers around C API (Ghostty.App, Config, Input, etc.)
│   │   ├── Features/
│   │   │   ├── Pulse/          # Pulse-specific features (10 files)
│   │   │   ├── Terminal/       # Terminal controllers, window styles
│   │   │   ├── Command Palette/
│   │   │   ├── Splits/
│   │   │   ├── About/
│   │   │   ├── App Intents/
│   │   │   ├── AppleScript/
│   │   │   ├── ClipboardConfirmation/
│   │   │   ├── Custom App Icon/
│   │   │   ├── Global Keybinds/
│   │   │   ├── QuickTerminal/
│   │   │   ├── Secure Input/
│   │   │   ├── Services/
│   │   │   ├── Settings/
│   │   │   └── Update/
│   │   └── Helpers/            # Utility files
│   ├── Resources/              # App icons, assets
│   ├── GhosttyKit.xcframework/ # Downloaded by fetch script (gitignored)
│   └── Ghostty.xcodeproj/
└── resources/                  # Shell integration (terminfo, completions, etc.)
```

### Xcode project configuration

- The existing `ghostty-bridging-header.h` in `App/` imports `ghostty.h`. This header ships inside the XCFramework under `Headers/`. The Xcode project's "Framework Search Paths" must point to `macos/GhosttyKit.xcframework/` so the bridging header resolves correctly.
- Remove any Zig build phase scripts from the Xcode project. Replace with a "Run Script" build phase that runs `scripts/fetch-libghostty.sh` before "Compile Sources".
- Add a "Copy Files" build phase to bundle shell integration resources from `resources/` into `Pulse.app/Contents/Resources/`.

### Build flow

```
LIBGHOSTTY_VERSION
        │
        ▼
fetch-libghostty.sh ──→ Downloads tarball from pulse-libghostty GitHub Releases
        │
        ▼
Extracts GhosttyKit.xcframework/ + resources/
        │
        ▼
xcodebuild ──→ Compiles Swift app against XCFramework
        │
        ▼
Pulse.app
```

### fetch-libghostty.sh behavior

1. Reads version from `LIBGHOSTTY_VERSION`
2. Checks if `.libghostty-cached-version` exists and matches — if so, skip download (cache hit)
3. Downloads tarball from `https://github.com/This-Tech-Company/pulse-libghostty/releases/download/<tag>/libghostty-macos-arm64.tar.gz`
4. Downloads `SHA256SUMS` from the same release, verifies tarball integrity via `shasum -a 256 -c`
5. Extracts XCFramework into `macos/GhosttyKit.xcframework/`
6. Extracts shell integration resources into `resources/`
7. Extracts Ghostty LICENSE into `resources/GHOSTTY-LICENSE`
8. Writes the current version to `.libghostty-cached-version`

Both `.libghostty-cached-version` and `macos/GhosttyKit.xcframework/` are gitignored.

### pulse-libghostty CI workflow

```yaml
on:
  workflow_dispatch:
    inputs:
      ghostty_tag:
        description: 'Ghostty release tag to build from'
        required: true
      ghostty_repo:
        description: 'Ghostty repo (override for custom forks)'
        required: false
        default: 'ghostty-org/ghostty'
```

Steps:
1. Clone the specified repo at the specified tag
2. Install Zig toolchain (version matching Ghostty's `build.zig.zon`)
3. Run `zig build -Doptimize=ReleaseFast -Dtarget=aarch64-macos` to produce `GhosttyKit.xcframework` (exact flags TBD based on Ghostty's build system — will be determined during implementation)
4. Collect shell integration resources (terminfo, completions, vim, man pages) and Ghostty LICENSE
5. Package into `libghostty-macos-arm64.tar.gz`
6. Generate `SHA256SUMS` for the tarball
7. Create GitHub Release tagged to match the Ghostty version, attach tarball + checksums

Old releases are retained permanently so any `LIBGHOSTTY_VERSION` can be rolled back to.

## What gets deleted from the current fork

- `src/` — entire Zig source tree
- `build.zig`, `build.zig.zon` — Zig build system
- `test/`, `example/` — Zig tests and examples
- `include/` — C headers (ship inside XCFramework)
- `vendor/` — Zig dependencies
- `nix/`, `snap/`, `apprt/` — platform packaging
- `dist/`, `conformance/`, `website/` — distribution and docs tooling

## Update workflow

### New Ghostty release

1. Trigger `pulse-libghostty` CI with the new Ghostty tag
2. CI builds XCFramework, publishes GitHub Release
3. Update `LIBGHOSTTY_VERSION` in the Pulse repo
4. Run `fetch-libghostty.sh` (or let CI do it)
5. Build, test, ship

### New developer onboarding

1. Clone Pulse repo
2. Run `scripts/fetch-libghostty.sh`
3. Open Xcode, build, run

### Custom libghostty change needed

1. Fork Ghostty, make the change
2. Trigger `pulse-libghostty` CI with the fork repo via the `ghostty_repo` input and a branch/tag reference
3. Once upstream merges the fix, switch back to the default repo

## Migration execution order

1. **Set up `pulse-libghostty` repo** — Create CI workflow, run against current Ghostty version, verify published XCFramework
2. **Create the `pulse` repo** — Copy `macos/` directory and supporting files from current fork
3. **Add fetch script + version file** — Wire up XCFramework download
4. **Update Xcode project** — Remove Zig build step references, build against fetched XCFramework
5. **Verify the build** — `fetch-libghostty.sh` → `xcodebuild` → Pulse.app launches and works identically
6. **Clean up** — Archive the old `ghostty-fork` repo

## Pulse app CI

The `pulse` repo needs a GitHub Actions workflow for building the app:

1. Runs on `macos-14` (Apple Silicon runner)
2. Calls `scripts/fetch-libghostty.sh` to download the XCFramework
3. Runs `xcodebuild` to build `Pulse.app`
4. Xcode version and code signing configuration are environment-specific and will be determined during implementation
