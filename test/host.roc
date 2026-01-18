app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Host
import pf.Sha256

main! = |_args| {
    # Use a valid secp256k1 secret key (32 bytes, value 1)
    secret_key = [
        0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    ]

    # Test pubkey! - derive public key from secret key
    pubkey = Host.pubkey!(secret_key)
    expect List.len(pubkey) == 32

    # Test sign! - sign a message
    msg = "Hello, Nostr!"
    msg_digest = Sha256.binary!(msg)
    sig = Host.sign!(secret_key, msg_digest)
    expect List.len(sig) == 64

    # Test verify! - verify the signature
    is_valid = Host.verify!(pubkey, msg_digest, sig)
    expect is_valid == True

    Stdout.line!("✓ All Host tests passed!")

    Ok({})
}
