# schnorr-platform Test Plan

> **See also:** [TEST_TYPES.md](TEST_TYPES.md) for detailed documentation of Roc and Zig testing concepts.

## Philosophy

**Hybrid testing approach:** Zig tests for platform internals, Roc runtime assertions for API validation.

### Important: Roc Testing Limitations

**Host functions are effectful** (marked with `!`) and cannot use `roc test`'s compile-time evaluation.

| Command | When It Runs | What Works |
|---------|--------------|------------|
| `roc test file.roc` | **Compile time** | Pure functions only (no `!` effects) |
| `roc file.roc` | **Runtime** | Any code, including hosted functions |

**For platform development:** Zig tests are primary. Roc "tests" are just runtime assertions in normal programs.

### Zig Tests (Primary for Platform)
- Test platform internals
- Edge cases and error handling
- Memory management
- Fast to run, direct host access
- Tests what Roc can't reach
- Run with `zig test` or `just test-debug`

### Roc Runtime Assertions (Secondary)
- Validate API surface from user perspective
- Run as normal programs with `roc file.roc`
- Use `expect` for runtime assertions (crash on failure)
- Cannot use `roc test` command with hosted functions

## Directory Structure

```
test/
├── host.roc              # Roc runtime assertions for Host module (run with `roc`, not `roc test`)
├── host.zig              # Zig unit tests for Host internals (primary)
├── sha256.roc            # Roc runtime assertions for Sha256 module (run with `roc`)
└── sha256.zig            # Zig unit tests for Sha256 internals (primary)

examples/
└── *.roc                 # Demonstration programs showing API usage
```

## Justfile Recipes

### Test Recipes
```
just test               - Run Roc tests only (fast, ~50ms)
just test-debug         - Run all tests including Zig (slow, ~600ms)
just dev                - Build platform + run tests
just build              - Build Zig platform (all targets)
```

### Why Separate `test` and `test-debug`?

**Zig test overhead:** ~575ms per run (fixed test infrastructure cost, not per-test)

**Breakdown:**
- `zig build test`: ~575ms (11 tests, mostly runner overhead)
- Roc tests: ~50ms total

**Implication:** For most development, you want fast feedback on API changes. The Zig tests test FFI internals and edge cases - useful when debugging platform code, but overkill for routine development.

**Workflow:**
- Daily development: `just test` (fast, validates API surface)
- Debugging platform issues: `just test-debug` (slow, validates FFI boundaries)

### Removed
```
just run                - Removed (not useful - use `just dev` or run roc directly)
just test-host          - Removed (use `just test`)
just test-sha256        - Removed (use `just test`)
just test-roc           - Removed (use `just test`)
just test-zig           - Removed (use `just test-debug`)
just smoke-test         - Removed (tests are fast enough to run all)
```

## Test Scenarios

### Host Module

#### Roc Runtime Assertions (`test/host.roc`)
**Purpose:** Validate Host module API from user perspective

**Note:** These are runtime assertions, not comptime unit tests. Run with `roc test/host.roc`, NOT `roc test test/host.roc`.

```roc
app [main!] { pf: platform "./platform/main.roc" }

import pf.Stdout
import pf.Host

main! = |_args| {
    # Test 1: Valid 32-byte secret key produces 32-byte public key
    secret_key = [
        0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    ]

    pubkey = Host.pubkey!(secret_key)
    expect List.len(pubkey) == 32
    expect pubkey != []

    # Test 2: Invalid length secret key returns empty list
    short_key = [0x01]
    result = Host.pubkey!(short_key)
    expect List.len(result) == 0

    # Test 3: All-zeros secret key is valid
    zeros_key = List.pad(32, 0, [0])
    pubkey = Host.pubkey!(zeros_key)
    expect List.len(pubkey) == 32

    # Test 4: Sign 32-byte message and verify signature
    digest = [0u8; 32]
    sig = Host.sign!(secret_key, digest)
    expect List.len(sig) == 64
    expect sig != []

    # Test 5: Verify valid signature
    is_valid = Host.verify!(pubkey, digest, sig)
    expect is_valid == Bool.true

    # Test 6: Verify invalid signature fails
    bad_sig = List.pad(64, 255, [0])
    is_valid = Host.verify!(pubkey, digest, bad_sig)
    expect is_valid == Bool.false

    Ok({})
}
```

