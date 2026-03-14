# libghostty Migration Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate Pulse from a full Ghostty fork to consuming a prebuilt GhosttyKit.xcframework via CI artifacts.

**Architecture:** Two repos — `pulse-libghostty` builds the XCFramework from upstream Ghostty tags and publishes to GitHub Releases; `pulse` is the Swift-only app that fetches the prebuilt framework at build time.

**Tech Stack:** GitHub Actions, Zig (version per Ghostty's `build.zig.zon`, currently 0.15.2), xcodebuild, bash, Swift/Xcode

**Spec:** `docs/superpowers/specs/2026-03-14-libghostty-migration-design.md`

---

## Chunk 1: pulse-libghostty CI Repo

> **Parallelizable:** This chunk is independent of Chunk 2. Can be executed by a separate agent.

### Task 1: Create pulse-libghostty repo structure

**Files:**
- Create: `pulse-libghostty/README.md`
- Create: `pulse-libghostty/.github/workflows/build-xcframework.yml`
- Create: `pulse-libghostty/.gitignore`

- [ ] **Step 1: Initialize the repo**

The user has already created `This-Tech-Company/pulse`. A new repo `This-Tech-Company/pulse-libghostty` needs to be created on GitHub.

```bash
mkdir -p /tmp/pulse-libghostty
cd /tmp/pulse-libghostty
git init
```

- [ ] **Step 2: Create .gitignore**

```bash
cat > .gitignore << 'GITIGNORE'
# Build artifacts
ghostty/
*.tar.gz
SHA256SUMS
output/
GITIGNORE
```

- [ ] **Step 3: Create the GitHub Actions workflow**

Create `.github/workflows/build-xcframework.yml`:

```yaml
name: Build GhosttyKit XCFramework

on:
  workflow_dispatch:
    inputs:
      ghostty_tag:
        description: 'Ghostty release tag to build from (e.g., v1.3.2)'
        required: true
      ghostty_repo:
        description: 'Ghostty repo (override for custom forks)'
        required: false
        default: 'ghostty-org/ghostty'

jobs:
  build:
    runs-on: macos-14
    steps:
      - name: Checkout this repo
        uses: actions/checkout@v4

      - name: Clone Ghostty
        run: |
          git clone --depth 1 --branch "${{ github.event.inputs.ghostty_tag }}" \
            "https://github.com/${{ github.event.inputs.ghostty_repo }}.git" ghostty

      - name: Install Zig
        uses: mlugg/setup-zig@v2
        with:
          version: 0.15.2

      - name: Build GhosttyKit.xcframework (macOS arm64)
        run: |
          cd ghostty
          zig build \
            -Doptimize=ReleaseFast \
            -Demit-xcframework=true \
            -Dxcframework-target=native \
            --system pkg/apple-sdk
        timeout-minutes: 30

      - name: Collect artifacts
        run: |
          mkdir -p output
          # XCFramework
          cp -R ghostty/macos/GhosttyKit.xcframework output/
          # Shell integration resources
          mkdir -p output/resources
          cp -R ghostty/zig-out/share/terminfo output/resources/ 2>/dev/null || true
          cp -R ghostty/zig-out/share/ghostty output/resources/ 2>/dev/null || true
          cp -R ghostty/zig-out/share/vim output/resources/ 2>/dev/null || true
          cp -R ghostty/zig-out/share/nvim output/resources/ 2>/dev/null || true
          cp -R ghostty/zig-out/share/fish output/resources/ 2>/dev/null || true
          cp -R ghostty/zig-out/share/zsh output/resources/ 2>/dev/null || true
          cp -R ghostty/zig-out/share/bash-completion output/resources/ 2>/dev/null || true
          cp -R ghostty/zig-out/share/man output/resources/ 2>/dev/null || true
          cp -R ghostty/zig-out/share/bat output/resources/ 2>/dev/null || true
          cp -R ghostty/zig-out/share/locale output/resources/ 2>/dev/null || true
          # License
          cp ghostty/LICENSE output/GHOSTTY-LICENSE

      - name: Package tarball
        run: |
          cd output
          tar -czf ../libghostty-macos-arm64.tar.gz .
          cd ..
          shasum -a 256 libghostty-macos-arm64.tar.gz > SHA256SUMS

      - name: Create GitHub Release
        uses: softprops/action-gh-release@v2
        with:
          tag_name: ${{ github.event.inputs.ghostty_tag }}
          name: "libghostty ${{ github.event.inputs.ghostty_tag }}"
          body: |
            Built from ghostty ${{ github.event.inputs.ghostty_tag }}
            Repo: ${{ github.event.inputs.ghostty_repo }}
            Platform: macOS arm64
          files: |
            libghostty-macos-arm64.tar.gz
            SHA256SUMS
```

- [ ] **Step 4: Create README.md**

```markdown
# pulse-libghostty

Prebuilt GhosttyKit.xcframework for the Pulse terminal app.

## Usage

Trigger the "Build GhosttyKit XCFramework" workflow with a Ghostty release tag.
The workflow builds `GhosttyKit.xcframework` (macOS arm64) and publishes it as a GitHub Release.

## Consumed by

[This-Tech-Company/pulse](https://github.com/This-Tech-Company/pulse) via `scripts/fetch-libghostty.sh`.
```

- [ ] **Step 5: Commit and push**

```bash
git add -A
git commit -m "feat: add CI workflow to build GhosttyKit.xcframework from upstream Ghostty"
git remote add origin git@github.com:This-Tech-Company/pulse-libghostty.git
git branch -M main
git push -u origin main
```

### Task 2: Test the CI workflow

- [ ] **Step 1: Trigger the workflow**

```bash
gh workflow run build-xcframework.yml \
  --repo This-Tech-Company/pulse-libghostty \
  -f ghostty_tag=v1.3.2
```

Note: The exact tag depends on the current upstream Ghostty release. Check https://github.com/ghostty-org/ghostty/releases for the latest tag.

- [ ] **Step 2: Monitor the workflow run**

```bash
gh run list --repo This-Tech-Company/pulse-libghostty --limit 1
gh run watch --repo This-Tech-Company/pulse-libghostty
```

- [ ] **Step 3: Verify the release was created**

```bash
gh release view --repo This-Tech-Company/pulse-libghostty v1.3.2
```

Expected: Release exists with `libghostty-macos-arm64.tar.gz` and `SHA256SUMS` attached.

- [ ] **Step 4: Download and verify the tarball locally**

```bash
mkdir -p /tmp/verify-xcframework
cd /tmp/verify-xcframework
gh release download v1.3.2 --repo This-Tech-Company/pulse-libghostty
shasum -a 256 -c SHA256SUMS
tar -xzf libghostty-macos-arm64.tar.gz
ls GhosttyKit.xcframework/
ls resources/
cat GHOSTTY-LICENSE | head -5
```

Expected: XCFramework directory with `macos-arm64/` containing `libghostty.a` and `Headers/ghostty.h`, resources directory with terminfo/ghostty/vim/etc., and GHOSTTY-LICENSE present.

- [ ] **Step 5: If the workflow fails, debug and fix**

Common issues:
- Zig version mismatch: Check Ghostty's `build.zig.zon` for the exact minimum Zig version
- Build flags: The exact `zig build` flags may differ. Check Ghostty's build.zig for valid options. Key options to explore: `-Demit-xcframework`, `-Dxcframework-target`, `-Doptimize`
- Apple SDK: The `--system pkg/apple-sdk` flag may not be needed on macOS runners that already have Xcode

Fix, commit, push, and re-trigger until the workflow succeeds.

- [ ] **Step 6: Commit any fixes**

```bash
git add -A
git commit -m "fix: adjust build flags for CI environment"
git push
```

---

## Chunk 2: Pulse App Repo

> **Parallelizable:** This chunk is independent of Chunk 1 (except Task 5 which requires the CI release to exist). Tasks 3-4 can start immediately.

### Task 3: Create fetch-libghostty.sh and LIBGHOSTTY_VERSION

**Files:**
- Create: `scripts/fetch-libghostty.sh`
- Create: `LIBGHOSTTY_VERSION`

These files will be created in the `This-Tech-Company/pulse` repo. The user has already initialized this repo.

- [ ] **Step 1: Create LIBGHOSTTY_VERSION**

```bash
echo "v1.3.2" > LIBGHOSTTY_VERSION
```

Note: Use the same tag used in Task 2. This is the Ghostty version the fork is currently based on.

- [ ] **Step 2: Create scripts/fetch-libghostty.sh**

```bash
mkdir -p scripts
cat > scripts/fetch-libghostty.sh << 'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

REPO="This-Tech-Company/pulse-libghostty"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
VERSION_FILE="$ROOT_DIR/LIBGHOSTTY_VERSION"
CACHE_FILE="$ROOT_DIR/.libghostty-cached-version"
XCFRAMEWORK_DIR="$ROOT_DIR/macos/GhosttyKit.xcframework"
RESOURCES_DIR="$ROOT_DIR/resources"

if [ ! -f "$VERSION_FILE" ]; then
    echo "ERROR: LIBGHOSTTY_VERSION file not found"
    exit 1
fi

VERSION=$(cat "$VERSION_FILE" | tr -d '[:space:]')
echo "libghostty version: $VERSION"

# Check cache
if [ -f "$CACHE_FILE" ] && [ -d "$XCFRAMEWORK_DIR" ]; then
    CACHED=$(cat "$CACHE_FILE" | tr -d '[:space:]')
    if [ "$CACHED" = "$VERSION" ]; then
        echo "Already at $VERSION (cached). Skipping download."
        exit 0
    fi
fi

# Download
TARBALL="libghostty-macos-arm64.tar.gz"
DOWNLOAD_URL="https://github.com/$REPO/releases/download/$VERSION/$TARBALL"
CHECKSUM_URL="https://github.com/$REPO/releases/download/$VERSION/SHA256SUMS"
TMPDIR=$(mktemp -d)

echo "Downloading $TARBALL from $DOWNLOAD_URL..."
curl -fSL -o "$TMPDIR/$TARBALL" "$DOWNLOAD_URL"

echo "Downloading SHA256SUMS..."
curl -fSL -o "$TMPDIR/SHA256SUMS" "$CHECKSUM_URL"

echo "Verifying checksum..."
(cd "$TMPDIR" && shasum -a 256 -c SHA256SUMS)

# Extract
echo "Extracting..."
rm -rf "$XCFRAMEWORK_DIR"
mkdir -p "$XCFRAMEWORK_DIR"
rm -rf "$RESOURCES_DIR"
mkdir -p "$RESOURCES_DIR"

tar -xzf "$TMPDIR/$TARBALL" -C "$TMPDIR/extracted" 2>/dev/null || {
    mkdir -p "$TMPDIR/extracted"
    tar -xzf "$TMPDIR/$TARBALL" -C "$TMPDIR/extracted"
}

# Move XCFramework
cp -R "$TMPDIR/extracted/GhosttyKit.xcframework/"* "$XCFRAMEWORK_DIR/"

# Move resources
if [ -d "$TMPDIR/extracted/resources" ]; then
    cp -R "$TMPDIR/extracted/resources/"* "$RESOURCES_DIR/"
fi

# Move license
if [ -f "$TMPDIR/extracted/GHOSTTY-LICENSE" ]; then
    cp "$TMPDIR/extracted/GHOSTTY-LICENSE" "$RESOURCES_DIR/GHOSTTY-LICENSE"
fi

# Update cache
echo "$VERSION" > "$CACHE_FILE"

# Cleanup
rm -rf "$TMPDIR"

echo "Done. GhosttyKit.xcframework and resources are ready."
SCRIPT
chmod +x scripts/fetch-libghostty.sh
```

- [ ] **Step 3: Commit**

```bash
git add LIBGHOSTTY_VERSION scripts/fetch-libghostty.sh
git commit -m "feat: add fetch-libghostty.sh and version pinning"
```

### Task 4: Update .gitignore and clean up Zig artifacts

**Files:**
- Modify: `.gitignore`

- [ ] **Step 1: Add libghostty artifacts to .gitignore**

Append to `.gitignore`:

```
# libghostty (fetched at build time)
macos/GhosttyKit.xcframework/
.libghostty-cached-version
resources/
```

- [ ] **Step 2: Commit**

```bash
git add .gitignore
git commit -m "chore: gitignore fetched XCFramework and resources"
```

### Task 5: Update Xcode project resource references

**Files:**
- Modify: `macos/Ghostty.xcodeproj/project.pbxproj`

The current Xcode project references resources via symlinks to `../zig-out/share/*`. These must be updated to point to `../resources/` instead.

- [ ] **Step 1: Update resource symlink paths in project.pbxproj**

Find all references to `../zig-out/share/` and replace with `../resources/`:

```bash
cd macos
sed -i '' 's|../zig-out/share/|../resources/|g' Ghostty.xcodeproj/project.pbxproj
```

Verify the replacements:

```bash
grep "resources/" Ghostty.xcodeproj/project.pbxproj
```

Expected: Lines like `path = ../resources/terminfo`, `path = ../resources/ghostty`, etc.

- [ ] **Step 2: Verify no remaining zig-out references**

```bash
grep "zig-out" Ghostty.xcodeproj/project.pbxproj
```

Expected: No output (no remaining references).

- [ ] **Step 3: Verify Framework Search Paths include GhosttyKit.xcframework**

```bash
grep -i "FRAMEWORK_SEARCH_PATHS" Ghostty.xcodeproj/project.pbxproj
```

The XCFramework is already referenced directly in the Xcode project's Frameworks build phase (not via search paths). Verify it still points to `GhosttyKit.xcframework` at the project root level (`macos/GhosttyKit.xcframework`). If missing, add it via Xcode or by editing the pbxproj.

- [ ] **Step 4: Verify existing resource Copy Files build phases**

The Xcode project already has PBXFileReference entries for each resource directory (terminfo, ghostty, vim, etc.) and includes them in the Resources build phase. Since we updated the paths from `../zig-out/share/` to `../resources/`, these should continue to work. Verify:

```bash
grep -c "resources/" Ghostty.xcodeproj/project.pbxproj
```

Expected: ~10 matches (one per resource directory).

- [ ] **Step 5: Commit**

```bash
git add Ghostty.xcodeproj/project.pbxproj
git commit -m "fix: update resource paths from zig-out to resources directory"
```

### Task 6: Remove Zig source tree and build files

**Files:**
- Delete: `src/`, `build.zig`, `build.zig.zon*`, `test/`, `example/`, `include/`, `vendor/`, `nix/`, `snap/`, `apprt/`, `dist/`, `conformance/`, `website/`, `zig-out/`, `.zig-cache/`, `pkg/`, `images/`, `.github/`, `flatpak/`, `po/`, `Makefile`, `Doxyfile`, `DoxygenLayout.xml`, `flake.*`, `default.nix`, `shell.nix`, `valgrind.supp`, `typos.toml`, and Ghostty docs (`CODEOWNERS`, `CONTRIBUTING.md`, `HACKING.md`, `PACKAGING.md`, `AGENTS.md`, `AI_POLICY.md`, `README.md`)

- [ ] **Step 1: Verify what exists before deleting**

```bash
ls -d src build.zig build.zig.zon test example include vendor nix snap apprt dist conformance website zig-out .zig-cache 2>/dev/null
```

- [ ] **Step 2: Delete Zig source tree and build artifacts**

```bash
rm -rf src/ build.zig build.zig.zon build.zig.zon.json build.zig.zon.nix build.zig.zon.txt \
       test/ example/ include/ vendor/ pkg/ images/ .github/ \
       nix/ snap/ apprt/ dist/ conformance/ website/ zig-out/ .zig-cache/ \
       flatpak/ po/ Makefile Doxyfile DoxygenLayout.xml \
       flake.nix flake.lock default.nix shell.nix valgrind.supp typos.toml \
       CODEOWNERS CONTRIBUTING.md HACKING.md PACKAGING.md AGENTS.md AI_POLICY.md README.md
```

- [ ] **Step 3: Verify what remains**

```bash
ls -la
```

Expected to remain: `macos/`, `scripts/`, `LIBGHOSTTY_VERSION`, `.gitignore`, `.git/`, `.claude/`, `docs/`, `LICENSE`, and `CLAUDE.md` (if present). Also `resources/` and `macos/GhosttyKit.xcframework/` if previously fetched (both gitignored).

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "chore: remove Zig source tree, keep only Swift app layer

The Pulse app now consumes GhosttyKit.xcframework as a prebuilt
binary from This-Tech-Company/pulse-libghostty GitHub Releases."
```

---

## Chunk 3: Verify and Ship

> **Sequential:** Must run after Chunks 1 and 2 are both complete.

### Task 7: End-to-end verification

- [ ] **Step 1: Fetch the XCFramework**

```bash
./scripts/fetch-libghostty.sh
```

Expected: Downloads tarball, verifies checksum, extracts XCFramework and resources. Output ends with "Done."

- [ ] **Step 2: Verify XCFramework contents**

```bash
ls macos/GhosttyKit.xcframework/
file macos/GhosttyKit.xcframework/macos-arm64*/libghostty*.a
```

Expected: Static library present for macOS arm64.

- [ ] **Step 3: Verify resources**

```bash
ls resources/
```

Expected: `terminfo/`, `ghostty/`, `vim/`, `nvim/`, `fish/`, `zsh/`, `bash-completion/`, `man/`, `bat/`, `locale/`, `GHOSTTY-LICENSE`.

- [ ] **Step 4: Build with Xcode**

```bash
cd macos
xcodebuild -target Ghostty -configuration Debug -arch arm64 build
```

Expected: Build succeeds, producing `macos/build/Debug/Pulse.app`.

- [ ] **Step 5: Launch and test**

```bash
open macos/build/Debug/Pulse.app
```

Verify:
- App launches without crash
- Terminal sessions work (type commands, get output)
- Pulse sidebar appears (Cmd+\)
- Command palette works (Cmd+K)
- Session management works (create, switch, close sessions)
- Shell integration works (completions, terminfo)

- [ ] **Step 6: Commit any fixes needed**

If the build or app has issues, fix them and commit:

```bash
git add -A
git commit -m "fix: resolve build issues after migration"
```

### Task 8: Add Pulse app CI workflow

**Files:**
- Create: `.github/workflows/build-pulse.yml`

- [ ] **Step 1: Create the CI workflow**

```bash
mkdir -p .github/workflows
cat > .github/workflows/build-pulse.yml << 'WORKFLOW'
name: Build Pulse

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  build:
    runs-on: macos-14
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Fetch libghostty
        run: ./scripts/fetch-libghostty.sh

      - name: Build Pulse.app
        run: |
          cd macos
          xcodebuild -target Ghostty -configuration Debug -arch arm64 build
WORKFLOW
```

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/build-pulse.yml
git commit -m "ci: add GitHub Actions workflow to build Pulse.app"
```

- [ ] **Step 3: Push and verify CI**

```bash
git push
gh run list --limit 1
gh run watch
```

Expected: CI passes — fetches XCFramework, builds Pulse.app successfully.

### Task 9: Final push and cleanup

- [ ] **Step 1: Push all changes to pulse repo**

```bash
git push origin main
```

- [ ] **Step 2: Archive the old ghostty-fork repo**

Go to `github.com/This-Tech-Company/ghostty` → Settings → Archive this repository.

- [ ] **Step 3: Verify new developer onboarding**

From a clean directory:

```bash
git clone git@github.com:This-Tech-Company/pulse.git /tmp/pulse-test
cd /tmp/pulse-test
./scripts/fetch-libghostty.sh
cd macos
xcodebuild -target Ghostty -configuration Debug -arch arm64 build
open build/Debug/Pulse.app
```

Expected: Clone → fetch → build → run, with no Zig toolchain needed.
