app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Signature
import pf.Digest
import pf.PublicKey
import pf.SecretKey
import pf.Host

main! = |_args| {
    # Test 1: Signature.create accepts 64 bytes
    sig_bytes = List.repeat(0xAB, 64)
    sig_result = Signature.create(sig_bytes)
    is_sig_ok = match sig_result {
        Ok(_) => Bool.True
        Err(_) => Bool.False
    }
    expect is_sig_ok == Bool.True

    # Test 2: Signature.create rejects wrong length
    short_bytes = [1, 2, 3]
    short_result = Signature.create(short_bytes)
    is_short_err = match short_result {
        Ok(_) => Bool.False
        Err(_) => Bool.True
    }
    expect is_short_err == Bool.True

    # Test 3: Signature.bytes() returns correct length
    sig_bytes2 = List.repeat(0xAB, 64)
    sig_result2 = Signature.create(sig_bytes2)
    sig_len = match sig_result2 {
        Ok(s) => List.len(s.bytes())
        Err(_) => 0
    }
    expect sig_len == 64

    # Test 4: Digest.create accepts 32 bytes
    digest_bytes = List.repeat(0xCC, 32)
    digest_result = Digest.create(digest_bytes)
    is_digest_ok = match digest_result {
        Ok(_) => Bool.True
        Err(_) => Bool.False
    }
    expect is_digest_ok == Bool.True

    # Test 5: PublicKey.create accepts 32 bytes
    pubkey_bytes = List.repeat(0xDD, 32)
    pubkey_result = PublicKey.create(pubkey_bytes)
    is_pubkey_ok = match pubkey_result {
        Ok(_) => Bool.True
        Err(_) => Bool.False
    }
    expect is_pubkey_ok == Bool.True

    # Test 6: SecretKey.create accepts 32 bytes
    seckey_bytes = List.repeat(0xEE, 32)
    seckey_result = SecretKey.create(seckey_bytes)
    is_seckey_ok = match seckey_result {
        Ok(_) => Bool.True
        Err(_) => Bool.False
    }
    expect is_seckey_ok == Bool.True

    # Test 7: Integration with Host.sha256!
    hash = Host.sha256!("hello")
    digest_from_hash_result = Digest.create(hash)
    is_hash_ok = match digest_from_hash_result {
        Ok(_) => Bool.True
        Err(_) => Bool.False
    }
    expect is_hash_ok == Bool.True

    Stdout.line!("✓ All Crypto tests passed!")

    Ok({})
}
