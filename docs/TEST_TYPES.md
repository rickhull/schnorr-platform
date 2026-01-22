# Test Types in schnorr-platform

This document explains the different testing approaches used in this project, covering both Roc and Zig testing strategies.

## Overview

This project uses a hybrid testing approach:

- **Zig tests** - For platform internals and secp256k1 FFI integration
- **Roc runtime assertions** - For API validation and integration testing (in `main!`)
- **No Roc comptime unit tests** - Comptime unit tests cannot test hosted functions

---

## Roc Testing

Roc has two modes for testing, both using the `expect` keyword but in different contexts.

### Roc Comptime Unit Tests

**Location:** Top-level (outside any expression)

**Run with:** `roc test file.roc`

**Characteristics:**
- Evaluated at **compile time**
- Only works with **pure functions** (no `!` effects)
- Cannot call hosted functions (Host.*, Sha256.*, Stdout.*, etc.)
- Fast feedback, proven by compiler

**Example:**
```roc
# Top-level unit tests (outside any expression)
expect 1 + 1 == 2
expect List.len([1, 2, 3]) == 3
expect Str.count_utf8_bytes("hello") == 5

app [main!] { pf: platform "./platform/main.roc" }
main! = |_args| { Ok({}) }
```

**Limitations:**
- Cannot test effectful functions
- Cannot test I/O operations
- Cannot test FFI integrations

### Roc Runtime Assertions

**Location:** Within block expressions (e.g., inside `main!`)

**Run with:** `roc file.roc`

**Characteristics:**
- Executed at **runtime**
- Works with **any code** including hosted functions
- `expect` crashes program on failure
- Required for testing platform modules

**Example:**
```roc
app [main!] { pf: platform "./platform/main.roc" }
import pf.Stdout
import pf.Host

main! = |_args| {
    secret_key = [
        0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    ]

    # Runtime assertions (within block expression)
    pubkey = Host.pubkey!(secret_key)
    expect List.len(pubkey) == 32

    sig = Host.sign!(secret_key, Sha256.binary!("msg"))
    expect List.len(sig) == 64

    is_valid = Host.verify!(pubkey, Sha256.binary!("msg"), sig)
    expect is_valid == True

    Ok({})
}
```

**When to use:**
- Testing platform modules (Host, Sha256, Stdout, etc.)
- Integration testing
- End-to-end workflows

---

## Zig Testing

Zig has one type of test (runtime), but can be organized as unit tests or integration tests based on scope.

### Zig Unit Tests

**Location:** Inline in implementation files (`test "name" { }` blocks)

**Run with:** `zig test file.zig` or `zig build test`

**Characteristics:**
- Always runs at **test time** (not compile time)
- Test single file, focused scope
- Fast and isolated
- No external dependencies typically

**Example:**
```zig
const std = @import("std");
const testing = std.testing;

test "add two numbers" {
    try testing.expect(1 + 1 == 2);
}

test "string concatenation" {
    const result = std.fmt.allocPrintZig("{s} {s}", .{"hello", "world"});
    defer std.heap.c_allocator.free(result);
    try testing.expectEqual(@as(usize, "helloworld").len, result.len);
}
```

**When to use:**
- Testing pure Zig logic
- Utility functions
- Data structures
- Algorithms

### Zig Integration Tests

**Location:** Separate test files, link multiple components

**Run with:** `zig build test`

**Characteristics:**
- Still runs at test time
- Tests multiple files/components together
- Links C libraries, external dependencies
- Tests FFI integrations

**Example (test/host.zig):**
```zig
const std = @import("std");
const secp256k1 = @cImport({
    @cInclude("secp256k1.h");
    @cInclude("secp256k1_extrakeys.h");
});

test "Host: keypair creation from valid secret key" {
    const ctx = secp256k1.secp256k1_context_create(
        secp256k1.SECP256K1_CONTEXT_SIGN | secp256k1.SECP256K1_CONTEXT_VERIFY,
    );
    defer secp256k1.secp256k1_context_destroy(ctx);

    const secret_key = [_]u8{0x01} ** 32;
    var keypair: secp256k1.secp256k1_keypair = undefined;
    const result = secp256k1.secp256k1_keypair_create(ctx, &keypair, &secret_key);

    try testing.expectEqual(@as(c_int, 1), result);
}
```

**When to use:**
- Testing FFI integrations
- Testing C library bindings
- Testing complex multi-file builds
- Testing components that need external dependencies

---

## Comparison Table: Roc vs Zig Testing

