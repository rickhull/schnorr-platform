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

    # Test 1: pubkey! returns 32 bytes for valid secret key
    pubkey = Host.pubkey!(secret_key)
    expect List.len(pubkey) == 32

    # Test 2: pubkey! returns empty list for invalid length secret key
    short_key = [0x01]
    short_pubkey = Host.pubkey!(short_key)
    expect List.len(short_pubkey) == 0

    # Test 3: pubkey! returns empty list for wrong length secret key
    long_key = List.repeat(0xFF_.U8, 33)
    long_pubkey = Host.pubkey!(long_key)
    expect List.len(long_pubkey) == 0

    # Test 4: sign! returns 64 bytes for valid input
    msg = "Hello, Nostr!"
    msg_digest = Sha256.binary!(msg)
    sig = Host.sign!(secret_key, msg_digest)
    expect List.len(sig) == 64

    # Test 5: sign! returns empty list for wrong length digest
    bad_digest = List.repeat(0_.U8, 31)
    bad_sig = Host.sign!(secret_key, bad_digest)
    expect List.len(bad_sig) == 0

    # Test 6: verify! returns True for valid signature
    is_valid = Host.verify!(pubkey, msg_digest, sig)
    expect is_valid == True

    # Test 7: verify! returns False for invalid signature
    fake_sig = List.repeat(0xFF_.U8, 64)
    is_fake_valid = Host.verify!(pubkey, msg_digest, fake_sig)
    expect is_fake_valid == False

    # Test 8: verify! returns False for wrong length signature
    short_sig = List.repeat(0_.U8, 63)
    is_short_sig_valid = Host.verify!(pubkey, msg_digest, short_sig)
    expect is_short_sig_valid == False

    Stdout.line!("✓ All Host tests passed!")

    Ok({})
}
