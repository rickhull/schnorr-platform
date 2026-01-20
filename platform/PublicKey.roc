## A secp256k1 public key is exactly 32 bytes (x-only)
##
## Use PublicKey.create to construct from raw bytes (validates length)
## Use .bytes() method to extract for FFI calls
PublicKey := [PublicKeyBytes(List(U8)), ..].{
    ## Create a PublicKey from raw bytes with validation
    ##
    ## Returns Ok(PublicKey) if input is exactly 32 bytes
    ## Returns Err(InvalidLength) otherwise
    create : List(U8) -> Try(PublicKey, [InvalidLength(U8, U64)])
    create = |bytes|
        match List.len(bytes) {
            32 => Ok(PublicKeyBytes(bytes))
            len => Err(InvalidLength(32, len))
        }

    ## Extract the underlying List(U8) for FFI calls
    bytes : PublicKey -> List(U8)
    bytes = |PublicKeyBytes(b)| b
}

## Tests
expect match PublicKey.create(List.repeat(0xDD, 32)) {
    Ok(_) => Bool.True
    Err(_) => Bool.False
}
