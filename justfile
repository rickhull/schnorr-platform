# Justfile for schnorr-platform

# Configuration
install_root := env_var_or_default("HOME", "") + "/.local"
curl_cmd := "curl -L -s -S" 

# Unit Tasks (no dependencies, no invocations)
# ---
# built            - Record successful build markers
# check-ascii      - Check all .roc files are 7-bit clean
# check-nightly    - Check if Roc nightly is up-to-date
# clean            - Remove platform build artifacts
# prune-roc        - Keep latest 3 Roc nightly cache entries
# test-integration - Run integration tests (hosted functions)
# test-unit        - Run module unit tests (roc test)
# test-zig         - Run zig tests, slow
# tools-build      - Verify zig is available
# tools-fetch      - Verify curl is available

# Workflow Tasks (have dependencies or invocations)
# ---
# build         - Build native (hygiene built)
# build-all     - Build all targets (hygiene built)
# bundle        - Create distributable platform package (build-all)
# dev           - (build test)
# fresh         - (clean dev)
# hygiene       - Conditional (clean nuke)
# fetch-roc     - Fetch roc-nightly to cache/ (tools-install)
# install-roc   - (check-nightly)
# nuke          - (clean)
# setup         - (install-roc build-all)
# test          - (test-unit test-integration)
# test-all      - (test test-zig)
# tools-install - Verify jq is available (tools-fetch)
# tools-all     - (tools-build tools-install)


#
# Unit Tasks
# ==========

# set timestamped build markers, checked by hygiene
built:
    #!/usr/bin/env bash
    set -e
    # Record successful build
    mkdir -p zig-out
    if command -v roc >/dev/null 2>&1; then
        echo "$(roc version)" > zig-out/.roc-version
    fi
    touch zig-out/.last-build

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

