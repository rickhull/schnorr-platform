///! nostr-platform: Roc host implementation for Nostr cryptographic operations
///!
///! This file provides the Zig side of a Roc platform, implementing:
///!   - Host module: secp256k1 Schnorr signing, verification, pubkey derivation (BIP-340)
///!   - Sha256 module: SHA-256 hashing (binary and hex output)
///!   - Stdout/Stderr/Stdin modules: I/O operations
///!
///! ARCHITECTURE
///!
///! This is "glue code" that bridges Roc applications to Zig/C libraries:
///!   - Roc applications call hosted functions (Host.*, Sha256.*, etc.)
///!   - This file translates RocCall ABI calls to Zig/secp256k1 operations
///!   - Memory management follows Roc's allocator conventions
///!
///! TESTING
///!
///! No inline Zig tests in this file. This is pure glue code - tests live elsewhere:
///!   - test/host.zig: secp256k1 FFI integration tests
///!   - test/*.roc: Roc runtime tests for API validation
const std = @import("std");
const builtins = @import("builtins");
const secp256k1 = @cImport({
    @cInclude("secp256k1.h");
    @cInclude("secp256k1_extrakeys.h");
    @cInclude("secp256k1_schnorrsig.h");
});

/// Global flag to track if dbg or expect_failed was called.
/// If set, program exits with non-zero code to prevent accidental commits.
var debug_or_expect_called: std.atomic.Value(bool) = std.atomic.Value(bool).init(false);

/// Host environment
const HostEnv = struct {
    gpa: std.heap.GeneralPurposeAllocator(.{}),
    stdin_reader: std.fs.File.Reader,
    secp256k1_ctx: *secp256k1.secp256k1_context,
};

/// Roc allocation function with size-tracking metadata
fn rocAllocFn(roc_alloc: *builtins.host_abi.RocAlloc, env: *anyopaque) callconv(.c) void {
    const host: *HostEnv = @ptrCast(@alignCast(env));
    const allocator = host.gpa.allocator();

    const min_alignment: usize = @max(roc_alloc.alignment, @alignOf(usize));
    const align_enum = std.mem.Alignment.fromByteUnits(min_alignment);

    // Calculate additional bytes needed to store the size
    const size_storage_bytes = @max(roc_alloc.alignment, @alignOf(usize));
    const total_size = roc_alloc.length + size_storage_bytes;

    // Allocate memory including space for size metadata
    const result = allocator.rawAlloc(total_size, align_enum, @returnAddress());

    const base_ptr = result orelse {
        const stderr: std.fs.File = .stderr();
        stderr.writeAll("\x1b[31mHost error:\x1b[0m allocation failed, out of memory\n") catch {};
        std.process.exit(1);
    };

    // Store the total size (including metadata) right before the user data
    const size_ptr: *usize = @ptrFromInt(@intFromPtr(base_ptr) + size_storage_bytes - @sizeOf(usize));
    size_ptr.* = total_size;

    // Return pointer to the user data (after the size metadata)
    roc_alloc.answer = @ptrFromInt(@intFromPtr(base_ptr) + size_storage_bytes);

    std.log.debug("[ALLOC] ptr=0x{x} size={d} align={d}", .{ @intFromPtr(roc_alloc.answer), roc_alloc.length, roc_alloc.alignment });
}

/// Roc deallocation function with size-tracking metadata
fn rocDeallocFn(roc_dealloc: *builtins.host_abi.RocDealloc, env: *anyopaque) callconv(.c) void {
    std.log.debug("[DEALLOC] ptr=0x{x} align={d}", .{ @intFromPtr(roc_dealloc.ptr), roc_dealloc.alignment });

    const host: *HostEnv = @ptrCast(@alignCast(env));
    const allocator = host.gpa.allocator();

    // Calculate where the size metadata is stored
    const size_storage_bytes = @max(roc_dealloc.alignment, @alignOf(usize));
    const size_ptr: *const usize = @ptrFromInt(@intFromPtr(roc_dealloc.ptr) - @sizeOf(usize));

    // Read the total size from metadata
    const total_size = size_ptr.*;

    // Calculate the base pointer (start of actual allocation)
    const base_ptr: [*]u8 = @ptrFromInt(@intFromPtr(roc_dealloc.ptr) - size_storage_bytes);

    // Calculate alignment
    const min_alignment: usize = @max(roc_dealloc.alignment, @alignOf(usize));
    const align_enum = std.mem.Alignment.fromByteUnits(min_alignment);

    // Free the memory (including the size metadata)
    const slice = @as([*]u8, @ptrCast(base_ptr))[0..total_size];
    allocator.rawFree(slice, align_enum, @returnAddress());
}

