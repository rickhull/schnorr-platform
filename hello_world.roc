app [main!] { pf: platform "./platform/main.roc" }

import pf.Stdout
import pf.Sha256

main! = |_args| {
    message = "hello world"
    hash = Sha256.hex!(message)

    Stdout.line!("Message: hello world")
    Stdout.line!(hash)

    Ok({})
}