# Check if we have the latest Roc nightly
check-nightly: tools-install
    #!/usr/bin/env bash
    set -e

    # Get latest release info from GitHub API
    release_info=$({{curl_cmd}} https://api.github.com/repos/roc-lang/nightlies/releases/latest)
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

# Clean platform build artifacts
clean:
    rm -rf zig-out .zig-cache

# Prune Roc nightly cache to 3 most recent entries
prune-roc:
    #!/usr/bin/env bash
    set -e
    cache_dir="cache/roc-nightly"
    if [ ! -d "$cache_dir" ]; then
        exit 0
    fi
    stale_dirs=$(ls -dt "$cache_dir"/nightly-* 2>/dev/null | tail -n +4)
    if [ -z "$stale_dirs" ]; then
        exit 0
    fi
    echo "$stale_dirs" | while read -r dir; do
        rm -rf "$dir"
    done

# Run integration tests (runtime with hosted functions)
test-integration:
    roc test/host.roc

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

# Run all tests including Zig (slow - includes FFI boundary tests)
test-zig: tools-build
    #!/usr/bin/env bash
    set -e
    echo "Running Zig tests..."

    zig build test
    echo "  [OK] Zig tests passed"
    echo ""

# fail unless zig is available
tools-build:
    #!/usr/bin/env bash
    if ! command -v zig &> /dev/null; then
        echo "Missing: zig"
        echo "  zig: https://ziglang.org/download/"
        exit 1
    fi

# fail unless curl is available
tools-fetch:
    #!/usr/bin/env bash
    if ! command -v curl &> /dev/null; then
        echo "Missing: curl"
        echo "  curl: Install via package manager (e.g., pacman -S curl)"
        exit 1
    fi

# fail unless jq is available
tools-install: tools-fetch
    #!/usr/bin/env bash
    if ! command -v jq &> /dev/null; then
        echo "Missing: jq"
        echo "  jq: Install via package manager (e.g., pacman -S jq)"
        exit 1
    fi


#
# Workflow Tasks
# ==============

# zig build native
build: hygiene tools-build
    #!/usr/bin/env bash
    set -e
    echo "Building Zig platform (native only)..."
    zig build native -Doptimize=ReleaseSafe
    just built
    echo "[OK] Platform built"

# Build all target architectures (for releases)
build-all: hygiene tools-build
    #!/usr/bin/env bash
    set -e
    echo "Building Zig platform (all targets)..."
    zig build -Doptimize=ReleaseSafe
    just built
    echo "[OK] Platform built (all targets)"

# Bundle platform for distribution (builds all targets first)
bundle: build-all
    #!/usr/bin/env bash
    set -e
    echo "Bundling platform for distribution..."

    mkdir -p dist

    # Collect all .roc files from platform/
    roc_files=(platform/*.roc)

    # Collect all compiled libraries from targets/
    lib_files=()
    for lib in platform/targets/*/*.a platform/targets/*/*.o platform/targets/*/*.lib; do
        if [[ -f "$lib" ]]; then
            lib_files+=("$lib")
        fi
    done

    echo "Found ${#roc_files[@]} .roc files and ${#lib_files[@]} library files"

    # Create bundle
    roc bundle "${roc_files[@]}" "${lib_files[@]}" --output-dir dist

    echo "[OK] Platform bundle created in dist/"

# Build and run tests
dev: build test

# Clean, build, and run
fresh: clean dev

# auto-run clean or nuke based on "built" markers
hygiene:
    #!/usr/bin/env bash
    set -e
    # Pre-checks: nuke first on Roc version change, else clean on config change.
    if command -v roc >/dev/null 2>&1; then
        current_version=$(roc version)
        cached_version=$(cat zig-out/.roc-version 2>/dev/null || echo "")
        if [ -n "$cached_version" ] && [ "$current_version" != "$cached_version" ]; then
            echo "Roc version changed - nuking cache..."
            just nuke
            exit 0 # nothing more to do after a nuke
        fi
    fi
    if [ -f "zig-out/.last-build" ] && \
       { [ "build.zig" -nt "zig-out/.last-build" ] || [ "build.zig.zon" -nt "zig-out/.last-build" ]; }; then
        echo "Build configuration changed - cleaning..."
        just clean
    fi

# Fetch latest Roc nightly into cache/
fetch-roc: tools-install
    #!/usr/bin/env bash
    set -e
    cache_dir="cache/roc-nightly"
    mkdir -p "$cache_dir"

    # Get latest release info from GitHub API
    release_info=$({{curl_cmd}} https://api.github.com/repos/roc-lang/nightlies/releases/latest)
    tag_name=$(echo "$release_info" | jq -r '.tag_name')

    if [ -z "$tag_name" ] || [ "$tag_name" = "null" ]; then
        echo "Error: Could not fetch latest release info"
        exit 1
    fi

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

    # Extract date from tag (format: nightly-2026-January-15-41b76c3)
    date_part=$(echo "$tag_name" | sed 's/nightly-//' | cut -d'-' -f1-3)
    commit=$(echo "$tag_name" | sed 's/.*-//')

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
    tag_dir="$cache_dir/$tag_name"
    tarball="$tag_dir/$filename"

    if [ -f "$tarball" ]; then
        echo "[OK] Cached: $tarball"
    else
        echo "Downloading $filename..."
        mkdir -p "$tag_dir"
        {{curl_cmd}} "$download_url" -o "$tarball"
    fi

    echo "$tag_name" > "$cache_dir/LATEST"
    echo "[OK] Cached nightly: $tag_name"

# Fetch and install latest Roc nightly (skips if already up-to-date)
install-roc: tools-install fetch-roc
    #!/usr/bin/env bash
    set -e

    # Check if we already have the latest version (exit early if so)
    check_output=$(just check-nightly 2>&1 || true)
    if echo "$check_output" | grep -q "[OK] Roc"; then
        echo "$check_output" | grep "[OK] Roc"
        exit 0
    fi

    cache_dir="cache/roc-nightly"
    tag_name="${1:-}"
    if [ -z "$tag_name" ]; then
        if [ ! -f "$cache_dir/LATEST" ]; then
            just fetch-roc
        fi
        tag_name=$(cat "$cache_dir/LATEST")
    fi

    tag_dir="$cache_dir/$tag_name"
    tarball=$(ls "$tag_dir"/*.tar.gz 2>/dev/null | head -1)
    if [ -z "$tarball" ]; then
        echo "Error: No cached nightly for tag '$tag_name'"
        echo "  Run: just fetch-roc"
        exit 1
    fi

    echo "Installing $tag_name..."
    tmpdir=$(mktemp -d -t roc-install 2>/dev/null || mktemp -d /tmp/roc-install.XXXXXX)
    trap 'rm -rf "$tmpdir"' EXIT

    echo "Extracting to {{install_root}}/bin..."
    mkdir -p {{install_root}}/bin
    tar -xzf "$tarball" -C "$tmpdir"

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
    just prune-roc

# Nuclear option: clean everything including Roc cache
nuke: clean
    rm -rf ~/.cache/roc

# One-time full setup
setup: install-roc build

# Run all Roc tests (unit + integration)
test: test-unit test-integration

# Run all tests
test-all: test test-zig

# Fail unless all tools are available
tools-all: tools-build tools-install