/// Roc reallocation function with size-tracking metadata
fn rocReallocFn(roc_realloc: *builtins.host_abi.RocRealloc, env: *anyopaque) callconv(.c) void {
    const host: *HostEnv = @ptrCast(@alignCast(env));
    const allocator = host.gpa.allocator();

    // Calculate alignment
    const min_alignment: usize = @max(roc_realloc.alignment, @alignOf(usize));
    const align_enum = std.mem.Alignment.fromByteUnits(min_alignment);

    // Calculate where the size metadata is stored for the old allocation
    const size_storage_bytes = min_alignment;
    const old_size_ptr: *const usize = @ptrFromInt(@intFromPtr(roc_realloc.answer) - @sizeOf(usize));

    // Read the old total size from metadata
    const old_total_size = old_size_ptr.*;

    // Calculate the old base pointer (start of actual allocation)
    const old_base_ptr: [*]u8 = @ptrFromInt(@intFromPtr(roc_realloc.answer) - size_storage_bytes);

    // Calculate new total size needed
    const new_total_size = roc_realloc.new_length + size_storage_bytes;

    // Allocate new memory with proper alignment
    const new_base_ptr = allocator.rawAlloc(new_total_size, align_enum, @returnAddress()) orelse {
        const stderr: std.fs.File = .stderr();
        stderr.writeAll("\x1b[31mHost error:\x1b[0m reallocation failed, out of memory\n") catch {};
        std.process.exit(1);
    };

    // Copy old data to new allocation (excluding metadata, just user data)
    const old_user_data_size = old_total_size - size_storage_bytes;
    const copy_size = @min(old_user_data_size, roc_realloc.new_length);
    const new_user_ptr: [*]u8 = @ptrFromInt(@intFromPtr(new_base_ptr) + size_storage_bytes);
    const old_user_ptr: [*]const u8 = @ptrCast(roc_realloc.answer);
    @memcpy(new_user_ptr, old_user_ptr[0..copy_size]);

    // Free old allocation
    const old_slice = old_base_ptr[0..old_total_size];
    allocator.rawFree(old_slice, align_enum, @returnAddress());

    // Store the new total size in the metadata
    const new_size_ptr: *usize = @ptrFromInt(@intFromPtr(new_base_ptr) + size_storage_bytes - @sizeOf(usize));
    new_size_ptr.* = new_total_size;

    // Return pointer to the user data (after the size metadata)
    roc_realloc.answer = new_user_ptr;

    std.log.debug("[REALLOC] old=0x{x} new=0x{x} new_size={d}", .{ @intFromPtr(roc_realloc.answer), @intFromPtr(new_user_ptr), roc_realloc.new_length });
}

/// Roc debug function
fn rocDbgFn(roc_dbg: *const builtins.host_abi.RocDbg, env: *anyopaque) callconv(.c) void {
    _ = env;
    debug_or_expect_called.store(true, .release);
    const message = roc_dbg.utf8_bytes[0..roc_dbg.len];
    const stderr: std.fs.File = .stderr();
    stderr.writeAll("\x1b[33mdbg:\x1b[0m ") catch {};
    stderr.writeAll(message) catch {};
    stderr.writeAll("\n") catch {};
}

/// Roc expect failed function
fn rocExpectFailedFn(roc_expect: *const builtins.host_abi.RocExpectFailed, env: *anyopaque) callconv(.c) void {
    _ = env;
    debug_or_expect_called.store(true, .release);
    const source_bytes = roc_expect.utf8_bytes[0..roc_expect.len];
    const trimmed = std.mem.trim(u8, source_bytes, " \t\n\r");
    const stderr: std.fs.File = .stderr();
    stderr.writeAll("\x1b[33mexpect failed:\x1b[0m ") catch {};
    stderr.writeAll(trimmed) catch {};
    stderr.writeAll("\n") catch {};
}

