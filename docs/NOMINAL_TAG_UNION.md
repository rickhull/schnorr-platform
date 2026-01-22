# Type-Safe Wrappers with Nominal Tag Unions

## Problem

Working with FFI boundaries often means passing raw `List(U8)` byte arrays. This is error-prone:

```roc
# Easy to mix up types!
sign!(secret_key, public_key)  # Oops! Should be digest, not public_key
```

## Solution: Nominal Tag Unions

Roc's `:=` creates distinct types with methods. Pattern from `Bool` and `Try` in stdlib.

### Pattern

```roc
PublicKey := [PublicKeyBytes(List(U8)), ..].{
    ## Create from raw bytes with validation
    create : List(U8) -> Try(PublicKey, [InvalidLength(U8, U64)])
    create = |bytes|
        match List.len(bytes) {
            32 => Ok(PublicKeyBytes(bytes))
            len => Err(InvalidLength(32, len))
        }

    ## Extract for FFI calls
    bytes : PublicKey -> List(U8)
    bytes = |PublicKeyBytes(b)| b
}
```

### Key Points

| Aspect | Implementation |
|--------|----------------|
| **Type** | `Type := [Variant(List(U8)), ..]` (nominal, distinct types) |
| **Construct** | `Type.create(list)` - validates length |
| **Extract** | `wrapper.bytes()` - returns `List(U8)` |
| **FFI call** | `Host.func!(wrapper.bytes(), ...)` |

### Why `:=` not `=` or `::`?

| Syntax | Types are distinct? | Can unwrap? |
|--------|-------------------|-------------|
| `MyType = T` | ❌ No (structural) | N/A |
| `MyType :: T` | ✅ Yes | ❌ No (opaque) |
| `MyType := [Variant(T)]` | ✅ Yes | ✅ Yes (pattern match) |

`:=` gives distinct types **and** lets you unwrap for FFI.

## Actual Usage

See `platform/PublicKey.roc`, `platform/SecretKey.roc`, `platform/Signature.roc`, `platform/Digest.roc` for the real implementations.

Example from `platform/PublicKey.roc`:

```roc
PublicKey := [PublicKeyBytes(List(U8)), ..].{
    create : List(U8) -> Try(PublicKey, [InvalidLength(U8, U64)])
    create = |bytes|
        match List.len(bytes) {
            32 => Ok(PublicKeyBytes(bytes))
            len => Err(InvalidLength(32, len))
        }

    bytes : PublicKey -> List(U8)
    bytes = |PublicKeyBytes(b)| b
}

## Tests
expect match PublicKey.create(List.repeat(0xDD, 32)) {
    Ok(_) => Bool.True
    Err(_) => Bool.False
}
```

All wrappers follow this same pattern with only the length varying (32 for keys/digests, 64 for signatures).
