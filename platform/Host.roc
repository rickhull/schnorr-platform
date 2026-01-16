Host := [].{
    ## Derive public key from 32-byte secret key
    ## Returns empty list on failure, 32-byte public key on success
    pubkey! : List U8 => List U8

    ## Sign 32-byte digest with secret key
    ## Returns empty list on failure, 64-byte signature on success
    sign! : List U8, List U8 => List U8

    ## Verify Schnorr signature
    ## Returns true if valid, false if invalid
    verify! : List U8, List U8, List U8 => Bool
}