/// Roc crashed function
fn rocCrashedFn(roc_crashed: *const builtins.host_abi.RocCrashed, env: *anyopaque) callconv(.c) noreturn {
    _ = env;
    const message = roc_crashed.utf8_bytes[0..roc_crashed.len];
    const stderr: std.fs.File = .stderr();
    var buf: [256]u8 = undefined;
    var w = stderr.writer(&buf);
    w.interface.print("\n\x1b[31mRoc crashed:\x1b[0m {s}\n", .{message}) catch {};
    w.interface.flush() catch {};
    std.process.exit(1);
}

// External symbols provided by the Roc runtime object file
// Follows RocCall ABI: ops, ret_ptr, then argument pointers
extern fn roc__main_for_host(ops: *builtins.host_abi.RocOps, ret_ptr: *anyopaque, arg_ptr: ?*anyopaque) callconv(.c) void;

// OS-specific entry point handling (not exported during tests)
comptime {
    if (!@import("builtin").is_test) {
        // Export main for all platforms
        @export(&main, .{ .name = "main" });

        // Windows MinGW/MSVCRT compatibility: export __main stub
        if (@import("builtin").os.tag == .windows) {
            @export(&__main, .{ .name = "__main" });
        }
    }
}

// Windows MinGW/MSVCRT compatibility stub
// The C runtime on Windows calls __main from main for constructor initialization
fn __main() callconv(.c) void {}

// C compatible main for runtime
fn main(argc: c_int, argv: [*][*:0]u8) callconv(.c) c_int {
    return platform_main(@intCast(argc), argv);
}

// Use the actual types from builtins
const RocStr = builtins.str.RocStr;
const RocList = builtins.list.RocList;

/// Hosted function: Stderr.line! (index 1 - sorted alphabetically)
/// Follows RocCall ABI: (ops, ret_ptr, args_ptr)
/// Returns {} and takes Str as argument
fn hostedStderrLine(ops: *builtins.host_abi.RocOps, ret_ptr: *anyopaque, args_ptr: *anyopaque) callconv(.c) void {
    _ = ops;
    _ = ret_ptr; // Return value is {} which is zero-sized

    // Arguments struct for single Str parameter
    const Args = extern struct { str: RocStr };
    const args: *Args = @ptrCast(@alignCast(args_ptr));

    const message = args.str.asSlice();
    const stderr: std.fs.File = .stderr();
    stderr.writeAll(message) catch {};
    stderr.writeAll("\n") catch {};
}

/// Hosted function: Stdin.line! (index 2 - sorted alphabetically)
/// Follows RocCall ABI: (ops, ret_ptr, args_ptr)
/// Returns Str and takes {} as argument
fn hostedStdinLine(ops: *builtins.host_abi.RocOps, ret_ptr: *anyopaque, args_ptr: *anyopaque) callconv(.c) void {
    _ = args_ptr; // Argument is {} which is zero-sized

    const host: *HostEnv = @ptrCast(@alignCast(ops.env));
    var reader = &host.stdin_reader.interface;

    var line = while (true) {
        const maybe_line = reader.takeDelimiter('\n') catch |err| switch (err) {
            error.ReadFailed => break &.{}, // Return empty string on error
            error.StreamTooLong => {
                // Skip the overlong line so the next call starts fresh.
                _ = reader.discardDelimiterInclusive('\n') catch |discard_err| switch (discard_err) {
                    error.ReadFailed, error.EndOfStream => break &.{},
                };
                continue;
            },
        } orelse break &.{};

        break maybe_line;
    };

    // Trim trailing \r for Windows line endings
    if (line.len > 0 and line[line.len - 1] == '\r') {
        line = line[0 .. line.len - 1];
    }

    if (line.len == 0) {
        // Return empty string
        const result: *RocStr = @ptrCast(@alignCast(ret_ptr));
        result.* = RocStr.empty();
        return;
    }

    // Create RocStr from the read line - RocStr.init handles allocation internally
    const result: *RocStr = @ptrCast(@alignCast(ret_ptr));
    result.* = RocStr.init(line.ptr, line.len, ops);
}

