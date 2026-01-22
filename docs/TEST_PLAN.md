# schnorr-platform Test Plan

> **See also:** [TEST_TYPES.md](TEST_TYPES.md) for detailed Roc vs Zig testing concepts.

## Philosophy

**Hybrid approach:** Zig tests for FFI internals, Roc runtime assertions for API validation.

### Why Two Types?

| Aspect | Zig Tests | Roc Runtime Assertions |
|--------|-----------|----------------------|
| **Purpose** | FFI boundaries, memory safety | API surface, usage patterns |
| **Location** | `test/*.zig` | `test/*.roc` |
| **Run with** | `just test-zig` | `just test` |
| **Speed** | ~600ms (fixed overhead) | ~50ms |
| **Primary?** | ✅ Yes (platform internals) | Secondary (API validation) |

### Critical: `roc test` Doesn't Work Here

Hosted functions (marked with `!`) require runtime and can't use `roc test`'s compile-time evaluation.

```bash
# ❌ WRONG - fails with COMPTIME EVAL ERROR
roc test test/host.roc

# ✅ RIGHT - runs as program
roc test/host.roc
```

All platform functions are effectful, so Roc "tests" are just runtime assertions in normal programs using `expect`.

## Test Structure

```
test/
├── host.roc       # 11 runtime assertions (API surface)
├── host.zig       # 15 Zig tests (FFI internals, edge cases)
└── sha256.zig     # Zig tests for SHA-256 internals
```

**Note:** No `test/sha256.roc` - SHA-256 is tested via `test/host.roc` calling `Host.sha256!`.

## Commands

```bash
# Roc tests only (fast, daily development)
just test

# All tests including Zig (slower, platform changes)
just test-zig

# Build + test
just dev
```

**Why split?** Zig tests have ~575ms fixed overhead. Use `just test` for rapid API development, `just test-zig` when modifying platform internals.

## What's Tested

### Zig Tests (Primary)
- FFI boundary correctness
- Memory management
- secp256k1 context handling
- Edge cases (invalid lengths, wrong types)

### Roc Tests (Secondary)
- API correctness from user perspective
- Expected return values
- Error handling (empty lists, Bool.false)

### Not Tested
- Stdio modules (trivial wrappers, indirect validation via other tests)

## Adding Tests

**Zig:** Add `test "name" { }` blocks to `test/*.zig`. Register in `build.zig`.

**Roc:** Add `expect` assertions to `test/*.roc` files. Remember these run as programs, not via `roc test`.
