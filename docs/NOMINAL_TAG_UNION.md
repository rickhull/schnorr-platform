# Type-Safe Wrappers with Nominal Tag Unions

## Problem

When working with FFI boundaries, we need to:
1. **Enforce length constraints** - SecretKey must be exactly 32 bytes
2. **Prevent type confusion** - Can't pass a Signature where a PublicKey is expected
3. **Unwrap for FFI calls** - Extract `List(U8)` to pass to host functions

Naive approach using `List(U8)` everywhere is error-prone:
```roc
# Easy to mix up types!
sign!(secret_key, public_key)  # Oops! Should be digest, not public_key
```

## Solution: Nominal Tag Unions with Methods

Roc's nominal tag unions (`:=`) let us create distinct types with associated methods. This is the same pattern used by `Bool` and `Try` in the standard library.

### Complete Implementation

```roc
## Type-safe wrappers for cryptographic types
##
## Each type is a nominal tag union (:=) with:
## - Single variant wrapping List(U8)
## - Methods for construction, validation, and extraction
## - Open (..) for compatibility with Try.Ok

PublicKey := [PublicKeyBytes(List(U8)), ..].{
    ## Create from raw bytes with validation
    ##
    ## Returns Ok(PublicKey) if input is exactly 32 bytes
    ## Returns Err(InvalidLength) otherwise
    from_bytes : List(U8) -> Try(PublicKey, [InvalidLength(U8, U64)])
    from_bytes = |bytes|
        match List.len(bytes) {
            32 => Ok(PublicKeyBytes(bytes))
            len => Err(InvalidLength(32, len))
        }

    ## Extract the underlying List(U8)
    ##
    ## Use this to pass to host functions:
    ## Host.pubkey!(sk.bytes())
    bytes : PublicKey -> List(U8)
    bytes = |PublicKeyBytes(b)| b

    ## Get the length in bytes
    len : PublicKey -> U64
    len = |pk| List.len(pk.bytes())

    ## Validate the key is exactly 32 bytes
    is_valid : PublicKey -> Bool
    is_valid = |pk| pk.len() == 32
}

SecretKey := [SecretKeyBytes(List(U8)), ..].{
    ## Create from raw bytes with validation
    from_bytes : List(U8) -> Try(SecretKey, [InvalidLength(U8, U64)])
    from_bytes = |bytes|
        match List.len(bytes) {
            32 => Ok(SecretKeyBytes(bytes))
            len => Err(InvalidLength(32, len))
        }

    ## Extract the underlying List(U8)
    bytes : SecretKey -> List(U8)
    bytes = |SecretKeyBytes(b)| b

    ## Get the length in bytes
    len : SecretKey -> U64
    len = |sk| List.len(sk.bytes())

    ## Derive public key from this secret key
    to_public_key! : SecretKey => Try(PublicKey, [DerivationFailed])
    to_public_key! = |sk| {
        result = Host.pubkey!(sk.bytes())
        match List.len(result) {
            0 => Err(DerivationFailed)
            32 => PublicKey.from_bytes(result)
            _ => Err(DerivationFailed)
        }
    }
}

Signature := [SignatureBytes(List(U8)), ..].{
    ## Create from raw bytes with validation
    from_bytes : List(U8) -> Try(Signature, [InvalidLength(U8, U64)])
    from_bytes = |bytes|
        match List.len(bytes) {
            64 => Ok(SignatureBytes(bytes))
            len => Err(InvalidLength(64, len))
        }

    ## Extract the underlying List(U8)
    bytes : Signature -> List(U8)
    bytes = |SignatureBytes(b)| b

    ## Get the length in bytes
    len : Signature -> U64
    len = |sig| List.len(sig.bytes())

    ## Validate the signature is exactly 64 bytes
    is_valid : Signature -> Bool
    is_valid = |sig| sig.len() == 64
}

Digest := [DigestBytes(List(U8)), ..].{
    ## Create from raw bytes with validation
    from_bytes : List(U8) -> Try(Digest, [InvalidLength(U8, U64)])
    from_bytes = |bytes|
        match List.len(bytes) {
            32 => Ok(DigestBytes(bytes))
            len => Err(InvalidLength(32, len))
        }

    ## Extract the underlying List(U8)
    bytes : Digest -> List(U8)
    bytes = |DigestBytes(b)| b

    ## Get the length in bytes
    len : Digest -> U64
    len = |digest| List.len(digest.bytes())
}
```

## How It Works

### 1. Type Safety at Compile Time

```roc
## These are DIFFERENT types - compiler prevents mixing them up
only_takes_pk : PublicKey -> Str
only_takes_pk = |_pk| "public key"

sk : SecretKey = ...
pk : PublicKey = ...

only_takes_pk(sk)  # COMPILER ERROR! SecretKey ≠ PublicKey
only_takes_pk(pk)  # ✓ OK
```