/// Hosted function: Sha256.binary! (alphabetically before hex!)
/// Follows RocCall ABI: (ops, ret_ptr, args_ptr)
/// Returns List U8 (32-byte binary hash) and takes Str as argument
fn hostedSha256Binary(ops: *builtins.host_abi.RocOps, ret_ptr: *anyopaque, args_ptr: *anyopaque) callconv(.c) void {
    // Arguments struct for single Str parameter
    const Args = extern struct { str: RocStr };
    const args: *Args = @ptrCast(@alignCast(args_ptr));

    const message = args.str.asSlice();

    // Compute SHA-256
    var digest: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(message, &digest, .{});

    // Create RocList with 32 bytes
    const digest_list = RocList.allocateExact(
        @alignOf(u8),
        32,
        @sizeOf(u8),
        false, // elements are not refcounted (u8)
        ops,
    );

    // Copy the digest bytes into the RocList
    @memcpy(@as([*]u8, @ptrCast(@alignCast(digest_list.bytes)))[0..32], &digest);

    // Return the list
    const result: *RocList = @ptrCast(@alignCast(ret_ptr));
    result.* = digest_list;
}

/// Hosted function: Sha256.hex! (alphabetically after binary!)
/// Follows RocCall ABI: (ops, ret_ptr, args_ptr)
/// Returns Str (hex-encoded hash) and takes Str as argument
fn hostedSha256Hex(ops: *builtins.host_abi.RocOps, ret_ptr: *anyopaque, args_ptr: *anyopaque) callconv(.c) void {
    // Arguments struct for single Str parameter
    const Args = extern struct { str: RocStr };
    const args: *Args = @ptrCast(@alignCast(args_ptr));

    const message = args.str.asSlice();

    // Compute SHA-256
    var digest: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(message, &digest, .{});

    // Convert to hex string (64 chars for 32 bytes)
    var hex_buf: [64]u8 = undefined;
    const hex_chars = "0123456789abcdef";
    for (digest, 0..) |byte, i| {
        hex_buf[i * 2] = hex_chars[byte >> 4];
        hex_buf[i * 2 + 1] = hex_chars[byte & 0x0F];
    }

    // Create RocStr from hex string
    const result: *RocStr = @ptrCast(@alignCast(ret_ptr));
    result.* = RocStr.init(&hex_buf, 64, ops);
}

/// Hosted function: Stdout.line! (index 3 - sorted alphabetically)
/// Follows RocCall ABI: (ops, ret_ptr, args_ptr)
/// Returns {} and takes Str as argument
fn hostedStdoutLine(ops: *builtins.host_abi.RocOps, ret_ptr: *anyopaque, args_ptr: *anyopaque) callconv(.c) void {
    _ = ops;
    _ = ret_ptr; // Return value is {} which is zero-sized

    // Arguments struct for single Str parameter
    const Args = extern struct { str: RocStr };
    const args: *Args = @ptrCast(@alignCast(args_ptr));

    const message = args.str.asSlice();
    const stdout: std.fs.File = .stdout();
    stdout.writeAll(message) catch {};
    stdout.writeAll("\n") catch {};
}

