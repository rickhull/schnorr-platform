Host := [].{
    ## Derive public key from 32-byte secret key
    ## Returns empty list on failure, 32-byte public key on success
    ##
    ## ```roc
    ## secret_key = List.repeat(0, 32)
    ## pubkey = Host.pubkey!(secret_key)
    ## ## Returns List(U8) with 32 bytes
    ## ```
    pubkey! : List(U8) => List(U8)

    ## Sign 32-byte digest with secret key
    ## Returns empty list on failure, 64-byte signature on success
    ##
    ## ```roc
    ## sig = Host.sign!(secret_key, digest)
    ## ## Returns List(U8) with 64 bytes
    ## ```
    sign! : List(U8), List(U8) => List(U8)

    ## Verify Schnorr signature
    ## Returns true if valid, false if invalid
    ##
    ## ```roc
    ## is_valid = Host.verify!(pubkey, digest, signature)
    ## ## Returns Bool
    ## ```
    verify! : List(U8), List(U8), List(U8) => Bool

    ## Compute SHA-256 hash and return as 32-byte binary List(U8)
    ##
    ## Returns exactly 32 bytes
    ##
    ## ```roc
    ## digest = Host.sha256!("hello world")
    ## ## Returns List(U8) with 32 bytes
    ## ```
    sha256! : Str => List(U8)
}
