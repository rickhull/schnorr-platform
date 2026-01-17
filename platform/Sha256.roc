Sha256 := [].{
    ## Compute SHA-256 hash and return as 32-byte binary List(U8).
    ##
    ## ```roc
    ## Sha256.binary!("hello world")
    ## # => List(U8) with 32 bytes
    ## ```
    binary! : Str => List(U8)

    ## Compute SHA-256 hash and return as lowercase hexadecimal string.
    ##
    ## ```roc
    ## Sha256.hex!("hello world")
    ## # => "b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9"
    ## ```
    hex! : Str => Str
}
