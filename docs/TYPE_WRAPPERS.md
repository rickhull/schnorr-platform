# Type Wrapper Patterns for FFI and Validation

## Motivation: The Problem

When working with FFI boundaries, cryptographic operations, or binary protocols, you often work with raw byte arrays (`List(U8)`). However, using `List(U8)` everywhere leads to bugs:

```roc
# WITHOUT type wrappers - easy to confuse:
signature = Host.sign!(secret_key, digest)
pubkey = Host.pubkey!(secret_key)  # Oops! Wrong order
verify_result = Host.verify!(digest, signature, pubkey)  # Wrong order!

# WITH type wrappers - compiler catches mistakes:
sig = Signing.sign!(sk, digest)
pk = Signing.pubkey!(sk)
# verify!(pk, digest, sig)  # Compiler error if wrong order!
```

Type wrappers enforce **length constraints** and **prevent type confusion** at compile time.

## Type Definition Options: Which to Use?

Roc has three ways to define types, each with different semantics:

### Quick Reference

| Syntax | Type | Visibility | Can Convert? | Use When |
|--------|------|------------|--------------|----------|
| `MyType = T` | Structural alias | Public | Yes (freely) | Simple alias, interchangeability is fine |
| `MyType := [Wrapper(T)]` | Nominal | Public | Yes (via pattern matching) | **Type-safe wrappers** ⭐ |
| `MyType :: T` | Opaque | Private only | No | Hiding implementation details |

### Structural Alias (`=`)

```roc
# Define
MyBytes = List(U8)

# Use
bytes : MyBytes = [1, 2, 3]
more : List(U8) = bytes  # OK - same type!
```

**Characteristics:**
- Can substitute freely - identical types are interchangeable
- No type safety - `MyBytes` and `YourBytes` are THE SAME type
- Good for: Convenience aliases where you don't care about distinction

**When to use:** Simple type aliases where interchangeability is fine.

### Nominal Type (`:=`) - **RECOMMENDED FOR WRAPPERS**

```roc
# Define single-variant tag union
Digest := [DigestBytes(List(U8))]
SecretKey := [SecretKeyBytes(List(U8))]

# Use - MUST use prefix to construct
d1 = DigestBytes([1, 2, 3])  # OK
d2 : Digest = DigestBytes([1, 2, 3])  # OK

# These are DIFFERENT types - compiler prevents confusion
# sk : SecretKey = d1  # TYPE ERROR!
```

**Characteristics:**
- **Distinct type** even if structure is identical
- **Public** - can be exported and used from other modules
- **Can convert** via pattern matching: `match digest { DigestBytes(bytes) => bytes }`
- Type-safe: Can't pass `SecretKey` where `Digest` expected

**When to use:**
- Type-safe public wrappers that prevent type confusion
- Length-constrained types (crypto keys, digests, etc.)
- FFI boundaries where raw bytes need validation
- **This is the pattern for Signing.roc!**

### Opaque Type (`::`)

```roc
# Define - module private
SecretDigest :: List(U8)

# Use - only within THIS module
make_secret : List(U8) -> SecretDigest
make_secret = |bytes| bytes  # Works in this module

# BUT: Cannot convert between SecretDigest and List(U8)
# get_bytes : SecretDigest -> List(U8)
# get_bytes = |digest| digest  # TYPE ERROR! They're incompatible!
```

**Characteristics:**
- **Module-private** - only visible in the module where defined
- **Cannot convert** to/from underlying type (even in same module!)
- Compiler treats them as completely different types
- Good for: Hiding implementation details

