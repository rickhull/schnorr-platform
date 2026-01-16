# Justfile for nostr-platform

# Configuration
install_root := env_var_or_default("HOME", "") + "/.local"
platform_dir := "platform"

# ===
# Leaf Tasks (basic operations that don't call other tasks)
# ===
#
# just nuke         - Clear all caches (zig-out, .zig-cache, ~/.cache/roc)
# just clean        - Remove platform build artifacts (zig-out, .zig-cache)
# just build        - Build Zig platform (all targets)
# just build-native - Build Zig platform (native target only, faster)
# just run          - Run hello_world.roc (or default .roc file)
# just check-tools  - Verify required tools (zig, curl, jq) are installed
# just check-nightly - Check if Roc nightly is up-to-date
# just install-roc  - Install latest Roc nightly compiler
# just fetch-docs   - Update Roc reference docs and Claude skills
# just list         - List all available recipes
#
# ===
# Workflow Tasks (compose multiple leaf tasks)
# ===
#
# just dev    - Build platform and run app (build → run)
# just fresh  - Clean build and run (clean → dev)
# just setup  - Full setup (install-roc → build)
#
# ===

# ============================================================================
# Workflows
# ============================================================================
#
# First-time setup:
#   just setup        # Check tools, install latest Roc nightly, build platform
#
# Edit-build-test cycle (after setup):
#   just build           # Rebuild Zig platform
#   just run             # roc main.roc
#   roc hello_world.roc  # Run Roc app
#   just dev             # Build and run
#   just fresh           # Clean, build, and run
#
# Reference docs:
#   just fetch-docs   # Update Roc reference docs (updates Claude skills)
#
# When things break:
#   just nuke         # Nuclear option: clear all caches
#
# Individual steps:
#   just check-tools  # Check for required tools
#   just install-roc  # Install latest Roc nightly
#   just build        # Build Zig platform
#   just clean        # Clean platform build artifacts
# ============================================================================

# Check for required tools
check-tools:
    #!/usr/bin/env bash
    echo "Checking required tools..."
    missing=""
    for cmd in zig curl jq; do
        if ! command -v $cmd &> /dev/null; then
            echo "  ✗ $cmd not found"
            missing="$missing $cmd"
        else
            echo "  ✓ $cmd"
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
        echo "✗ Roc not installed"
        exit 1
    fi

    current_version=$(roc version 2>&1 | head -1)
    # Extract commit hash from tag (format: nightly-2026-January-15-41b76c3)
    latest_commit=$(echo "$tag_name" | sed 's/.*-//')

    if echo "$current_version" | grep -q "$latest_commit"; then
        echo "✓ Roc $tag_name already installed"
        echo "  Current: $current_version"
        exit 0
    else
        echo "✗ Update available"
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
    if echo "$check_output" | grep -q "✓ Roc"; then
        echo "$check_output" | grep "✓ Roc"
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
    esac

    year=$(echo "$date_part" | cut -d'-' -f1)
    day=$(echo "$date_part" | cut -d'-' -f3)
    numeric_date="$year-$month_num-$day"

    filename="roc_nightly-linux_x86_64-$numeric_date-$commit.tar.gz"
    download_url="https://github.com/roc-lang/nightlies/releases/download/$tag_name/$filename"

    echo "Downloading $filename..."
    mkdir -p /tmp/roc-install
    curl -L "$download_url" -o "/tmp/roc-install/$filename"

    echo "Extracting to {{install_root}}/bin..."
    mkdir -p {{install_root}}/bin
    tar -xzf "/tmp/roc-install/$filename" -C /tmp/roc-install

    # Find the extracted directory (should be roc_nightly-linux_x86_64-DATE-HASH)
    extracted_dir=$(find /tmp/roc-install -maxdepth 1 -type d -name "roc_nightly-*" | head -1)

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
    rm -rf /tmp/roc-install

    echo "✓ Roc nightly installed to {{install_root}}/bin/roc"
    echo ""
    echo "Ensure {{install_root}}/bin is in your PATH:"
    echo "  export PATH=\"{{install_root}}/bin:\$PATH\""
    echo ""
    {{install_root}}/bin/roc version

# Build the Zig platform
# Note: Zig automatically downloads Roc source from build.zig.zon
# The roc dependency provides builtins that match your installed roc compiler
build:
    #!/usr/bin/env bash
    set -e
    echo "Building Zig platform..."
    zig build -Doptimize=ReleaseSafe
    echo "✓ Platform built"

# Build for native platform only (faster)
build-native:
    #!/usr/bin/env bash
    set -e
    echo "Building Zig platform (native only)..."
    zig build native -Doptimize=ReleaseSafe
    echo "✓ Platform built (native)"

# One-time full setup
setup: install-roc build

# Run hello_world example
run:
    roc hello_world.roc

# Build and run
dev: build run

# Clean platform build artifacts
clean:
    rm -rf zig-out .zig-cache

# Nuclear option: clean everything including Roc cache
nuke:
    rm -rf zig-out .zig-cache ~/.cache/roc

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
    echo "  ✓ docs/Builtin.roc"

    # Fetch all_syntax_test.roc
    curl -s https://raw.githubusercontent.com/roc-lang/roc/main/test/fx/all_syntax_test.roc \
        -o docs/all_syntax_test.roc
    echo "  ✓ docs/all_syntax_test.roc"

    # Update roc-language skill references
    echo "Updating roc-language skill..."
    mkdir -p ~/.claude/skills/roc-language/references
    cp docs/Builtin.roc ~/.claude/skills/roc-language/references/
    cp docs/all_syntax_test.roc ~/.claude/skills/roc-language/references/
    echo "  ✓ ~/.claude/skills/roc-language/references/"

    # Update roc-platform skill references
    echo "Updating roc-platform skill..."
    mkdir -p ~/.claude/skills/roc-platform/references
    cp docs/Builtin.roc ~/.claude/skills/roc-platform/references/
    echo "  ✓ ~/.claude/skills/roc-platform/references/"

    echo ""
    echo "✓ Reference docs updated successfully!"
    echo "  - docs/Builtin.roc ($(wc -l < docs/Builtin.roc) lines)"
    echo "  - docs/all_syntax_test.roc ($(wc -l < docs/all_syntax_test.roc) lines)"
    echo ""
    echo "Updated skills:"
    echo "  - roc-language (core syntax and builtins)"
    echo "  - roc-platform (platform development)"

# List available recipes
list:
    just --list