/// Hosted function: Host.pubkey (index 0 - sorted alphabetically)
/// Derive public key from secret key using secp256k1
/// Follows RocCall ABI: (ops, ret_ptr, args_ptr)
/// Returns List U8 - 32-byte public key on success, empty list on error
fn hostedHostPubkey(ops: *builtins.host_abi.RocOps, ret_ptr: *anyopaque, args_ptr: *anyopaque) callconv(.c) void {
    // Arguments struct for List U8 parameter
    const Args = extern struct { secret_key: RocList };
    const args: *Args = @ptrCast(@alignCast(args_ptr));

    const host: *HostEnv = @ptrCast(@alignCast(ops.env));

    // Get secret key bytes from RocList
    const bytes_ptr = args.secret_key.bytes orelse {
        // Return empty list on error
        const result: *RocList = @ptrCast(@alignCast(ret_ptr));
        result.* = RocList.empty();
        return;
    };
    const secret_key_bytes = bytes_ptr[0..args.secret_key.length];

    // Validate secret key length
    if (secret_key_bytes.len != 32) {
        // Return empty list on error
        const result: *RocList = @ptrCast(@alignCast(ret_ptr));
        result.* = RocList.empty();
        return;
    }

    // Parse secret key
    var keypair: secp256k1.secp256k1_keypair = undefined;
    if (secp256k1.secp256k1_keypair_create(host.secp256k1_ctx, &keypair, secret_key_bytes.ptr) != 1) {
        // Invalid secret key - return empty list on error
        const result: *RocList = @ptrCast(@alignCast(ret_ptr));
        result.* = RocList.empty();
        return;
    }

    // Extract x-only public key from keypair (32 bytes for Nostr)
    var xonly_pubkey: secp256k1.secp256k1_xonly_pubkey = undefined;
    var pk_parity: c_int = 0;
    _ = secp256k1.secp256k1_keypair_xonly_pub(host.secp256k1_ctx, &xonly_pubkey, &pk_parity, &keypair);

    // Serialize x-only public key (32 bytes)
    var pubkey_bytes: [32]u8 = undefined;
    _ = secp256k1.secp256k1_xonly_pubkey_serialize(host.secp256k1_ctx, &pubkey_bytes, &xonly_pubkey);

    // Create RocList with 32 bytes
    const pubkey_list = RocList.allocateExact(
        @alignOf(u8),
        32,
        @sizeOf(u8),
        false, // elements are not refcounted (u8)
        ops,
    );

    @memcpy(@as([*]u8, @ptrCast(@alignCast(pubkey_list.bytes)))[0..32], &pubkey_bytes);

    // Return the list directly
    const result: *RocList = @ptrCast(@alignCast(ret_ptr));
    result.* = pubkey_list;
}

/// Hosted function: Host.sign (index 1 - sorted alphabetically)
/// Sign a 32-byte digest using Schnorr signature
/// Follows RocCall ABI: (ops, ret_ptr, args_ptr)
/// Returns List U8 - 64-byte signature on success, empty list on error
fn hostedHostSign(ops: *builtins.host_abi.RocOps, ret_ptr: *anyopaque, args_ptr: *anyopaque) callconv(.c) void {
    // Arguments struct for (List U8, List U8) parameters
    const Args = extern struct { secret_key: RocList, digest: RocList };
    const args: *Args = @ptrCast(@alignCast(args_ptr));

    const host: *HostEnv = @ptrCast(@alignCast(ops.env));

    // Get bytes from RocLists
    const sk_bytes_ptr = args.secret_key.bytes orelse {
        // Return empty list on error
        const result: *RocList = @ptrCast(@alignCast(ret_ptr));
        result.* = RocList.empty();
        return;
    };
    const digest_bytes_ptr = args.digest.bytes orelse {
        const result: *RocList = @ptrCast(@alignCast(ret_ptr));
        result.* = RocList.empty();
        return;
    };

    const secret_key_bytes = sk_bytes_ptr[0..args.secret_key.length];
    const digest_bytes = digest_bytes_ptr[0..args.digest.length];

    // Validate lengths
    if (secret_key_bytes.len != 32 or digest_bytes.len != 32) {
        // Return empty list on error
        const result: *RocList = @ptrCast(@alignCast(ret_ptr));
        result.* = RocList.empty();
        return;
    }

    // Create keypair from secret key
    var keypair: secp256k1.secp256k1_keypair = undefined;
    if (secp256k1.secp256k1_keypair_create(host.secp256k1_ctx, &keypair, secret_key_bytes.ptr) != 1) {
        // Invalid secret key - return empty list on error
        const result: *RocList = @ptrCast(@alignCast(ret_ptr));
        result.* = RocList.empty();
        return;
    }

    // Sign using Schnorr
    var signature: [64]u8 = undefined;
    if (secp256k1.secp256k1_schnorrsig_sign32(
        host.secp256k1_ctx,
        &signature,
        digest_bytes.ptr,
        &keypair,
        null, // aux_rand - NULL means generate random nonce internally
    ) != 1) {
        const result: *RocList = @ptrCast(@alignCast(ret_ptr));
        result.* = RocList.empty();
        return;
    }

    // Create RocList with 64-byte signature
    const sig_list = RocList.allocateExact(
        @alignOf(u8),
        64,
        @sizeOf(u8),
        false,
        ops,
    );

    @memcpy(@as([*]u8, @ptrCast(@alignCast(sig_list.bytes)))[0..64], &signature);

    // Return the list directly
    const result: *RocList = @ptrCast(@alignCast(ret_ptr));
    result.* = sig_list;
}