**When to use:**
- Internal implementation details you want to hide
- NOT for public wrapper types (can't export!)
- NOT for FFI wrappers (can't convert to `List(U8)` for host calls)

**❌ Why opaque types DON'T work for wrappers:**

```roc
# This doesn't work:
Digest :: List(U8)

make_digest : List(U8) -> Try(Digest, [InvalidLength])
make_digest = |bytes|
    match List.len(bytes) {
        32 => Ok(bytes)  # ERROR: List(U8) != Digest
        _ => Err(InvalidLength)
    }
```

The compiler won't let you convert between `Digest` and `List(U8)`, even though `Digest` is defined as `List(U8)`. Opaque types are truly opaque.

## Decision Tree

```
Need to wrap a type for type safety?
│
├─ No: Just use structural alias (=)
│   └─ MyBytes = List(U8)
│
└─ Yes: Need to export from module?
    ├─ No: Use opaque (::) for internal-only
    │   └─ InternalState :: List(U8)
    │
    └─ Yes: Use nominal (:=) ⭐ RECOMMENDED
        └─ Digest := [DigestBytes(List(U8))]
```

## The Single-Variant Tag Union Pattern

For type-safe, length-constrained wrappers, use **nominal types with single-variant tag unions**:

```roc
Digest := [DigestBytes(List(U8))]
SecretKey := [SecretKeyBytes(List(U8))]
PublicKey := [PublicKeyBytes(List(U8))]
Signature := [SignatureBytes(List(U8))]
```

### Constructor with Validation

Validate at construction time, use `Try` for errors:

```roc
make_digest : List(U8) -> Try(Digest, [InvalidLength])
make_digest = |bytes|
    match List.len(bytes) {
        32 => Ok(DigestBytes(bytes))
        len => Err(InvalidLength(32, len, "Digest"))
    }

# Usage
result = make_digest(input_bytes)
match result {
    Ok(digest) => {
        # digest is guaranteed to be 32 bytes
        "Valid digest"
    }
    Err(InvalidLength(expected, actual, type_name)) =>
        "Wrong length: expected ${expected.to_str()}, got ${actual.to_str()}"
}
```

**Key insight:** Once you have a `Digest` value, it's guaranteed valid. No need to check length again.

### Unwrapping for FFI Calls

To call host functions, unwrap with pattern matching:

```roc
to_bytes : Digest -> List(U8)
to_bytes = |digest|
    match digest {
        DigestBytes(bytes) => bytes
    }

# Or inline (when calling Host):
pubkey! : SecretKey => Try(PublicKey, [CryptoError])
pubkey! = |sk|
    match sk {
        SecretKeyBytes(sk_bytes) => {
            result = Host.pubkey!(sk_bytes)  # Call Host
            match List.len(result) {
                0 => Err(InvalidSecretKey)
                32 => Ok(PublicKeyBytes(result))
                _ => Err(InvalidSecretKey)
            }
        }
    }
```

## Ergonomics and Patterns

### Pattern 1: Direct Unwrap

Simple case: single parameter function.

```roc
# Extractor function
to_bytes : Digest -> List(U8)
to_bytes = |digest|
    match digest {
        DigestBytes(bytes) => bytes
    }

# Inline unwrap
hash_digest : Digest => List(U8)
hash_digest = |digest|
    match digest {
        DigestBytes(bytes) => Hash.hash!(bytes)
    }
```

### Pattern 2: Multiple Unwraps

Functions that take multiple wrapped types (like `sign!`):

```roc
sign! : SecretKey, Digest => Try(Signature, [CryptoError])
sign! = |sk, digest|
    match sk {
        SecretKeyBytes(sk_bytes) =>
            match digest {
                DigestBytes(digest_bytes) => {
                    result = Host.sign!(sk_bytes, digest_bytes)
                    match List.len(result) {
                        0 => Err(SignFailed)
                        64 => Ok(SignatureBytes(result))
                        _ => Err(SignFailed)
                    }
                }
            }
    }
```

**Note:** The nested `match` is verbose but type-safe. This boilerplate prevents real bugs.

### Pattern 3: Record for Multiple Returns

When unwrapping multiple values, return a record:

```roc
# Return unwrapped values as a record
unwrap_for_verify : PublicKey, Digest, Signature => { pk: List(U8), digest: List(U8), sig: List(U8) }
unwrap_for_verify = |pk, digest, sig|
    match pk {
        PublicKeyBytes(pk_bytes) =>
            match digest {
                DigestBytes(digest_bytes) =>
                    match sig {
                        SignatureBytes(sig_bytes) =>
                            { pk: pk_bytes, digest: digest_bytes, sig: sig_bytes }
                    }
            }

# Usage
unwrapped = unwrap_for_verify(pubkey, digest, signature)
is_valid = Host.verify!(unwrapped.pk, unwrapped.digest, unwrapped.sig)
```

## Real-World Example: Crypto Signing Module

Here's a complete example showing the pattern in practice:

```roc
## Type-safe wrapper types (nominal, single-variant tag unions)
Digest := [DigestBytes(List(U8))]
SecretKey := [SecretKeyBytes(List(U8))]
PublicKey := [PublicKeyBytes(List(U8))]
Signature := [SignatureBytes(List(U8))]

## Error types
InvalidLength := [InvalidLength(U8, U64, Str)]  # expected, actual, type_name
CryptoError := [InvalidSecretKey, SignFailed, InvalidPublicKey]

## Constructors with validation

make_digest : List(U8) -> Try(Digest, [InvalidLength])
make_digest = |bytes|
    match List.len(bytes) {
        32 => Ok(DigestBytes(bytes))
        len => Err(InvalidLength(32, len, "Digest"))
    }

make_secret_key : List(U8) -> Try(SecretKey, [InvalidLength])
make_secret_key = |bytes|
    match List.len(bytes) {
        32 => Ok(SecretKeyBytes(bytes))
        len => Err(InvalidLength(32, len, "SecretKey"))
    }

make_public_key : List(U8) -> Try(PublicKey, [InvalidLength])
make_public_key = |bytes|
    match List.len(bytes) {
        32 => Ok(PublicKeyBytes(bytes))
        len => Err(InvalidLength(32, len, "PublicKey"))
    }

make_signature : List(U8) -> Try(Signature, [InvalidLength])
make_signature = |bytes|
    match List.len(bytes) {
        64 => Ok(SignatureBytes(bytes))
        len => Err(InvalidLength(64, len, "Signature"))
    }

## Crypto operations (wrap Host functions)

pubkey! : SecretKey => Try(PublicKey, [CryptoError])
pubkey! = |sk|
    match sk {
        SecretKeyBytes(sk_bytes) => {
            result = Host.pubkey!(sk_bytes)
            match List.len(result) {
                0 => Err(InvalidSecretKey)
                32 => Ok(PublicKeyBytes(result))
                _ => Err(InvalidSecretKey)
            }
        }
    }

sign! : SecretKey, Digest => Try(Signature, [CryptoError])
sign! = |sk, digest|
    match sk {
        SecretKeyBytes(sk_bytes) =>
            match digest {
                DigestBytes(digest_bytes) => {
                    result = Host.sign!(sk_bytes, digest_bytes)
                    match List.len(result) {
                        0 => Err(SignFailed)
                        64 => Ok(SignatureBytes(result))
                        _ => Err(SignFailed)
                    }
                }
            }
    }

verify! : PublicKey, Digest, Signature => Bool
verify! = |pk, digest, sig|
    match pk {
        PublicKeyBytes(pk_bytes) =>
            match digest {
                DigestBytes(digest_bytes) =>
                    match sig {
                        SignatureBytes(sig_bytes) =>
                            Host.verify!(pk_bytes, digest_bytes, sig_bytes)
                    }
            }
    }

## Optional: Helper functions for convenience

to_digest_bytes : Digest -> List(U8)
to_digest_bytes = |digest|
    match digest {
        DigestBytes(bytes) => bytes
    }

to_secret_key_bytes : SecretKey -> List(U8)
to_secret_key_bytes = |sk|
    match sk {
        SecretKeyBytes(bytes) => bytes
    }
```

**Usage example:**

```roc
# Create wrapped types
sk_result = make_secret_key(raw_sk_bytes)
digest_result = make_digest(hash_bytes)

# Use with error handling
result = match sk_result {
    Ok(sk) => match digest_result {
        Ok(digest) => {
            # Both valid - proceed
            sig_result = sign!(sk, digest)
            match sig_result {
                Ok(sig) => {
                    # Verify signature
                    pk_result = pubkey!(sk)
                    match pk_result {
                        Ok(pk) => {
                            is_valid = verify!(pk, digest, sig)
                            match is_valid {
                                Bool.True => "✓ Signature valid"
                                Bool.False => "✗ Signature invalid"
                            }
                        }
                        Err(_) => "✗ Failed to derive pubkey"
                    }
                }
                Err(_) => "✗ Signing failed"
            }
        }
        Err(_) => "✗ Invalid digest"
    }
    Err(_) => "✗ Invalid secret key"
}
```

## Module Boundaries Hide Implementation Complexity

One concern with the wrapper pattern is the verbose nested matching required to unwrap types before calling FFI functions. However, **this complexity is entirely hidden inside the module** - users get a clean API.

### Inside the Module (Implementation)

Module authors deal with the nesting:

```roc
## Inside Signing.roc - 3 levels of nesting
sign! : SecretKey, Digest => Try(Signature, [CryptoError])
sign! = |sk, digest|
    match sk {
        SecretKeyBytes(sk_bytes) =>
            match digest {
                DigestBytes(digest_bytes) => {
                    result = Host.sign!(sk_bytes, digest_bytes)
                    match List.len(result) {
                        64 => Ok(SignatureBytes(result))
                        _ => Err(SignFailed)
                    }
                }
            }
    }
```

### Outside the Module (User Code)

Users get a simple, clean API:

```roc
## In user code - no nesting visible!
import Signing

sk = Signing.make_secret_key!(bytes)
digest = Signing.make_digest!(hash)

# One line - no nesting
sig = Signing.sign!(sk, digest)

# Verify - also clean
is_valid = Signing.verify!(pk, digest, sig)

match is_valid {
    True => "Valid!"
    False => "Invalid"
}
```

### When Users See Nesting

Users only see **one level** of unwrapping when they want to inspect contents:

```roc
# User code - single match to inspect
match sig {
    SignatureBytes(bytes) => {
        Stdout.line!("Signature is ${List.len(bytes)} bytes")
    }
}
```

This is intentional - the wrapper type makes the FFI boundary explicit while hiding the implementation complexity of repeatedly unwrapping and rewrapping.

### Key Takeaway

**The module boundary is where complexity goes to die.** Push the ugly nested matching inside the module so users don't have to deal with it. Users work with clean, type-safe wrapper types and never see the implementation details.

## Common Gotchas

### Gotcha 1: Opaque Types Can't Convert

```roc
# ❌ This doesn't work:
Digest :: List(U8)

make : List(U8) -> Digest
make = |bytes| bytes  # ERROR: Can't convert List(U8) to Digest

# ✅ Use nominal instead:
Digest := [DigestBytes(List(U8))]

make : List(U8) -> Try(Digest, _)
make = |bytes| Ok(DigestBytes(bytes))  # OK
```

### Gotcha 2: Match Verbosity

Unwrapping requires pattern matching every time. This verbosity is intentional:

```roc
# Can't just access the bytes directly
# bytes = digest.bytes  # NO - records don't work that way with tag unions

# Must match
bytes = match digest {
    DigestBytes(b) => b
}
```

**Why this is OK:** The boilerplate prevents real bugs. You're explicitly handling the unwrap, making the FFI boundary visible.

### Gotcha 3: Function Type Syntax for Higher-Order Functions

When passing effectful functions, use parentheses and `=>`:

```roc
# ❌ Wrong:
# func : List(U8) => List(U8), SecretKey -> Try(...)

# ✅ Right:
func! : (List(U8) => List(U8)), SecretKey => Try(PublicKey, _)
func! = |host_fn, sk|
    match sk {
        SecretKeyBytes(bytes) => {
            result = host_fn(bytes)  # Call effectful function
            Ok(PublicKeyBytes(result))
        }
    }
```

### Gotcha 4: Empty Lists Need Type Annotations

```roc
# ❌ Can't infer type
# bytes = []

# ✅ Must annotate
bytes : List(U8) = []

# ✅ Or let non-empty list infer
bytes = [0, 1, 2]  # Infers List(I64) or similar
```

### Gotcha 5: Use Prefix to Create, Bare in Match

For module types (not local types), use prefix to create, bare tags in patterns:

```roc
# Module type (like Try)
result = Try.Ok(42)  # Need Try.Ok

match result {
    Ok(value) => "ok"  # Bare Ok in match - no prefix
    Err(e) => "err"
}
```

For local types (defined in same module), bare tags everywhere:

```roc
# Local type definition
Color = [Red, Green, Blue]
c = Red  # Bare for creation

match c {
    Red => "red"  # Bare in match
}
```

## Checklist: Implementing Type-Safe Wrappers

When you need type-safe wrappers for FFI or validation:

- [ ] **Use `:= [Wrapper(T)]`** for public wrapper types
- [ ] **Validate in constructor** - Return `Try(Wrapper, [InvalidLength])`
- [ ] **Unwrap with `match`** for FFI calls
- [ ] **Consider helper functions** for frequently used unwraps
- [ ] **Never use `::`** for exported wrapper types
- [ ] **Document length requirements** in comments
- [ ] **Handle empty lists** as failure (common FFI pattern)
- [ ] **Use descriptive tag names** like `DigestBytes`, `SecretKeyBytes`

## When NOT to Use Type Wrappers

- Internal functions where `List(U8)` is clear enough
- Performance-critical inner loops (unwrap once, not in loops)
- Generic code that works on any `List(T)`
- When you genuinely want type interchangeability (use `=`)

## Summary

**For FFI wrappers and validation, use nominal types with single-variant tag unions:**

```roc
Digest := [DigestBytes(List(U8))]

make_digest : List(U8) -> Try(Digest, [InvalidLength])
make_digest = |bytes|
    match List.len(bytes) {
        32 => Ok(DigestBytes(bytes))
        _ => Err(InvalidLength)
    }
```

This pattern gives you:
- ✅ Type safety (can't confuse `Digest` with `SecretKey`)
- ✅ Length validation (enforced at construction)
- ✅ Public API (exportable from modules)
- ✅ FFI integration (unwrap to `List(U8)` for host calls)

The verbosity of pattern matching is a feature, not a bug - it makes FFI boundaries explicit and prevents real bugs.
