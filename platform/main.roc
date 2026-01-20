## PLATFORM COUPLING: main.roc ↔ host.zig
##
## The order of modules in `exposes` must match the order of function pointers
## in platform/host.zig's `hosted_function_ptrs` array.
##
## Convention: Both are sorted alphabetically by fully-qualified name.
##   - main.roc: exposes [Crypto, Host, Stderr, Stdin, Stdout]
##   - host.zig: hosted_function_ptrs = [hostedHostPubkey, hostedHostSign, ...]
##
## When adding a new module:
##   1. Add module file: platform/ModuleName.roc
##   2. Add to exposes (alphabetical order)
##   3. Add host function to host.zig (alphabetical order)
platform ""
    requires {} { main! : List(Str) => Try({}, [Exit(I32)]) }
    exposes [Digest, Host, PublicKey, SecretKey, Signature, Stderr, Stdin, Stdout]
    packages {}
    provides { main_for_host! : "main_for_host" }
    targets: {
        files: "targets/",
        exe: {
            x64mac: ["libhost.a", app],
            arm64mac: ["libhost.a", app],
            x64musl: ["crt1.o", "libhost.a", app, "libc.a"],
            arm64musl: ["crt1.o", "libhost.a", app, "libc.a"],
            x64win: ["host.lib", app],
            arm64win: ["host.lib", app],
        }
    }

import Stdout
import Stderr
import Stdin
import Digest
import PublicKey
import SecretKey
import Signature

main_for_host! : List(Str) => I32
main_for_host! = |args| {
    result = main!(args)
    match result {
        Ok({}) => 0
        Err(Exit(code)) => code
    }
}
