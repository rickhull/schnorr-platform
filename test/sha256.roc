app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Sha256

main! = |_args| {
    # Test 1: Empty string hash
    hash1 = Sha256.hex!("")
    expect hash1 == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

    # Test 2: Known input produces known hash
    hash2 = Sha256.hex!("hello world")
    expect hash2 == "b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9"

    # Test 3: Different inputs produce different hashes
    hash_a = Sha256.hex!("foo")
    hash_b = Sha256.hex!("bar")
    expect hash_a != hash_b

    # Test 4: Hash length is consistent (64 hex chars)
    hash_result = Sha256.hex!("test")
    expect Str.count_utf8_bytes(hash_result) == 64

    # Test 5: binary! returns 32 bytes
    hash_bytes = Sha256.binary!("test")
    expect List.len(hash_bytes) == 32

    Stdout.line!("✓ All Sha256 tests passed!")

    Ok({})
}