### 2. Validation at Construction Time

```roc
## Invalid length - returns error
result = SecretKey.from_bytes([1, 2, 3])
match result {
    Ok(sk) => Stdout.line!("Got secret key")
    Err(InvalidLength(expected, actual)) =>
        Stdout.line!("Expected ${expected.to_str()}, got ${actual.to_str()}")
}
```

### 3. Unwrap for FFI Calls

```roc
## Call host functions with .bytes()
sign_and_verify! = |sk_bytes, msg| {
    ## Create typed wrapper
    sk_result = SecretKey.from_bytes(sk_bytes)

    match sk_result {
        Ok(sk) => {
            ## Derive public key
            pk_result = sk.to_public_key!()

            match pk_result {
                Ok(pk) => {
                    ## Hash message
                    digest_bytes = Sha256.hex!(msg)
                    digest_result = Digest.from_bytes(digest_bytes.to_utf8())

                    match digest_result {
                        Ok(digest) => {
                            ## Sign - unwrap with .bytes()
                            sig_bytes = Host.sign!(sk.bytes(), digest.bytes())
                            sig_result = Signature.from_bytes(sig_bytes)

                            match sig_result {
                                Ok(sig) => {
                                    ## Verify - unwrap all with .bytes()
                                    is_valid = Host.verify!(
                                        pk.bytes(),
                                        digest.bytes(),
                                        sig.bytes()
                                    )
                                    Stdout.line!("Valid: ${is_valid.to_str()}")
                                }
                                Err(e) => Stdout.line!("Invalid signature")
                            }
                        }
                        Err(_) => Stdout.line!("Invalid digest")
                        # No BytesError - from_bytes returns Try(Digest, [InvalidLength])
                    }
                }
                Err(_) => Stdout.line!("Failed to derive public key")
                # No InvalidLengthError - to_public_key! returns Try(PublicKey, [DerivationFailed])
                # and PublicKey.from_bytes returns Try(PublicKey, [InvalidLength])
                # but we already validated length with List.len(result) == 32
                # and PublicKey.from_bytes will succeed for 32-byte input
                # Actually wait, let me check this more carefully...
                #
                # result = Host.pubkey!(sk.bytes()) returns List(U8)
                # We check List.len(result) == 32, so it's 32 bytes
                # PublicKey.from_bytes(result) with 32 bytes => Ok(PublicKeyBytes(result))
                # So this branch can only return Ok, not Err(InvalidLength)
                # So the Err case here is actually unreachable
                #
                # But the compiler doesn't know that, so we still need to handle it
            }
        }
        Err(_) => Stdout.line!("Invalid secret key")
    }
    Ok({})
}
```

## Why This Pattern?

### ✅ Nominal Tag Unions (`:=`)

- **Distinct types**: `PublicKey` ≠ `SecretKey` even though both wrap `List(U8)`
- **Can have methods**: Define behavior in `.{ }` block
- **Always cross FFI boundary**: Safe to use with host functions

### ✅ Single Variant `[Wrapper(T)]`

- **Type-safe**: Can't confuse different byte array types
- **Unwrappable**: Pattern matching extracts the underlying `List(U8)`
- **Idiomatic**: Same pattern as `Bool` and `Try` in stdlib

### ✅ Methods on Types

- **Clean API**: `pk.bytes()` instead of `to_bytes(pk)`
- **Encapsulation**: Validation logic stays with the type
- **Discoverability**: Methods appear via dot notation

### ✅ Open Tag Unions (`..`)

- **Try compatible**: Works with `Try.Ok(PublicKey)`
- **Future-proof**: Can extend with new variants if needed

## Comparison: Why Not Other Approaches?

### ❌ Opaque Types (`::`)

```roc
PublicKey :: List(U8)  # Can't convert List(U8) to PublicKey!
```

Opaque types hide implementation - you can't convert between `T` and `MyType :: T`. Great for hiding internals, bad for FFI wrappers.

### ❌ Structural Types (`=`)

```roc
PublicKey = [PublicKeyBytes(List(U8))]
SecretKey = [SecretKeyBytes(List(U8))]
```

These are the **same type** structurally! Compiler treats them as interchangeable, defeating type safety.

### ❌ Bare `List(U8)`

```roc
pubkey! : List(U8) => List(U8)
sign! : List(U8), List(U8) => List(U8)
```

Easy to pass wrong byte array to wrong function. No validation. No type safety.

## Complete Example Module