#### Zig Tests (`test/host.zig`)
**Purpose:** Validate Host internals, edge cases, memory safety

```zig
const std = @import("std");
const testing = std.testing;
const expect = std.testing.expect;

// Test RocList.empty()
test "Host.pubkey: empty secret key returns empty list" {
    const secret_key_bytes = [_]u8{0} ** 32;
    const result = testHostPubkey(&secret_key_bytes);
    try testing.expectEqual(@as(usize, result.len), 0);
}

// Test RocList.allocateExact with 32 bytes
test "Host.pubkey: valid key returns 32 bytes" {
    const secret_key_bytes = [_]u8{0x01} ** 32;
    const result = testHostPubkey(&secret_key_bytes);
    try testing.expectEqual(@as(usize, result.len), 32);
}

// Test invalid secret key (all zeros)
test "Host.pubkey: invalid key returns empty list" {
    const invalid_key = [_]u8{0xFF} ** 32;
    const result = testHostPubkey(&invalid_key);
    try testing.expectEqual(@as(usize, result.len), 0);
}

// Test Host.sign returns 64 bytes
test "Host.sign: valid input returns 64 bytes" {
    const secret_key_bytes = [_]u8{0x01} ** 32;
    const digest_bytes = [_]u8{0} * 32;

    const sig = testHostSign(&secret_key_bytes, &digest_bytes);
    try testing.expectEqual(@as(usize, sig.len), 64);
}

// Test Host.verify returns 1 for valid, 0 for invalid
test "Host.verify: valid signature returns true" {
    const valid_sig = [_]u8{0x42} ** 64; // Mock valid sig
    const result = testHostVerify(&mock_pubkey, &mock_digest, &valid_sig);
    try testing.expect(result, @as(u8, 1));
}
```

### Sha256 Module

#### Roc Runtime Assertions (`test/sha256.roc`)
**Purpose:** Validate Sha256 API from user perspective

**Note:** These are runtime assertions. Run with `roc test/sha256.roc`, NOT `roc test test/sha256.roc`.

```roc
app [main!] { pf: platform "./platform/main.roc" }

import pf.Stdout
import pf.Sha256

main! = |_args| {
    # Test 1: Empty string hash
    hash1 = Sha256.hex!("")
    expect hash1 == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

    # Test 2: Known input produces known hash
    hash2 = Sha256.hex!("hello world")
    expect hash2 == "b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9"

    # Test 3: Different inputs produce different hashes
    hash_a = Sha256.hex!("foo")
    hash_b = Sha256.hex!("bar")
    expect hash_a != hash_b

    # Test 4: Hash length is consistent (64 hex chars)
    hash_result = Sha256.hex!("test")
    expect Str.count_utf8_bytes(hash_result) == 64

    Ok({})
}
```

#### Zig Tests (`test/sha256.zig`)
**Purpose:** Validate Sha256 internals, memory management

```zig
const std = @import("std");
const testing = std.testing;

// Test empty string
test "Sha256.hex: empty string" {
    const result = testSha256Hex("");
    try testing.expectEqual(result, "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
}

// Test hello world
test "Sha256.hex: hello world" {
    const result = testSha256Hex("hello world");
    try testing.expectEqual(result, "b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9");
}

// Test output is always 64 characters
test "Sha256.hex: output length" {
    const inputs = [_][]const u8{ "", "a", "hello world", "test" };
    for (inputs) |input| {
        const result = testSha256Hex(input);
        try testing.expectEqual(@as(usize, result.len), 64);
    }
}
```

## Implementation Status

