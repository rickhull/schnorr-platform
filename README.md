# schnorr-platform

A Roc platform providing the cryptographic primitives needed for [Nostr](https://github.com/nostr-protocol/nostr) applications.

Built with libsecp256k1 FFI bindings for BIP-340 Schnorr signatures.

## What It Provides

```roc
# Cryptographic operations for Nostr
Host.pubkey!(secret_key)       # Derive npub from secret key
Host.sign!(secret_key, msg)    # Schnorr signature
Host.verify!(pubkey, msg, sig) # Verify signature
Host.sha256!(data)             # SHA-256 hash
```

Perfect for building Nostr clients, relays, or bots in Roc.

## Quick Start

```bash
# Build platform (requires Roc and Zig)
just build

# Run example
roc examples/pubkey.roc
```

**Prerequisites:** Roc nightly (installed via `roc-init`), Zig (0.15.2+)

## Commands

| Task | Description | Depends | Invokes |
|------|-------------|---------|---------|
| `build` | Build native platform | `hygiene` | - |
| `build-all` | Build all target architectures | `hygiene` | - |
| `bundle` | Create distributable platform package | `build-all` | - |
| `clean` | Remove platform build artifacts | - | - |
| `dev` | Build and run tests | - | `build`, `test` |
| `fresh` | Clean, build, and run | - | `clean`, `dev` |
| `nuke` | Clean everything including platform cache | - | `clean` |
| `test` | Run Roc tests (unit + integration) | - | `test-unit`, `test-integration` |
| `test-all` | Run all tests including Zig | `test` | `test-zig` |
| `test-integration` | Run integration tests (runtime) | - | - |
| `test-unit` | Run module unit tests (roc test) | - | - |
| `test-integration` | Run integration tests (runtime) | - | - |
| `test-zig` | Run Zig tests (FFI boundaries) | `tools-build` | - |

**Workflow:** Use `roc-init` to set up Roc, then clone schnorr-platform and run `just build`.

## Example: Nostr Key Pair

```roc
app [main!] { pf: platform "./platform/main.roc" }

import pf.Stdout
import pf.Host

main! = |_args| {
    # Your Nostr secret key (32 bytes)
    secret_key = List.repeat(0, 32)

    # Derive your npub (public key)
    npub = Host.pubkey!(secret_key)

    # Sign a Nostr event
    event_json = "{\"content\": \"hello nostr\"}"
    digest = Host.sha256!(event_json)
    signature = Host.sign!(secret_key, digest)

    Stdout.line!("npub: ${npub}")
    Stdout.line!("signature: ${signature}")

    Ok({})
}
```

## Platform API

| Module | Functions |
|--------|-----------|
| `Host` | `pubkey!`, `sign!`, `verify!`, `sha256!` |
| `Stdout` | `line!` |
| `Stderr` | `line!` |
| `Stdin` | `line!` |

## Links

- **Testing**: [docs/TEST_PLAN.md](docs/TEST_PLAN.md)
- **Roc vs Zig testing**: [docs/TEST_TYPES.md](docs/TEST_TYPES.md)
- **Nostr protocol**: [nostr-protocol/nostr](https://github.com/nostr-protocol/nostr)

## Project Overview

This is a **Roc platform** providing BIP-340 Schnorr cryptographic operations via FFI to libsecp256k1. It's the foundation for building Nostr applications in Roc.

**Key architectural concept:** This is a "platform" - not an application or library. Roc apps link against it as `app [main!] { pf: platform "./platform/main.roc" }` and call hosted functions like `Host.pubkey!(secret_key)`.

**Important test distinction:** `just test` runs Roc runtime assertions only. `just test-all` includes Zig FFI boundary tests. Use `just test` for rapid development, `just test-all` when modifying platform internals.

## Architecture: Platform Coupling

**CRITICAL:** The order of modules in `platform/main.roc`'s `exposes` list must match the order of function pointers in `platform/host.zig`'s `hosted_function_ptrs` array.

### Adding a New Module

When adding a new hosted function:

1. **Create module interface:** `platform/ModuleName.roc`
   - Define hosted functions with `!` suffix (effectful)
   - Document input/output types clearly

2. **Add to `platform/main.roc`:**
   - Add to `exposes` list in **alphabetical order**
   - Import the module

3. **Add Zig implementation to `platform/host.zig`:**
   - Implement function following RocCall ABI: `fn hostedModuleName(ops, ret_ptr, args_ptr)`
   - Add function pointer to `hosted_function_ptrs` in **alphabetical order**
   - Index must match position in main.roc's `exposes`

4. **Register tests in `build.zig`:**
   - Add `b.addTest()` for the module's Zig test file
   - Depend on test step

Example from main.roc (lines 1-14):
```roc
## PLATFORM COUPLING: main.roc <-> host.zig
## The order of modules in `exposes` must match the order of function pointers
## in platform/host.zig's `hosted_function_ptrs` array.
##
## Convention: Both are sorted alphabetically by fully-qualified name.
platform ""
    exposes [Digest, Host, PublicKey, SecretKey, Signature, Stderr, Stdin, Stdout]
```

## Module Pattern

Each module in `platform/*.roc` defines a **record of functions** that Roc apps can call:

```roc
Host := [].{
    pubkey! : List(U8) => List(U8)
    sign! : List(U8), List(U8) => List(U8)
    verify! : List(U8), List(U8), List(U8) => Bool
    sha256! : Str => List(U8)
}
```

**Type wrappers** (`SecretKey.roc`, `PublicKey.roc`, etc.) provide opaque types around `List(U8)` for API clarity but are not enforced by the runtime - they're just documentation and type checking at compile time.

## Roc Testing Constraints

**Hosted functions cannot use `roc test`** - they are effectful (`!` suffix) and require runtime.

- **Roc "tests" are runtime assertions:** Run with `roc test/module.roc` (not `roc test test/module.roc`)
- **Zig tests test FFI boundaries:** Run with `zig build test`

All platform code testing is hybrid: Zig validates FFI/memory, Roc validates API surface.

## Tool Preferences

- Use `rg` (ripgrep) instead of `grep` or `git grep` (except for git history searches)
- See `docs/RIPGREP.md` for project-specific search patterns

## Dependencies

- **Zig** (0.15.2+) - FFI host implementation
- **Roc nightly** - Must match commit hash in `build.zig.zon`
- **libsecp256k1** - BIP-340 Schnorr signatures (managed via Zig)
- **just** - Build automation

## Common Pitfalls

1. **Roc version mismatch:** If `roc version` doesn't match `build.zig.zon`, update build.zig.zon's hash to match the Roc commit hash
2. **Platform coupling:** Adding functions to only main.roc OR only host.zig causes index misalignment and crashes
3. **Using `roc test` with hosted functions:** Won't work - use `roc file.roc` for runtime assertions
4. **Empty returns:** Hosted functions return empty lists or `Bool.false` on errors (no exception types)
