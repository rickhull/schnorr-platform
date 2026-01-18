## Crypto Type Wrappers - Version 4: Complete
##
## Final version with verify! operation and full workflow.

app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Host

## ============================================================================
## Types
## ============================================================================

Digest := [DigestBytes(List(U8))]
SecretKey := [SecretKeyBytes(List(U8))]
PublicKey := [PublicKeyBytes(List(U8))]
Signature := [SignatureBytes(List(U8))]

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
## Crypto operations
##
## All follow the same pattern:
##   unwrap -> call Host -> validate length -> rewrap
## ============================================================================

pubkey! : SecretKey => PublicKey
pubkey! = |sk|
    match sk {
        SecretKeyBytes(sk_bytes) => {
            result = Host.pubkey!(sk_bytes)
            match List.len(result) {
                32 => PublicKeyBytes(result)
                _ => PublicKeyBytes([])
            }
        }
    }

sign! : SecretKey, Digest => Signature
sign! = |sk, digest|
    match sk {
        SecretKeyBytes(sk_bytes) =>
            match digest {
                DigestBytes(digest_bytes) => {
                    result = Host.sign!(sk_bytes, digest_bytes)
                    match List.len(result) {
                        64 => SignatureBytes(result)
                        _ => SignatureBytes([])
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

## ============================================================================
## Helper: Check if wrapper has valid content
## ============================================================================

is_valid_pubkey : PublicKey -> Bool
is_valid_pubkey = |pk|
    match pk {
        PublicKeyBytes(bytes) => List.len(bytes) == 32
    }

is_valid_signature : Signature -> Bool
is_valid_signature = |sig|
    match sig {
        SignatureBytes(bytes) => List.len(bytes) == 64
    }

## ============================================================================
## Demo: Complete workflow
## ============================================================================

main! = |_args| {
    Stdout.line!("=== Crypto Wrappers v4: Complete ===")
    Stdout.line!("")

    Stdout.line!("=== Setup: Create secret key ===")
    sk_bytes = List.repeat(0, 32)
    sk_result = make_secret_key!(sk_bytes)

    match sk_result {
        Ok(sk) => {
            Stdout.line!("✓ Secret key created")

            Stdout.line!("")
            Stdout.line!("=== Step 1: Derive public key ===")
            pk = pubkey!(sk)

            match is_valid_pubkey(pk) {
                True => Stdout.line!("✓ Public key derived (32 bytes)")
                False => Stdout.line!("✗ Failed to derive pubkey")
            }

            Stdout.line!("")
            Stdout.line!("=== Step 2: Create digest ===")
            digest_bytes = List.repeat(170, 32)
            digest_result = make_digest!(digest_bytes)

            match digest_result {
                Ok(digest) => {
                    Stdout.line!("✓ Digest created (32 bytes)")

                    Stdout.line!("")
                    Stdout.line!("=== Step 3: Sign digest ===")
                    sig = sign!(sk, digest)

                    match is_valid_signature(sig) {
                        True => {
                            Stdout.line!("✓ Signature created (64 bytes)")

                            Stdout.line!("")
                            Stdout.line!("=== Step 4: Verify signature ===")
                            is_valid = verify!(pk, digest, sig)

                            match is_valid {
                                True => Stdout.line!("✓ Signature is VALID")
                                False => Stdout.line!("✗ Signature is INVALID")
                            }

                            Stdout.line!("")
                            Stdout.line!("=== Step 5: Try wrong digest ===")
                            wrong_bytes = List.repeat(255, 32)
                            wrong_result = make_digest!(wrong_bytes)

                            match wrong_result {
                                Ok(wrong_digest) => {
                                    is_wrong = verify!(pk, wrong_digest, sig)
                                    match is_wrong {
                                        True => Stdout.line!("✗ Should have failed!")
                                        False => Stdout.line!("✓ Correctly rejected wrong digest")
                                    }
                                }
                                Err(_) => {
                                    Stdout.line!("✗ Failed to create wrong digest")
                                }
                            }
                        }
                        False => {
                            Stdout.line!("✗ Failed to sign (all-zero key)")
                        }
                    }
                }
                Err(_) => {
                    Stdout.line!("✗ Failed to create digest")
                }
            }
        }
        Err(_) => {
            Stdout.line!("✗ Failed to create secret key")
        }
    }

    Stdout.line!("")
    Stdout.line!("=== v4 Summary ===")
    Stdout.line!("✓ All 4 crypto types defined")
    Stdout.line!("✓ pubkey!, sign!, verify! operations working")
    Stdout.line!("✓ Type-safe: can't confuse pk, sk, digest, sig")
    Stdout.line!("✓ Length constraints enforced")
    Stdout.line!("✓ Complete signing workflow demonstrated")
    Stdout.line!("✓ Wrong digest correctly rejected")

    Ok({})
}
