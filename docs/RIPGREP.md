# Ripgrep Patterns for nostr-platform

Common ripgrep commands for searching the codebase.

## Essential Patterns

### secp256k1 Cryptography
```bash
# Find all secp256k1 function calls
rg "secp256k1_secp256k1_context_create" platform/host.zig
rg "secp256k1_keypair_create" platform/host.zig
rg "secp256k1_schnorrsig_sign32" platform/host.zig
rg "secp256k1_schnorrsig_verify" platform/host.zig
```

### Roc Types & Memory
```zig
# Find RocList operations
rg "RocList\." platform/host.zig
rg "RocList\.allocateExact\|RocList\.empty" platform/host.zig -n

# Find RocStr operations
rg "RocStr\." platform/host.zig
rg "RocStr\.init\|RocStr\.empty" platform/host.zig
```

### Roc Function Patterns
```bash
# Find all hosted function definitions
rg "fn hostedHost" platform/host.zig -n
rg "\"Host\":"\"" -A 5 platform/

# Find function return patterns
rg "return.*RocList" platform/host.zig
rg "return.*RocStr" platform/host.zig
rg "return.*\\*[U8|Bool|I32]" platform/host.zig
```

### Error Handling
```bash
# Find empty list/error patterns
rg "return.*RocList\.empty" platform/
rg "return.*RocStr\.empty" platform/
rg "return.*0.*=.*1" platform/  # Bool.false patterns

# Find Result/Tag patterns
rg "Err\." test/
rg "Ok\." test/
rg "\"[A-Za-z]+\\.\"" test/
```

### Test Patterns
```bash
# Find test declarations
rg "test \"|\"check\"" test/
rg "b\.addTest" build.zig

# Find test assertions
rg "try testing\expectEqual\|expect" test/ -A 2

# Find test functions
rg "fn \"test.*\"(" test/
```

### List Operations
```bash
# Find List operations
rg "List\\.len\|List\\.get\|List\\.allocateExact" platform/
rg "List\\.append\|List\\.map\|List\\.keep_if" test/ -n
```

### Number Types
```bash
# Find numeric type annotations
rg ": U64\|: I32\|: Bool\|: List U8" --line-number
```

## Common Options

### Basic Options
```bash
rg "pattern"                  # Basic search
rg "pattern" -n                # Show line numbers
rg "pattern" -C 3              # 3 lines of context
rg "pattern" -C 5              # 5 lines of context
```

### Search Inverse
```bash
rg -v "pattern" path/           # Find non-matching lines
```

### Count Matches
```bash
rg "pattern" --count           # Count matches
rg "pattern" --stats           # Detailed match stats
```

### Search Specific Files
```bash
rg "pattern" platform/           # Only search in platform/
rg "pattern" test/              # Only search in test/
rg "pattern" *.roc               # Only search .roc files
rg "pattern" *.zig              # Only search .zig files
```

## Project-Specific Searches

### Find All Host Functions
```bash
rg "fn hostedHost" platform/host.zig -A 3
rg "fn hostedSha256" platform/host.zig -A 3
rg "fn hostedStd" platform/ -A 2
```

### Find Module Implementations
```zig
# Find Host module (index 0)
rg "\"Host\":"\"" -A 20 platform/host.zig

# Find Sha256 module (index 1)
rg "\"Sha256\":"\"" -A 10 platform/
```

### Find secp256k1 Context
```bash
rg "secp256k1_ctx\|secp256k1_context" platform/host.zig
```

### Find API Surface
```roc
# Find all Host function calls in examples
rg "Host\\..*!" examples/

# Find Host function definitions in platform/
rg "\"fn\"Host\\.pubkey!|sign!|verify!\"" platform/
```

### Find TODO/FIXME
```bash
rg "TODO|FIXME|XXX|HACK|TEMP" --line-number
```

### Find Compilation/Build Artifacts
```bash
rg "zig-out|\\.zig-cache|\\.cache" --exclude-dir
```

### Find Debug Output
```bash
rg "Stdout\.line|dbg|print" platform/
```

## Complex Patterns

### Multi-pattern search
```bash
rg "secret_key|digest|pubkey|signature" platform/host.zig
```

### Pattern with context
```bash
rg -C 5 "RocList\.empty" platform/host.zig
rg -B 2 "RocList\.empty" platform/host.zig
```

### Regex with ripgrep
```bash
# Find Result types
rg "Err\\(" test/

# Find specific error tags
rg "Err\\(" test/
```

## Optimization

For very large codebases:
```bash
# Use ripgrep with hyperfine
rg "pattern" --hyperfine "build.zig"  # Faster on large files

# Use ripgrep with PCRE2 patterns
rg "secret_key\\d+" -P    # Regex patterns

# Use ripgrep with literal string matching
rg "secret_key" --type js          # JavaScript files
rg "secret_key" --type zig         # Zig files
```

## Workflow Commands

### Before changing APIs
```bash
# Find all callers of a function before refactoring
rg "my_function(" --exclude-dir=test/ -A 2

# Find all function definitions
rg "^fn my_function" -A 5
```

### Search for deprecated patterns
```bash
# Find Result/Status patterns that should be simple types
rg "Result\\.ok|Result\\.err" --exclude-dir=docs/

# Find complex conditionals that could be simplified
rg "match.*is.*=>.*is.*=>" test/
```

### Validate code consistency
```bash
# Ensure all function names match module conventions
rg "\"fn [a-z_]+!" --exclude-dir=test/ | rg "\"fn [a-z_]+\"" | grep -v "test\\|spec\\|example"
```
