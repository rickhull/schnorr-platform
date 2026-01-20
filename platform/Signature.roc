## A Schnorr signature is exactly 64 bytes (32-byte r + 32-byte s)
##
## Use Signature.create to construct from raw bytes (validates length)
## Use .bytes() method to extract for FFI calls
Signature := [SignatureBytes(List(U8)), ..].{
    ## Create a Signature from raw bytes with validation
    ##
    ## Returns Ok(Signature) if input is exactly 64 bytes
    ## Returns Err(InvalidLength) otherwise
    create : List(U8) -> Try(Signature, [InvalidLength(U8, U64)])
    create = |bytes|
        match List.len(bytes) {
            64 => Ok(SignatureBytes(bytes))
            len => Err(InvalidLength(64, len))
        }

    ## Extract the underlying List(U8) for FFI calls
    bytes : Signature -> List(U8)
    bytes = |SignatureBytes(b)| b
}

## Tests
expect match Signature.create(List.repeat(0xAB, 64)) {
    Ok(_) => Bool.True
    Err(_) => Bool.False
}

expect match Signature.create([1, 2, 3]) {
    Ok(_) => Bool.False
    Err(_) => Bool.True
}

expect match Signature.create(List.repeat(0xAB, 64)) {
    Ok(s) => List.len(s.bytes()) == 64
    Err(_) => Bool.False
}
