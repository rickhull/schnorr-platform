platform ""
    requires {} { main! : List(Str) => Try({}, [Exit(I32)]) }
    exposes [Stdout, Stderr, Stdin, Sha256, Host]
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
import Sha256
import Host

main_for_host! : List(Str) => I32
main_for_host! = |args| {
    result = main!(args)
    match result {
        Ok({}) => 0
        Err(Exit(code)) => code
    }
}
