# Ripgrep Patterns for schnorr-platform

Common ripgrep commands for searching the codebase.

## Platform Architecture

### Find Hosted Functions
```bash
# All hosted function implementations (Zig side)
rg "fn hostedHost" platform/host.zig -A 3
rg "fn hostedStd" platform/host.zig -A 3

# Host module API (Roc side)
rg "^    [a-z]+! :" platform/Host.roc
```

### Find Module Definitions
```bash
# All wrapper type modules (use nominal tag unions)
rg "^[A-Z][a-zA-Z]+ := \[" platform/*.roc

# Find create methods (type constructors)
rg "create : List\(U8\)" platform/*.roc

# Find bytes methods (FFI unwrap)
rg "bytes : [A-Z][a-zA-Z]+ -> List\(U8\)" platform/*.roc
```

### Platform Coupling (CRITICAL)
```bash
# Check exposes list order (main.roc)
rg "exposes \[" platform/main.roc -A 1

# Check hosted_function_ptrs order (host.zig)
rg "hosted_function_ptrs = \[" platform/host.zig -A 10
```

## Type Operations

### List Operations
```bash
# List.len validation patterns
rg "List\.len" platform/*.roc

# List construction patterns
rg "List\.repeat|List\.pad" platform/ test/
```

### Result/Try Types
```bash
# Find Result constructors
rg "Ok\(|Err\(" test/

# Find Try types (new compiler)
rg "Try\(" platform/*.roc
```

## Common Searches

### Find All Module Uses
```bash
# Host function calls
rg "Host\.[a-z]+!" examples/

# Type wrapper usage
rg "(PublicKey|SecretKey|Signature|Digest)\." examples/

# Stdout calls
rg "Stdout\.line!" examples/
```

### Find Validation Logic
```bash
# Length checks
rg "match List\.len" platform/*.roc

# InvalidLength errors
rg "InvalidLength" platform/*.roc
```

### FFI Boundary Patterns
```bash
# All RocList allocations
rg "RocList\.allocateExact" platform/host.zig

# Empty returns (error handling)
rg "RocList\.empty\(\)" platform/host.zig

# Bool returns
rg "result\.* = 0|result\.* = 1" platform/host.zig
```

## Quick Reference

```bash
# Show line numbers
rg "pattern" -n

# Context (3 lines before/after)
rg "pattern" -C 3

# Search specific directory
rg "pattern" platform/

# Count matches
rg "pattern" --count

# Inverse search (lines NOT matching)
rg "pattern" -v
```
