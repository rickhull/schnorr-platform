## A SHA-256 digest is exactly 32 bytes
##
## Use Digest.create to construct from raw bytes (validates length)
## Use .bytes() method to extract for FFI calls to Host.sign! or Host.verify!
Digest := [DigestBytes(List(U8)), ..].{
    ## Create a Digest from raw bytes with validation
    ##
    ## Returns Ok(Digest) if input is exactly 32 bytes
    ## Returns Err(InvalidLength) otherwise
    create : List(U8) -> Try(Digest, [InvalidLength(U8, U64)])
    create = |bytes|
        match List.len(bytes) {
            32 => Ok(DigestBytes(bytes))
            len => Err(InvalidLength(32, len))
        }

    ## Extract the underlying List(U8) for FFI calls
    bytes : Digest -> List(U8)
    bytes = |DigestBytes(b)| b
}
