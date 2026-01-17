app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Host
import pf.Sha256

main! = |_args| {
    # Use a valid secp256k1 secret key (32 bytes, value 1)
    secret_key = [
        0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    ]

    # Test pubkey! - derive public key from secret key
    pubkey = Host.pubkey!(secret_key)
    pubkey_len = List.len(pubkey)

    match pubkey_len {
        32 => Stdout.line!("✓ Host.pubkey! returned 32 bytes"),
        _ => Stdout.line!("✗ Host.pubkey! returned ${Str.inspect(pubkey_len)} bytes (expected 32)"),
    }

    # Test sign! - sign a message
    msg = "Hello, Nostr!"
    msg_digest = Sha256.binary!(msg)
    sig = Host.sign!(secret_key, msg_digest)
    sig_len = List.len(sig)

    match sig_len {
        64 => Stdout.line!("✓ Host.sign! returned 64 bytes"),
        _ => Stdout.line!("✗ Host.sign! returned ${Str.inspect(sig_len)} bytes (expected 64)"),
    }

    # Test verify! - verify the signature
    is_valid = Host.verify!(pubkey, msg_digest, sig)

    match is_valid {
        True => Stdout.line!("✓ Host.verify! signature is valid"),
        False => Stdout.line!("✗ Host.verify! signature is invalid"),
    }

    Ok({})
}