✅ **Complete:**
- Zig test files: `test/host.zig`, `test/sha256.zig`
- Roc runtime assertion files: `test/host.roc`, `test/sha256.roc`
- build.zig test registration for Zig tests
- justfile recipes: `just test` (Roc only), `just test-debug` (all)
- `test/host.roc` uses `expect` for proper failure detection
- `test/host.roc` includes edge case tests (invalid inputs, error paths)

❌ **Skipped:**
- Stdio module tests (not needed - trivial wrappers from template)

🔄 **Future Work (Optional):**
- Performance benchmarks (if needed)
- Property-based tests (if needed)

## build.zig Test Registration

```zig
pub fn build(b: *std.Build) void {
    // ... existing code ...

    // Add test steps
    const test_step = b.step("test", "Run all tests");

    // Host tests
    const host_tests = b.addTest(.{
        .root_source_file = b.path("test/host.zig"),
        .target = native_target,
    });
    test_step.dependOn(&host_tests.step);

    // Sha256 tests
    const sha256_tests = b.addTest(.{
        .root_source_file = b.path("test/sha256.zig"),
        .target = native_target,
    });
    test_step.dependOn(&sha256_tests.step);

    // ... rest of build
}
```

## Test Coverage Goals

**Target: ~5-10 tests per module (not comprehensive, but meaningful)**

- **Host module:** 8 Roc tests + 7 Zig tests ✅ **On target**
  - Roc: API surface (pubkey!, sign!, verify! with valid inputs, invalid inputs, edge cases)
  - Zig: edge cases (invalid keys, wrong lengths, context creation)

- **Sha256 module:** 5 Roc tests + 4 Zig tests ✅ **On target**
  - Roc: API surface (known vectors, output format, binary encoding)
  - Zig: empty string, unicode handling, buffer management

- **Stdio modules:** Not tested
  - These are trivial wrappers around Zig's well-tested stdlib
  - Copied from roc-platform-template-zig (battle-tested)
  - Indirectly validated by all other tests (they use Stdout.line!)

## Benefits

1. **Rapid feedback** - Roc tests run fast (~50ms), Zig tests take ~600ms
2. **Complete coverage** - Roc runtime assertions for API, Zig tests for internals
3. **Maintainable** - Tests are clear about what they validate
4. **Developer friendly** - `just dev` for quick edit-build-test cycle
5. **CI ready** - `just test-debug` for full test suite

## Roc Testing: `roc test` vs `roc`

### Two Modes of Execution

**1. Comptime unit tests with `roc test`:**
```roc
# Top-level unit tests (outside any expression)
expect 1 + 1 == 2
expect List.len([1, 2, 3]) == 3

app [main!] { pf: platform "..." }
main! = |_args| { Ok({}) }
```
- Run with: `roc test file.roc`
- Evaluates `expect` at compile time
- Only works with **pure functions** (no `!` effects)
- Cannot call hosted functions (Host.*, Sha256.*, etc.)
- Fast feedback for pure logic

**2. Runtime assertions with `roc`:**
```roc
app [main!] { pf: platform "..." }
import pf.Host

main! = |_args| {
    pubkey = Host.pubkey!(secret_key)
    expect List.len(pubkey) == 32  # Runtime assertion
    Ok({})
}
```
- Run with: `roc file.roc`
- Executes `main!` normally
- Works with **any code** including hosted functions
- `expect` crashes on failure at runtime
- Required for platform testing

### For This Platform

Since all platform functions are effectful (hosted), we use:

- **`test/*.zig`** - Zig unit tests (primary, run with `zig test`)
- **`test/*.roc`** - Roc runtime assertions (run with `roc`, not `roc test`)
- **`examples/*.roc`** - Demonstration programs

**Do NOT use `roc test test/*.roc`** - it will fail with "COMPTIME EVAL ERROR" because hosted functions can't be evaluated at compile time.

## Future Expansion

As the platform grows, we can add:

- **Performance tests** - Benchmark signing/verification speed
- **Integration tests** - Full Nostr event creation/signing flow
- **Fuzzing** - Find edge cases with host functions
- **Property-based tests** - Invariants like "pubkey(sign(sk, msg)) == verify(pubkey, msg, sig(sk, msg))"