/// Hosted function: Host.verify (index 2 - sorted alphabetically)
/// Verify a Schnorr signature
/// Follows RocCall ABI: (ops, ret_ptr, args_ptr)
/// Returns Bool (true if valid, false if invalid or error)
fn hostedHostVerify(ops: *builtins.host_abi.RocOps, ret_ptr: *anyopaque, args_ptr: *anyopaque) callconv(.c) void {
    // Arguments struct for (List U8, List U8, List U8) parameters
    const Args = extern struct { pubkey: RocList, digest: RocList, signature: RocList };
    const args: *Args = @ptrCast(@alignCast(args_ptr));

    const host: *HostEnv = @ptrCast(@alignCast(ops.env));

    // Get bytes from RocLists
    const pubkey_bytes_ptr = args.pubkey.bytes orelse {
        const result: *u8 = @ptrCast(@alignCast(ret_ptr));
        result.* = 0; // false
        return;
    };
    const digest_bytes_ptr = args.digest.bytes orelse {
        const result: *u8 = @ptrCast(@alignCast(ret_ptr));
        result.* = 0; // false
        return;
    };
    const sig_bytes_ptr = args.signature.bytes orelse {
        const result: *u8 = @ptrCast(@alignCast(ret_ptr));
        result.* = 0; // false
        return;
    };

    const pubkey_bytes = pubkey_bytes_ptr[0..args.pubkey.length];
    const digest_bytes = digest_bytes_ptr[0..args.digest.length];
    const sig_bytes = sig_bytes_ptr[0..args.signature.length];

    // Validate lengths
    if (pubkey_bytes.len != 32 or digest_bytes.len != 32 or sig_bytes.len != 64) {
        // Return false
        const result: *u8 = @ptrCast(@alignCast(ret_ptr));
        result.* = 0;
        return;
    }

    // Parse x-only public key (32 bytes)
    var xonly_pubkey: secp256k1.secp256k1_xonly_pubkey = undefined;
    if (secp256k1.secp256k1_xonly_pubkey_parse(
        host.secp256k1_ctx,
        &xonly_pubkey,
        pubkey_bytes.ptr,
    ) != 1) {
        // Invalid public key - return false
        const result: *u8 = @ptrCast(@alignCast(ret_ptr));
        result.* = 0;
        return;
    }

    // Verify signature using x-only public key
    const verify_result = secp256k1.secp256k1_schnorrsig_verify(
        host.secp256k1_ctx,
        sig_bytes.ptr,
        digest_bytes.ptr,
        32, // message length (32 bytes for SHA-256 digest)
        &xonly_pubkey,
    );

    // Return true (1) if valid, false (0) if invalid
    const result: *u8 = @ptrCast(@alignCast(ret_ptr));
    result.* = if (verify_result == 1) 1 else 0;
}

/// Array of hosted function pointers, sorted alphabetically by fully-qualified name
///
/// PLATFORM COUPLING: host.zig ↔ main.roc
/// This array order MUST match the `exposes` order in platform/main.roc
///
/// Convention: Both are sorted alphabetically by fully-qualified name.
///   - main.roc exposes: [Host, Sha256, Stderr, Stdin, Stdout]
///   - host.zig array: [hostedHostPubkey, hostedHostSign, ..., hostedStdoutLine]
///
/// When adding a new hosted function:
///   1. Add function pointer here (alphabetical by fully-qualified name)
///   2. Add module to main.roc exposes (alphabetical order)
///   3. Ensure index alignment between the two
const hosted_function_ptrs = [_]builtins.host_abi.HostedFn{
    hostedHostPubkey,    // Host.pubkey (index 0)
    hostedHostSign,      // Host.sign (index 1)
    hostedHostVerify,    // Host.verify (index 2)
    hostedSha256Binary,  // Sha256.binary! (index 3)
    hostedSha256Hex,     // Sha256.hex! (index 4)
    hostedStderrLine,    // Stderr.line! (index 5)
    hostedStdinLine,     // Stdin.line! (index 6)
    hostedStdoutLine,    // Stdout.line! (index 7)
};

