# Justfile for nostr-platform

# Configuration
install_root := env_var_or_default("HOME", "") + "/.local"
platform_dir := "platform"

# Unit Tasks (no dependencies, no invocations)
# ---
# just check-ascii      - Check all .roc files are 7-bit clean
# just check-nightly    - Check if Roc nightly is up-to-date
# just check-tools      - Verify required tools are installed
# just clean            - Remove platform build artifacts
# just built            - Record successful build markers
# just fetch-docs       - Update Roc reference docs and Claude skills
# just test-debug       - Run all tests including Zig
# just test-integration - Run integration tests (runtime with hosted functions)
# just test-unit        - Run module unit tests (roc test)

# Workflow Tasks (have dependencies or invocations)
# ---
# just build       - Quick native build for local development (hygiene + built)
# just build-all   - Build all target architectures (for releases; hygiene + built)
# just dev         - Build and run tests (build + test)
# just fresh       - Clean build and test (clean + dev)
# just hygiene     - Pre-build checks (clean/nuke when needed)
# just install-roc - Install latest Roc nightly (invokes check-nightly)
# just nuke        - Clear all caches (clean + ~/.cache/roc)
# just setup       - Full setup (install-roc + build-all)
# just test        - Run all Roc tests (test-unit + test-integration)
# just test-all    - Run all tests (test + test-debug)

# Check for required tools
check-tools:
    #!/usr/bin/env bash
    echo "Checking required tools..."
    missing=""
    for cmd in zig curl jq; do
        if ! command -v $cmd &> /dev/null; then
            echo "  [X] $cmd not found"
            missing="$missing $cmd"
        else
            echo "  [OK] $cmd"
        fi
    done
    if [ -n "$missing" ]; then
        echo ""
        echo "Missing: $missing"
        echo "  zig: https://ziglang.org/download/"
        echo "  curl, jq: Install via package manager (e.g., pacman -S curl jq)"
        exit 1
    fi
    echo ""
    echo "All tools satisfied!"

