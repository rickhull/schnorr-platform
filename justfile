# Justfile for schnorr-platform

# Unit Tasks (no dependencies, no invocations)
# ---
# built            - Record successful build markers
# check-ascii      - Check all .roc files are 7-bit clean
# clean            - Remove platform build artifacts
# test-integration - Run integration tests (hosted functions)
# test-unit        - Run module unit tests (roc test)
# test-zig         - Run zig tests, slow
# tools-build      - Verify zig is available

# Workflow Tasks (have dependencies or invocations)
# ---
# build         - Build native (hygiene built)
# build-all     - Build all targets (hygiene built)
# bundle        - Create distributable platform package (build-all)
# dev           - (build test)
# fresh         - (clean dev)
# hygiene       - Conditional (clean nuke)
# nuke          - (clean)
# test          - (test-unit test-integration)
# test-all      - (test test-zig)


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

# Clean platform build artifacts
clean:
    rm -rf zig-out .zig-cache

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

# Nuclear option: clean everything (no longer removes Roc cache)
nuke: clean
    rm -rf cache/roc-nightly

# Run all Roc tests (unit + integration)
test: test-unit test-integration

# Run all tests
test-all: test test-zig
