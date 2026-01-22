# Test Types in schnorr-platform

This project uses a hybrid testing approach: Zig tests for FFI internals, Roc unit tests/runtime assertions for API validation.

## Roc Testing: Two Modes

Roc has two ways to use `expect`, depending on function purity.

### Unit Tests (Pure Functions Only)

**Location:** Top-level (outside any expression)
**Run with:** `roc test file.roc`
**Requirement:** Pure functions only (no `!` effects)

```roc
# Top-level expect = unit test
expect 1 + 1 == 2
expect List.len([1, 2, 3]) == 3

app [main!] { pf: platform "..." }
main! = |_args| { Ok({}) }
```

**Limitations:** Cannot test hosted functions (`Host.pubkey!`, `Stdout.line!`, etc.) because they're impure.

### Runtime Assertions (Impure Functions)

**Location:** Inside block expressions
**Run with:** `roc file.roc`
**Works with:** Any code including hosted functions

```roc
app [main!] { pf: platform "./platform/main.roc" }
import pf.Host

main! = |_args| {
    secret_key = List.repeat(0, 32)

    # expect inside block = runtime assertion
    pubkey = Host.pubkey!(secret_key)
    expect List.len(pubkey) == 32

    Ok({})
}
```

**Why:** Hosted functions require runtime execution, so `expect` must be inside `main!` and run as a program.

## Zig Testing: Unit vs Integration

Zig has one test mechanism but different scopes:

| Type | Location | Purpose | Example |
|------|----------|---------|---------|
| **Unit** | Inline in any file | Pure Zig logic | Utility functions |
| **Integration** | Separate `test/*.zig` | FFI boundaries, C libraries | `test/host.zig` (secp256k1) |

Both use the same `test "name" { }` syntax:

```zig
test "description" {
    try testing.expect(actual == expected);
}
```

## This Project's Structure

```
test/
├── host.roc       # Runtime assertions (11 expects)
├── host.zig       # Zig integration tests (secp256k1 FFI, 15 tests)
└── sha256.zig     # Zig unit/integration tests (SHA-256 internals)
```

**Note:** No `test/sha256.roc` - SHA-256 tested via `test/host.roc` calling `Host.sha256!`.

## Critical: Don't Use `roc test` Here

```bash
# ❌ WRONG - fails because hosted functions are impure
roc test test/host.roc

# ✅ RIGHT - runs as program
roc test/host.roc
```

All platform functions are hosted (impure), so all Roc testing uses runtime assertions, not unit tests.

## Zig Test Registration

Tests are file-based, registered in `build.zig`:

```zig
pub fn build(b: *std.Build) void {
    const host_tests = b.addTest(.{
        .root_source_file = b.path("test/host.zig"),
        .target = native_target,
    });

    const test_step = b.step("test", "Run all tests");
    test_step.dependOn(&host_tests.step);
}
```

Zig automatically discovers all `test "name" { }` blocks in registered files.

## Quick Reference

| Test Type | Command | Can test hosted? | Can test FFI? |
|-----------|---------|-----------------|---------------|
| Roc unit tests | `roc test file.roc` | ❌ No | ❌ No |
| Roc runtime assertions | `roc file.roc` | ✅ Yes | ✅ Yes (via Host) |
| Zig tests | `zig build test` | N/A | ✅ Yes |

In this project:
- **Zig** - FFI internals, memory management, edge cases
- **Roc** - API surface, user-facing behavior
