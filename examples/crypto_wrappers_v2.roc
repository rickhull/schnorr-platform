## Crypto Type Wrappers - Version 2: Add Rewrapping
##
## Build on v1 by adding PublicKey type and rewrapping Host results.

app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Host

## ============================================================================
## Types
## ============================================================================

Digest := [DigestBytes(List(U8))]
SecretKey := [SecretKeyBytes(List(U8))]
PublicKey := [PublicKeyBytes(List(U8))]  # NEW

## ============================================================================
## Constructors
## ============================================================================

make_digest! : List(U8) => Try(Digest, [InvalidLength])
make_digest! = |bytes|
    match List.len(bytes) {
        32 => Ok(DigestBytes(bytes))
        _len => {
            Stdout.line!("✗ Invalid digest length")
            Err(InvalidLength)
        }
    }

make_secret_key! : List(U8) => Try(SecretKey, [InvalidLength])
make_secret_key! = |bytes|
    match List.len(bytes) {
        32 => Ok(SecretKeyBytes(bytes))
        _len => {
            Stdout.line!("✗ Invalid secret key length")
            Err(InvalidLength)
        }
    }

## ============================================================================
## Host operations with rewrapping
##
## Pattern: unwrap -> call Host -> validate -> rewrap
## ============================================================================

pubkey! : SecretKey => PublicKey  # Simplified: no error handling for now
pubkey! = |sk|
    match sk {
        SecretKeyBytes(sk_bytes) => {
            result = Host.pubkey!(sk_bytes)
            PublicKeyBytes(result)  # Just rewrap for now (even if empty)
        }
    }

## ============================================================================
## Demo
## ============================================================================

main! = |_args| {
    Stdout.line!("=== Crypto Wrappers v2: Rewrapping ===")
    Stdout.line!("")

    Stdout.line!("1. Creating secret key...")
    sk_bytes = List.repeat(0, 32)

    sk_result = make_secret_key!(sk_bytes)
    match sk_result {
        Ok(sk) => {
            Stdout.line!("   ✓ Secret key created")

            Stdout.line!("")
            Stdout.line!("2. Deriving public key...")
            pk = pubkey!(sk)  # Returns PublicKey wrapper

            ## Unwrap to check length
            match pk {
                PublicKeyBytes(pk_bytes) => {
                    match List.len(pk_bytes) {
                        0 => Stdout.line!("   Note: Host returned empty (all-zero key)")
                        32 => Stdout.line!("   ✓ Got 32-byte public key")
                        _ => Stdout.line!("   ✗ Unexpected length")
                    }
                }
            }
        }
        Err(_) => {
            Stdout.line!("   ✗ Failed")
        }
    }

    Stdout.line!("")
    Stdout.line!("=== v2 Summary ===")
    Stdout.line!("✓ Added PublicKey type")
    Stdout.line!("✓ Rewrapping Host results works")
    Stdout.line!("✓ Type-safe: pubkey! returns PublicKey, not List(U8)")
    Stdout.line!("✓ Next: Add proper error handling")

    Ok({})
}