# Check if we have the latest Roc nightly (returns 0 if up-to-date, 1 if needs update)
check-nightly:
    #!/usr/bin/env bash
    set -e

    # Get latest release info from GitHub API
    release_info=$(curl -s https://api.github.com/repos/roc-lang/nightlies/releases/latest)
    tag_name=$(echo "$release_info" | jq -r '.tag_name')

    if [ -z "$tag_name" ] || [ "$tag_name" = "null" ]; then
        echo "Error: Could not fetch latest release info"
        exit 1
    fi

    echo "Latest nightly: $tag_name"

    # Check if roc is installed
    if ! command -v roc &> /dev/null; then
        echo "[X] Roc not installed"
        exit 1
    fi

    current_version=$(roc version 2>&1 | head -1)
    # Extract commit hash from tag (format: nightly-2026-January-15-41b76c3)
    latest_commit=$(echo "$tag_name" | sed 's/.*-//')

    if echo "$current_version" | grep -q "$latest_commit"; then
        echo "[OK] Roc $tag_name already installed"
        echo "  Current: $current_version"
        exit 0
    else
        echo "[X] Update available"
        echo "  Current: $current_version"
        echo "  Latest:  $tag_name"
        exit 1
    fi

# Fetch and install latest Roc nightly (skips if already up-to-date)
install-roc: check-tools
    #!/usr/bin/env bash
    set -e

    # Check if we already have the latest version (exit early if so)
    check_output=$(just check-nightly 2>&1 || true)
    if echo "$check_output" | grep -q "[OK] Roc"; then
        echo "$check_output" | grep "[OK] Roc"
        exit 0
    fi

    echo "Fetching latest Roc nightly release info..."

    # Get latest release info from GitHub API
    release_info=$(curl -s https://api.github.com/repos/roc-lang/nightlies/releases/latest)
    tag_name=$(echo "$release_info" | jq -r '.tag_name')

    if [ -z "$tag_name" ] || [ "$tag_name" = "null" ]; then
        echo "Error: Could not fetch latest release info"
        exit 1
    fi

    echo "Installing $tag_name..."

    # Extract date from tag (format: nightly-2026-January-15-41b76c3)
    date_part=$(echo "$tag_name" | sed 's/nightly-//' | cut -d'-' -f1-3)
    commit=$(echo "$tag_name" | sed 's/.*-//')

    # Detect platform/arch for filename (best-effort, fail fast if unknown)
    os_name=$(uname -s)
    arch_name=$(uname -m)
    case "$os_name" in
        Linux) platform="linux" ;;
        Darwin) platform="macos" ;;
        *) echo "Error: Unsupported OS '$os_name' for Roc nightly install"; exit 1 ;;
    esac
    case "$arch_name" in
        x86_64|amd64) arch="x86_64" ;;
        arm64|aarch64) arch="arm64" ;;
        *) echo "Error: Unsupported arch '$arch_name' for Roc nightly install"; exit 1 ;;
    esac

    # Construct filename (format: roc_nightly-linux_x86_64-2026-01-15-41b76c3.tar.gz)
    # Need to convert January -> 01, parse the date
    month=$(echo "$date_part" | cut -d'-' -f2)
    case "$month" in
        January) month_num="01" ;;
        February) month_num="02" ;;
        March) month_num="03" ;;
        April) month_num="04" ;;
        May) month_num="05" ;;
        June) month_num="06" ;;
        July) month_num="07" ;;
        August) month_num="08" ;;
        September) month_num="09" ;;
        October) month_num="10" ;;
        November) month_num="11" ;;
        December) month_num="12" ;;
        *) echo "Error: Unrecognized month '$month' in tag '$tag_name'"; exit 1 ;;
    esac

    year=$(echo "$date_part" | cut -d'-' -f1)
    day=$(echo "$date_part" | cut -d'-' -f3)
    numeric_date="$year-$month_num-$day"

    filename="roc_nightly-${platform}_${arch}-$numeric_date-$commit.tar.gz"
    download_url="https://github.com/roc-lang/nightlies/releases/download/$tag_name/$filename"

    echo "Downloading $filename..."
    tmpdir=$(mktemp -d -t roc-install 2>/dev/null || mktemp -d /tmp/roc-install.XXXXXX)
    trap 'rm -rf "$tmpdir"' EXIT
    curl -L "$download_url" -o "$tmpdir/$filename"

    echo "Extracting to {{install_root}}/bin..."
    mkdir -p {{install_root}}/bin
    tar -xzf "$tmpdir/$filename" -C "$tmpdir"

    # Find the extracted directory (should be roc_nightly-linux_x86_64-DATE-HASH)
    extracted_dir=$(find "$tmpdir" -maxdepth 1 -type d -name "roc_nightly-*" | head -1)

    if [ -z "$extracted_dir" ]; then
        echo "Error: Could not find extracted directory"
        exit 1
    fi

    # Copy binaries
    cp "$extracted_dir/roc" {{install_root}}/bin/
    if [ -f "$extracted_dir/roc_language_server" ]; then
        cp "$extracted_dir/roc_language_server" {{install_root}}/bin/
    fi

    # Cleanup
    echo "[OK] Roc nightly installed to {{install_root}}/bin/roc"
    echo ""
    echo "Ensure {{install_root}}/bin is in your PATH:"
    echo "  export PATH=\"{{install_root}}/bin:\$PATH\""
    echo ""
    {{install_root}}/bin/roc version


# Note: Zig automatically downloads Roc source (from build.zig.zon)

# Quick native build for local development
hygiene:
    #!/usr/bin/env bash
    set -e
    # Pre-checks: clean/nuke when build config or Roc version changed.
    if [ -f "zig-out/.last-build" ] && \
       { [ "build.zig" -nt "zig-out/.last-build" ] || [ "build.zig.zon" -nt "zig-out/.last-build" ]; }; then
        echo "Build configuration changed - cleaning..."
        just clean
    fi
    if command -v roc >/dev/null 2>&1; then
        current_version=$(roc version)
        cached_version=$(cat zig-out/.roc-version 2>/dev/null || echo "")
        if [ -n "$cached_version" ] && [ "$current_version" != "$cached_version" ]; then
            echo "Roc version changed - nuking cache..."
            just nuke
        fi
    fi

built:
    #!/usr/bin/env bash
    set -e
    # Record successful build
    mkdir -p zig-out
    if command -v roc >/dev/null 2>&1; then
        echo "$(roc version)" > zig-out/.roc-version
    fi
    touch zig-out/.last-build

build: hygiene
    #!/usr/bin/env bash
    set -e
    echo "Building Zig platform (native only)..."
    zig build native -Doptimize=ReleaseSafe
    just built
    echo "[OK] Platform built"

# Build all target architectures (for releases)
build-all: hygiene
    #!/usr/bin/env bash
    set -e
    echo "Building Zig platform (all targets)..."
    zig build -Doptimize=ReleaseSafe
    just built
    echo "[OK] Platform built (all targets)"

# One-time full setup
setup: install-roc build