```roc
## Cryptographic operations with type-safe wrappers

import Host

## Wrapper types (defined above)
PublicKey := [PublicKeyBytes(List(U8)), ..].{
    from_bytes : List(U8) -> Try(PublicKey, [InvalidLength(U8, U64)])
    from_bytes = |bytes|
        match List.len(bytes) {
            32 => Ok(PublicKeyBytes(bytes))
            len => Err(InvalidLength(32, len))
        }

    bytes : PublicKey -> List(U8)
    bytes = |PublicKeyBytes(b)| b
}

SecretKey := [SecretKeyBytes(List(U8)), ..].{
    from_bytes : List(U8) -> Try(SecretKey, [InvalidLength(U8, U64)])
    from_bytes = |bytes|
        match List.len(bytes) {
            32 => Ok(SecretKeyBytes(bytes))
            len => Err(InvalidLength(32, len))
        }

    bytes : SecretKey -> List(U8)
    bytes = |SecretKeyBytes(b)| b
}

Signature := [SignatureBytes(List(U8)), ..].{
    from_bytes : List(U8) -> Try(Signature, [InvalidLength(U8, U64)])
    from_bytes = |bytes|
        match List.len(bytes) {
            64 => Ok(SignatureBytes(bytes))
            len => Err(InvalidLength(64, len))
        }

    bytes : Signature -> List(U8)
    bytes = |SignatureBytes(b)| b
}

Digest := [DigestBytes(List(U8)), ..].{
    from_bytes : List(U8) -> Try(Digest, [InvalidLength(U8, U64)])
    from_bytes = |bytes|
        match List.len(bytes) {
            32 => Ok(DigestBytes(bytes))
            len => Err(InvalidLength(32, len))
        }

    bytes : Digest -> List(U8)
    bytes = |DigestBytes(b)| b
}

## Error types
InvalidLength := [InvalidLength(U8, U64)]
DerivationFailed := [DerivationFailed]

## High-level API using typed wrappers
Crypto := [].{
    ## Derive public key from secret key
    pubkey! : SecretKey => Try(PublicKey, [DerivationFailed])
    pubkey! = |sk| {
        result = Host.pubkey!(sk.bytes())
        match List.len(result) {
            0 => Err(DerivationFailed)
            32 => PublicKey.from_bytes(result)  # Always Ok for 32-byte input
            _ => Err(DerivationFailed)
        }
    }

    ## Sign a digest with secret key
    sign! : SecretKey, Digest => Try(Signature, [DerivationFailed])
    sign! = |sk, digest| {
        result = Host.sign!(sk.bytes(), digest.bytes())
        match List.len(result) {
            0 => Err(DerivationFailed)
            64 => Signature.from_bytes(result)  # Always Ok for 64-byte input
            _ => Err(DerivationFailed)
        }
    }

    ## Verify a signature
    verify! : PublicKey, Digest, Signature => Bool
    verify! = |pk, digest, sig| {
        Host.verify!(pk.bytes(), digest.bytes(), sig.bytes())
    }
}

## Usage
main! = |_args| {
    ## Secret key (32 bytes of zeros for example - use real key in production!)
    sk_bytes = List.pad(32, 0)

    match SecretKey.from_bytes(sk_bytes) {
        Ok(sk) => {
            ## Derive public key
            match Crypto.pubkey!(sk) {
                Ok(pk) => {
                    ## Create digest
                    msg = "Hello, Nostr!"
                    digest_bytes = Sha256.hex!(msg).to_utf8()

                    match Digest.from_bytes(digest_bytes) {
                        Ok(digest) => {
                            ## Sign
                            match Crypto.sign!(sk, digest) {
                                Ok(sig) => {
                                    ## Verify
                                    is_valid = Crypto.verify!(pk, digest, sig)
                                    Stdout.line!("Signature valid: ${is_valid.to_str()}")
                                }
                                Err(_) => Stdout.line!("Signing failed")
                            }
                        }
                        Err(_) => Stdout.line!("Invalid digest")
                    }
                }
                Err(_) => Stdout.line!("Failed to derive public key")
            }
        }
        Err(_) => Stdout.line!("Invalid secret key")
    }

    Ok({})
}
```

## Summary

| Aspect | Approach |
|--------|----------|
| **Type definition** | `Type := [Variant(List(U8)), ..]` |
| **Construction** | `Type.from_bytes(list)` - validates length |
| **Extraction** | `wrapper.bytes()` - returns `List(U8)` |
| **Type safety** | Compile-time error: `SecretKey` ≠ `PublicKey` |
| **FFI boundary** | Call `Host.func!(wrapper.bytes(), ...)` |
| **Idiomatic** | Same pattern as `Bool`, `Try` in stdlib |

This pattern gives you:
- ✅ **Type safety** - can't mix up different byte arrays
- ✅ **Validation** - length enforced at construction
- ✅ **Clean API** - methods on types, not separate functions
- ✅ **FFI compatible** - unwrap with `.bytes()` for host calls
