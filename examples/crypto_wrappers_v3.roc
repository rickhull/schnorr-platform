## Crypto Type Wrappers - Version 3: Sign Operation
##
## Build on v2 by adding sign! and proper error handling.

app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Host

## ============================================================================
## Types
## ============================================================================

Digest := [DigestBytes(List(U8))]
SecretKey := [SecretKeyBytes(List(U8))]
PublicKey := [PublicKeyBytes(List(U8))]
Signature := [SignatureBytes(List(U8))]  # NEW

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
## Host operations
##
## KEY: Don't overly constrain error types - let compiler infer
## ============================================================================

pubkey! : SecretKey => PublicKey  # Simplified for now
pubkey! = |sk|
    match sk {
        SecretKeyBytes(sk_bytes) => {
            result = Host.pubkey!(sk_bytes)
            match List.len(result) {
                32 => PublicKeyBytes(result)
                _ => PublicKeyBytes([])  # Empty on failure
            }
        }
    }

sign! : SecretKey, Digest => Signature  # Simplified for now
sign! = |sk, digest|
    match sk {
        SecretKeyBytes(sk_bytes) =>
            match digest {
                DigestBytes(digest_bytes) => {
                    result = Host.sign!(sk_bytes, digest_bytes)
                    match List.len(result) {
                        64 => SignatureBytes(result)
                        _ => SignatureBytes([])  # Empty on failure
                    }
                }
            }
    }

## ============================================================================
## Demo
## ============================================================================

main! = |_args| {
    Stdout.line!("=== Crypto Wrappers v3: Sign Operation ===")
    Stdout.line!("")

    Stdout.line!("1. Creating secret key and digest...")
    sk_bytes = List.repeat(0, 32)
    digest_bytes = List.repeat(170, 32)

    sk_result = make_secret_key!(sk_bytes)
    match sk_result {
        Ok(sk) => {
            Stdout.line!("   ✓ Secret key created")

            digest_result = make_digest!(digest_bytes)
            match digest_result {
                Ok(digest) => {
                    Stdout.line!("   ✓ Digest created")

                    Stdout.line!("")
                    Stdout.line!("2. Signing digest...")
                    sig = sign!(sk, digest)

                    ## Unwrap to check
                    match sig {
                        SignatureBytes(sig_bytes) => {
                            match List.len(sig_bytes) {
                                0 => Stdout.line!("   Note: Failed (all-zero key)")
                                64 => Stdout.line!("   ✓ Signature is 64 bytes")
                                _ => Stdout.line!("   ✗ Unexpected length")
                            }
                        }
                    }
                }
                Err(_) => {
                    Stdout.line!("   ✗ Failed to create digest")
                }
            }
        }
        Err(_) => {
            Stdout.line!("   ✗ Failed to create secret key")
        }
    }

    Stdout.line!("")
    Stdout.line!("=== v3 Summary ===")
    Stdout.line!("✓ Added Signature type")
    Stdout.line!("✓ Added sign! operation")
    Stdout.line!("✓ Multiple unwraps working (sk + digest)")
    Stdout.line!("✓ Pattern: unwrap -> Host -> validate -> rewrap")
    Stdout.line!("✓ Next: Add verify! operation")

    Ok({})
}
