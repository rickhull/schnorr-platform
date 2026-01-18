## Type Wrappers Introduction
##
## This example demonstrates the single-variant tag union pattern
## for creating type-safe, length-constrained wrappers.
##
## Use case: Preventing type confusion when working with raw byte arrays
## at FFI boundaries or in cryptographic operations.

app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdout

## ============================================================================
## Type Definitions
##
## We use nominal types (:=) with single-variant tag unions.
## This creates distinct types that the compiler won't let you confuse.
##
## Key points:
## - := means nominal type (distinct from identical types)
## - [Wrapper(T)] is a single-variant tag union
## - Public across modules (can be exported)
## ============================================================================

Digest := [DigestBytes(List(U8))]
SecretKey := [SecretKeyBytes(List(U8))]

## ============================================================================
## Constructors with Validation
##
## Validate length at construction time.
## Once you have a Digest value, it's guaranteed to be 32 bytes.
##
## Using Try for error handling:
## - Ok(Digest) - valid, guaranteed to be 32 bytes
## - Err(InvalidLength) - wrong length
## ============================================================================

make_digest! : List(U8) => Try(Digest, [InvalidLength])
make_digest! = |bytes|
    match List.len(bytes) {
        32 => Ok(DigestBytes(bytes))
        len => {
            Stdout.line!("✗ Invalid digest length: got ${len.to_str()}, expected 32")
            Err(InvalidLength)
        }
    }

make_secret_key! : List(U8) => Try(SecretKey, [InvalidLength])
make_secret_key! = |bytes|
    match List.len(bytes) {
        32 => Ok(SecretKeyBytes(bytes))
        len => {
            Stdout.line!("✗ Invalid secret key length: got ${len.to_str()}, expected 32")
            Err(InvalidLength)
        }
    }

## ============================================================================
## Extractor Functions
##
## Unwrap the type to get back the raw List(U8).
## This is needed when calling FFI functions that expect List(U8).
## ============================================================================

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

## ============================================================================
## Demonstration
## ============================================================================

main! = |_args| {
    Stdout.line!("=== Type Wrappers Introduction ===")
    Stdout.line!("")

    ## Create a 32-byte digest (valid)
    Stdout.line!("1. Creating a valid 32-byte digest...")
    valid_bytes = List.repeat(42, 32)
    valid_result = make_digest!(valid_bytes)

    match valid_result {
        Ok(digest) => {
            extracted = to_digest_bytes(digest)
            Stdout.line!("   ✓ Digest created successfully")
            Stdout.line!("   ✓ Extracted ${List.len(extracted).to_str()} bytes")
        }
        Err(_) => {
            Stdout.line!("   ✗ Failed (shouldn't happen)")
        }
    }

    Stdout.line!("")

    ## Try to create a digest with wrong length (invalid)
    Stdout.line!("2. Creating an invalid 16-byte digest...")
    invalid_bytes = List.repeat(99, 16)
    invalid_result = make_digest!(invalid_bytes)

    match invalid_result {
        Ok(_) => {
            Stdout.line!("   ✗ Should have failed!")
        }
        Err(InvalidLength) => {
            Stdout.line!("   ✓ Correctly rejected wrong length")
        }
    }

    Stdout.line!("")

    ## Demonstrate type safety
    Stdout.line!("3. Type safety demonstration...")
    Stdout.line!("   Digest and SecretKey are different types")
    Stdout.line!("   The compiler prevents mixing them up")
    Stdout.line!("   ✓ Uncommenting the code below would be a TYPE ERROR:")
    Stdout.line!("   # secret_key : SecretKey = digest  # COMPILER ERROR!")

    Stdout.line!("")

    ## Show pattern matching ergonomics
    Stdout.line!("4. Pattern matching for unwrapping...")
    sk_bytes = List.repeat(255, 32)
    match make_secret_key!(sk_bytes) {
        Ok(_sk) => {
            Stdout.line!("   ✓ Unwrapped secret key")
            Stdout.line!("   ✓ Pattern matching makes the unwrap explicit")
        }
        Err(_) => {
            Stdout.line!("   ✗ Failed")
        }
    }

    Stdout.line!("")
    Stdout.line!("=== Summary ===")
    Stdout.line!("✓ Single-variant tag unions provide type safety")
    Stdout.line!("✓ Validation happens once at construction")
    Stdout.line!("✓ Pattern matching makes FFI boundaries explicit")
    Stdout.line!("✓ Compiler prevents type confusion")

    Ok({})
}
