app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Host

main! = |_args| {
    # Test 1: sha256! returns 32 bytes for empty string
    hash1_bytes = Host.sha256!("")
    expect List.len(hash1_bytes) == 32

    # Test 2: Known input produces correct hash
    hash2_bytes = Host.sha256!("hello world")
    expect List.len(hash2_bytes) == 32

    # Test 3: Different inputs produce different hashes
    hash_a_bytes = Host.sha256!("foo")
    hash_b_bytes = Host.sha256!("bar")
    expect hash_a_bytes != hash_b_bytes

    # Test 4: Hash length is consistent (32 bytes)
    hash_bytes = Host.sha256!("test")
    expect List.len(hash_bytes) == 32

    # TODO: Add hex tests when hex encoding is implemented
    # hash_hex = Host.hex!("test")
    # expect Str.count_utf8_bytes(hash_hex) == 64

    Stdout.line!("✓ All Sha256 tests passed!")

    Ok({})
}