/// Platform host entrypoint
fn platform_main(argc: usize, argv: [*][*:0]u8) c_int {
    var stdin_buffer: [4096]u8 = undefined;

    // Create secp256k1 context (for both signing and verification)
    const secp256k1_ctx = secp256k1.secp256k1_context_create(
        secp256k1.SECP256K1_CONTEXT_SIGN | secp256k1.SECP256K1_CONTEXT_VERIFY,
    ) orelse {
        std.log.err("Failed to create secp256k1 context", .{});
        std.process.exit(1);
    };

    var host_env = HostEnv{
        .gpa = std.heap.GeneralPurposeAllocator(.{}){},
        .stdin_reader = std.fs.File.stdin().reader(&stdin_buffer),
        .secp256k1_ctx = secp256k1_ctx,
    };

    // Create the RocOps struct
    var roc_ops = builtins.host_abi.RocOps{
        .env = @as(*anyopaque, @ptrCast(&host_env)),
        .roc_alloc = rocAllocFn,
        .roc_dealloc = rocDeallocFn,
        .roc_realloc = rocReallocFn,
        .roc_dbg = rocDbgFn,
        .roc_expect_failed = rocExpectFailedFn,
        .roc_crashed = rocCrashedFn,
        .hosted_fns = .{
            .count = hosted_function_ptrs.len,
            .fns = @constCast(&hosted_function_ptrs),
        },
    };

    // Build List(Str) from argc/argv
    std.log.debug("[HOST] Building args...", .{});
    const args_list = buildStrArgsList(argc, argv, &roc_ops);
    std.log.debug("[HOST] args_list ptr=0x{x} len={d}", .{ @intFromPtr(args_list.bytes), args_list.length });

    // Call the app's main! entrypoint - returns I32 exit code
    std.log.debug("[HOST] Calling roc__main_for_host...", .{});

    var exit_code: i32 = -99;
    roc__main_for_host(&roc_ops, @as(*anyopaque, @ptrCast(&exit_code)), @as(*anyopaque, @ptrCast(@constCast(&args_list))));

    std.log.debug("[HOST] Returned from roc, exit_code={d}", .{exit_code});

    // Destroy secp256k1 context
    secp256k1.secp256k1_context_destroy(host_env.secp256k1_ctx);

    // Check for memory leaks before returning
    const leak_status = host_env.gpa.deinit();
    if (leak_status == .leak) {
        std.log.err("\x1b[33mMemory leak detected!\x1b[0m", .{});
        std.process.exit(1);
    }

    // If dbg or expect_failed was called, ensure non-zero exit code
    // to prevent accidental commits with debug statements or failing tests
    if (debug_or_expect_called.load(.acquire) and exit_code == 0) {
        return 1;
    }

    return exit_code;
}

/// Build a RocList of RocStr from argc/argv
fn buildStrArgsList(argc: usize, argv: [*][*:0]u8, roc_ops: *builtins.host_abi.RocOps) RocList {
    if (argc == 0) {
        return RocList.empty();
    }

    // Allocate list with proper refcount header using RocList.allocateExact
    const args_list = RocList.allocateExact(
        @alignOf(RocStr),
        argc,
        @sizeOf(RocStr),
        true, // elements are refcounted (RocStr)
        roc_ops,
    );

    const args_ptr: [*]RocStr = @ptrCast(@alignCast(args_list.bytes));

    // Build each argument string
    for (0..argc) |i| {
        const arg_cstr = argv[i];
        const arg_len = std.mem.len(arg_cstr);

        // RocStr.init takes a const pointer to read FROM and allocates internally
        args_ptr[i] = RocStr.init(arg_cstr, arg_len, roc_ops);
    }

    return args_list;
}
