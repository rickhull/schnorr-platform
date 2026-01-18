## Crypto Type Wrappers - Version 1: Basics
##
## Starting from the working type_wrappers_intro.roc
## and adding Host operations one step at a time.

app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Host

## ============================================================================
## Step 1: Define wrapper types (this works!)
## ============================================================================

Digest := [DigestBytes(List(U8))]
SecretKey := [SecretKeyBytes(List(U8))]

## ============================================================================
## Step 2: Simple constructors (from working example)
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
## Step 3: Add ONE Host operation - pubkey!
##
## Pattern: unwrap -> call Host -> check result -> rewrap
## ============================================================================

pubkey_demo! : SecretKey => List(U8)  # For now, just return List(U8)
pubkey_demo! = |sk|
    match sk {
        SecretKeyBytes(sk_bytes) => {
            result = Host.pubkey!(sk_bytes)
            result  # Return raw List(U8) for now
        }
    }

## ============================================================================
## Demo
## ============================================================================

main! = |_args| {
    Stdout.line!("=== Crypto Wrappers v1: Basics ===")
    Stdout.line!("")

    ## Create a secret key
    Stdout.line!("1. Creating secret key...")
    sk_bytes = List.repeat(0, 32)

    sk_result = make_secret_key!(sk_bytes)
    match sk_result {
        Ok(sk) => {
            Stdout.line!("   ✓ Secret key created")

            ## Call Host function (unwrap happens inside)
            Stdout.line!("")
            Stdout.line!("2. Calling Host.pubkey!...")
            pk_bytes = pubkey_demo!(sk)

            match List.len(pk_bytes) {
                32 => Stdout.line!("   ✓ Got 32-byte public key from Host")
                _ => Stdout.line!("   ✗ Unexpected pubkey length")
            }
        }
        Err(_) => {
            Stdout.line!("   ✗ Failed to create secret key")
        }
    }

    Stdout.line!("")
    Stdout.line!("=== v1 Summary ===")
    Stdout.line!("✓ Type definitions work")
    Stdout.line!("✓ Constructors with validation work")
    Stdout.line!("✓ Unwrap -> Host call pattern works")
    Stdout.line!("✓ Next: Add rewrapping of Host results")

    Ok({})
}
