## A secp256k1 secret key is exactly 32 bytes
##
## Use SecretKey.create to construct from raw bytes (validates length)
## Use .bytes() method to extract for FFI calls
SecretKey := [SecretKeyBytes(List(U8)), ..].{
    ## Create a SecretKey from raw bytes with validation
    ##
    ## Returns Ok(SecretKey) if input is exactly 32 bytes
    ## Returns Err(InvalidLength) otherwise
    create : List(U8) -> Try(SecretKey, [InvalidLength(U8, U64)])
    create = |bytes|
        match List.len(bytes) {
            32 => Ok(SecretKeyBytes(bytes))
            len => Err(InvalidLength(32, len))
        }

    ## Extract the underlying List(U8) for FFI calls
    bytes : SecretKey -> List(U8)
    bytes = |SecretKeyBytes(b)| b
}