# Run module unit tests (roc test)
test-unit:
    #!/usr/bin/env bash
    echo "=== Unit Tests ==="
    failed=""
    for module in platform/*.roc; do
        name=$(basename "$module")
        result=$(roc test "$module" 2>&1)
        exitcode=$?
        # Only show files with tests (skip "All (0) tests passed")
        if echo "$result" | grep -qv "All (0) tests passed"; then
            echo "  $name: $result"
        fi
        if [ $exitcode -ne 0 ]; then
            failed="$failed $name"
        fi
    done
    if [ -n "$failed" ]; then
        echo "X Failed unit tests:$failed"
        exit 1
    fi
    echo "[OK] All unit tests passed"

# Run integration tests (runtime with hosted functions)
test-integration:
    roc test/host.roc

# Run all Roc tests (unit + integration)
test: test-unit test-integration

# Run all tests
test-all: test test-debug

# Check all .roc files are 7-bit clean (ASCII only, UTF-8 compatible)
check-ascii:
    #!/usr/bin/env bash
    echo "=== Checking for 7-bit clean files ==="
    has_non_ascii() {
        local file="$1"
        if command -v rg >/dev/null 2>&1; then
            rg -q --pcre2 '[^\x00-\x7F]' "$file"
            return $?
        fi
        # BusyBox-compatible fallback: strip ASCII bytes, check if anything remains.
        if LC_ALL=C tr -d '\000-\177' < "$file" | head -c 1 | grep -q .; then
            return 0
        fi
        return 1
    }
    failed=""
    for f in platform/*.roc test/*.roc; do
        if has_non_ascii "$f"; then
            echo "  $f: contains non-ASCII bytes"
            failed="$failed $f"
        fi
    done
    if [ -n "$failed" ]; then
        echo "X Files with non-ASCII:$failed"
        exit 1
    fi
    echo "[OK] All .roc files are 7-bit clean"

# Run all tests including Zig (slow - includes FFI boundary tests)
test-debug:
    #!/usr/bin/env bash
    set -e
    echo "Running Zig tests..."

    zig build test
    echo "  [OK] Zig tests passed"
    echo ""

# Build and run tests
dev: build test

# Clean platform build artifacts
clean:
    rm -rf zig-out .zig-cache

# Nuclear option: clean everything including Roc cache
nuke: clean
    rm -rf ~/.cache/roc

# Clean, build, and run
fresh: clean dev

# Fetch latest Roc reference docs and update both docs/ and skill references
fetch-docs:
    #!/usr/bin/env bash
    set -e
    echo "Fetching Roc reference docs from GitHub..."
    mkdir -p docs

    # Fetch Builtin.roc
    curl -s https://raw.githubusercontent.com/roc-lang/roc/main/src/build/roc/Builtin.roc \
        -o docs/Builtin.roc
    echo "  [OK] docs/Builtin.roc"

    # Fetch all_syntax_test.roc
    curl -s https://raw.githubusercontent.com/roc-lang/roc/main/test/fx/all_syntax_test.roc \
        -o docs/all_syntax_test.roc
    echo "  [OK] docs/all_syntax_test.roc"

    # Update roc-language skill references
    echo "Updating roc-language skill..."
    mkdir -p ~/.claude/skills/roc-language/references
    cp docs/Builtin.roc         ~/.claude/skills/roc-language/references/
    cp docs/all_syntax_test.roc ~/.claude/skills/roc-language/references/
    cp docs/ROC_TUTORIAL.md     ~/.claude/skills/roc-language/references/
    cp docs/ROC_TUTORIAL_CONDENSED.md ~/.claude/skills/roc-language/references/
    cp docs/ROC_LANGREF_TUTORIAL.md   ~/.claude/skills/roc-language/references/
    echo "  [OK] ~/.claude/skills/roc-language/references/"

    # Update roc-platform skill references
    echo "Updating roc-platform skill..."
    mkdir -p ~/.claude/skills/roc-platform/references
    cp docs/Builtin.roc ~/.claude/skills/roc-platform/references/
    echo "  [OK] ~/.claude/skills/roc-platform/references/"

    echo ""
    echo "[OK] Reference docs updated successfully!"
    echo "  - docs/Builtin.roc ($(wc -l < docs/Builtin.roc) lines)"
    echo "  - docs/all_syntax_test.roc ($(wc -l < docs/all_syntax_test.roc) lines)"
    echo ""
    echo "Updated skills:"
    echo "  - roc-language (core syntax and builtins)"
    echo "  - roc-platform (platform development)"
