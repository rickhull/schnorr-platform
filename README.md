# schnorr-platform

> **⚠️ IMPORTANT: This project uses the NEW Roc compiler (nightly) with different syntax than documented on roc-lang.org**
>
> The official Roc website currently documents the OLD compiler (different syntax, builtins, stdlib).
> This project uses the NEW compiler whose documentation is located in `docs/Builtin.roc` and `docs/all_syntax_test.roc`.
>
> **Key syntax differences from old documentation:**
> - No `if/then/else` → Use `match` with `Bool.true`/`Bool.false`
> - No `Num.to_str` → Use `Str.inspect(value)` for string conversion
> - `List U8` → Use `List(U8)` with parentheses (type application)
> - Function signatures use `=>` not `->` in module definitions
>
> Always verify syntax against `docs/Builtin.roc` - these were fetched from the new compiler source and are authoritative.

## Overview

This project provides a Roc platform that exposes cryptographic primitives via FFI bindings to `libsecp256k1`. It enables applications to perform:

- SHA-256 hashing
- BIP-340 Schnorr signing
- Signature verification
- Public key derivation

All cryptographic operations follow the [BIP-340](https://github.com/bitcoin/bips/blob/master/bip-0340.mendociki) standard using the secp256k1 curve.

## Features

- **Host Module** (`Host.pubkey!`, `Host.sign!`, `Host.verify!`)
  - Derive public key from 32-byte secret key
  - Sign 32-byte digest with Schnorr signature
  - Verify Schnorr signatures
  - Returns simple types (List U8, Bool, Str) - no status structs

- **Sha256 Module** (`Sha256.hex!`)
  - Hash byte arrays as hexadecimal strings
  - Returns Str

- **Stdio Modules** (`Stdout.line!`, `Stderr.line!`, `Stdin.line!`)
  - Input/output operations

## Quick Start

### Prerequisites

You'll need:
- Zig (0.15.2+)
- just
- Roc nightly compiler (installed via `just install-roc`)
- curl (for fetching docs)

On Arch Linux:
```bash
sudo pacman -S zig just curl
```

On Debian/ubuntu:
```bash
sudo apt install zig just curl
```

On macOS (with Homebrew):
```bash
brew install zig
```

### Installation

1. Clone the repository:
```bash
git clone https://github.com/your-repo/schnorr-platform.git
cd schnorr-platform
```

2. Run setup:
```bash
just setup
```

This will:
- Check for required tools
- Install latest Roc nightly compiler (if needed)
- Download libsecp256k1 dependency
- Build Zig platform for all targets
- Fetch Roc reference docs

## Usage

### Edit-Build-Test Cycle

```bash
# Build platform
just build

# Run all tests (Roc + Zig)
just test

# Build and run smoke test (quick validation)
just smoke-test
```

### Running Examples

```bash
# Run smoke test
just smoke-test

# Run a specific example
roc examples/pubkey.roc
```

## Examples

### Public Key Derivation

```roc
app [main!] { pf: platform "./platform/main.roc" }

import pf.Stdout
import pf.Host

main! = |_args| {
    # 32-byte secret key (all zeros for simplicity - use a real key in production!)
    secret_key = List.pad(32, 0)

    # Derive public key
    pubkey = Host.pubkey!(secret_key)

    # Check if we got a 32-byte public key
    match List.len(pubkey) {
        32 => Stdout.line!("✓ Got 32-byte public key")
        _ => Stdout.line!("✗ Failed to derive public key")
    }

    Ok({})
}
```

### Signing and Verification

```roc
app [main!] { pf: platform "./platform/main.roc" }

import pf.Stdout
import pf.Host

main! = |_args| {
    secret_key = List.pad(32, 0)
    msg = "Hello, Nostr!"

    # Hash the message
    digest = Sha256.hex!(msg)
    Stdout.line!("Digest: ${digest}")

    # Sign the digest
    sig = Host.sign!(secret_key, digest)

    # Verify signature
    pubkey = Host.pubkey!(secret_key)
    is_valid = Host.verify!(pubkey, digest, sig)

    match is_valid {
        Bool.true => Stdout.line!("✓ Signature is valid")
        Bool.false => Stdout.line!("✗ Signature is invalid")
    }

    Ok({})
}
```

## Testing

This project uses a hybrid testing approach:
- **Roc tests** (`expect`) - Validate API surface and usage patterns
- **Zig tests** - Validate platform internals and edge cases

See [TEST_PLAN.md](TEST_PLAN.md) for the full testing strategy.

### Running Tests

```bash
# Run all tests
just test

# Run specific module tests
just test-host
just test-sha256

# Run only Roc tests or only Zig tests
just test-roc
just test-zig
```

## Platform Development

If you want to add new modules or extend existing ones, see [docs/platform-dev-guide.md](docs/platform-dev-guide.md) for a complete guide on:

- Adding new Zig host functions
- Creating Roc module interfaces
- Registering tests in build.zig
- Managing dependencies via build.zig.zon

## Reference Documentation

### ⚠️ Roc Compiler Documentation

**WARNING:** The official Roc website (roc-lang.org) documents the OLD compiler with outdated syntax. This project uses the NEW compiler.

**Authoritative references for the NEW compiler (located in this repo):**
- [docs/Builtin.roc](docs/Builtin.roc) - Complete builtin functions reference (45KB)
- [docs/all_syntax_test.roc](docs/all_syntax_test.roc) - Comprehensive syntax examples (15KB)

These were fetched directly from the new Roc compiler source and are **authoritative** for the syntax used in this project.

### Platform Development

- [docs/TEST_PLAN.md](docs/TEST_PLAN.md) - Testing strategy and philosophy
- [docs/platform-dev-guide.md](docs/platform-dev-guide.md) - Complete platform development guide

### Claude Skills

The project includes two Claude Code skills for development assistance:
- `roc-language` - Roc syntax, patterns, and builtin functions
- `roc-platform` - Platform development, Zig hosts, build.zig

## Troubleshooting

### "DOES NOT EXIST" for builtin functions

The Roc compiler version must match the Roc dependency in `build.zig.zon`.

Check versions:
```bash
roc version
```

If they don't match, update `build.zig.zon` to match the commit hash from `roc version`.

### Platform build fails with "hash mismatch"

Zig will show the correct hash after a failed build. Update the `.hash` field in `build.zig.zon` with the new hash and rebuild.

### Function returns empty list/Bool.false

This usually indicates:
- Invalid input (e.g., wrong length secret key, bad signature)
- Missing context setup (e.g., secp256k1 context not initialized)

Check the function documentation in `examples/` for correct usage patterns.

### Wrong syntax errors

If you get syntax errors, check official docs (roc-lang.org) against this project's docs:

**Common issues from following old tutorials:**
- `if ... then ... else` → Not valid, use `match` with `Bool.true`/`Bool.false`
- `Num.to_str(x)` → Doesn't exist, use `Str.inspect(x)` or `.to_str()` method on numbers
- `List U8` → Wrong, use `List(U8)` (parentheses for type application)
- Function signatures using `->` → Use `=>` in module definitions

**Always verify against `docs/Builtin.roc`** - this is authoritative for the NEW compiler used in this project.

## Project Structure

```
├── build.zig.zon             # Zig package dependencies (roc, secp256k1)
├── build.zig                 # Build configuration
├── platform/
│   ├── main.roc             # Platform interface definition
│   ├── host.zig             # Zig host implementation
│   ├── *.roc                # Module interfaces (Stdout.roc, etc.)
│   └── targets/             # Compiled host libraries
├── test/
│   ├── *.roc                # Roc expect tests (API surface)
│   └── *.zig                # Zig unit tests (internals, edge cases)
├── examples/
│   └── *.roc                # Demo applications
├── docs/
│   ├── roc-tutorial.txt      # Condensed Roc tutorial
│   ├── stdlib.txt            # Condensed stdlib reference
│   ├── TEST_PLAN.md           # Testing strategy
│   └── platform-dev-guide.md   # Platform development guide
└── justfile                  # Build, test, and dev workflows
```

## License

MIT