| Aspect | Roc Comptime Unit Tests | Roc Runtime Assertions | Zig Unit | Zig Integration |
|--------|------------------------|------------------------|----------|-----------------|
| **Keyword** | `expect` | `expect` | `test` | `test` |
| **Location** | Top-level (outside any expression) | Within block expressions | Inline | Separate file |
| **Command** | `roc test file.roc` | `roc file.roc` | `zig test file.zig` | `zig build test` |
| **When runs** | Compile time | Runtime | Test time | Test time |
| **Can test hosted functions** | ❌ No | ✅ Yes | N/A | N/A |
| **Can test C FFI** | ❌ No | ✅ Yes | ❌ No* | ✅ Yes |
| **Fast feedback** | ✅ Instant | ❌ No | ✅ Yes | ❌ No |

*Zig unit tests typically don't include C FFI. Integration tests add C library linking.

---

## How `zig build test` Works

Zig uses **file-based test registration**:

### 1. Register Test Files in build.zig

```zig
pub fn build(b: *std.Build) void {
    // ... existing code ...

    // Register test files
    const host_module_tests = b.addTest(.{
        .root_source_file = b.path("test/host.zig"),
        .target = native_target,
    });

    const sha256_tests = b.addTest(.{
        .root_source_file = b.path("test/sha256.zig"),
        .target = native_target,
    });

    // Add to test step
    const test_step = b.step("test", "Run all tests");
    test_step.dependOn(&host_module_tests.step);
    test_step.dependOn(&sha256_tests.step);
}
```

### 2. Zig Discovers Tests Automatically

When you run `zig build test`:
1. Zig reads each registered test file
2. Scans for `test "name" { ... }` blocks
3. Compiles the file with required dependencies
4. Executes each test block
5. Reports results

### 3. No Manual Test Listing Required

**You do NOT need to:**
- List individual tests
- Create test registries
- Manually specify test names

**You DO need to:**
- Point `b.addTest()` at test files
- Use `test "name" { }` syntax in test files
- Link required C libraries (if needed)

---

## This Project's Test Structure

```
test/
├── host.roc              # Roc runtime assertions for Host module
├── host.zig              # Zig integration tests for secp256k1 FFI
├── sha256.roc            # Roc runtime assertions for Sha256 module
└── sha256.zig            # Zig unit tests for Sha256 internals
```

| Test File | Type | Command | Tests |
|----------|------|--------|-------|
| `test/host.roc` | Roc runtime assertions | `roc test/host.roc` | Host module API |
| `test/host.zig` | Zig integration | `zig build test` | secp256k1 FFI |
| `test/sha256.roc` | Roc runtime assertions | `roc test/sha256.roc` | Sha256 module API |
| `test/sha256.zig` | Zig unit | `zig build test` | Sha256 internals |

---

## Key Differences Summary

**Roc vs Zig Testing:**

| | Roc | Zig |
|---|---|-----|
| Comptime unit tests | ✅ Top-level `expect` | ❌ None |
| Runtime assertions | ✅ `expect` in block expressions | ✅ `test` blocks |
| Can test hosted functions | ✅ (runtime only) | ✅ (with FFI setup) |
| Can test pure logic | ✅ (comptime) | ✅ (any test) |
| Test discovery | Automatic (file-based) | Automatic (scan for `test` keyword) |

**Zig Unit vs Integration:**

| | Unit Tests | Integration Tests |
|---|------------|-------------------|
| **Location** | Inline in source files | Separate test files |
| **Scope** | Single file, focused | Multiple files, linked |
| **Dependencies** | Minimal | External libraries (C, etc.) |
| **Examples** | Utility functions | secp256k1 FFI, multi-file builds |
| **In this project** | `test/sha256.zig` | `test/host.zig` |

---

## Quick Reference

### Running Tests

```bash
# Zig tests (all)
zig build test

# Roc runtime assertions
roc test/host.roc
roc test/sha256.roc

# Roc comptime unit tests (none currently exist in this project)
# roc test file.roc  # Only works with pure functions
```

### Writing Tests

**Roc comptime unit test (not used for this project):**
```roc
expect 1 + 1 == 2
```

**Roc runtime assertion:**
```roc
main! = |_args| {
    value = someFunction()
    expect value == expected
    Ok({})
}
```

**Zig unit test:**
```zig
test "name" {
    try testing.expect(actual == expected);
}
```

**Zig integration test:**
```zig
test "name" {
    // Call C FFI, test multiple components
    const ctx = secp256k1_context_create(...);
    defer secp256k1_context_destroy(ctx);
    try testing.expect(ctx != null);
}
```
