const std = @import("std");
const testing = std.testing;

const secp256k1 = @cImport({
    @cInclude("secp256k1.h");
    @cInclude("secp256k1_extrakeys.h");
    @cInclude("secp256k1_schnorrsig.h");
});

// Host module Zig tests for secp256k1 integration
//
// These tests verify the secp256k1 operations that underlie the Host module.
// Run with: `zig test test/host.zig` (requires secp256k1 to be in include path)

test "Host: secp256k1 context creation" {
    const ctx = secp256k1.secp256k1_context_create(
        secp256k1.SECP256K1_CONTEXT_SIGN | secp256k1.SECP256K1_CONTEXT_VERIFY,
    );

    try testing.expect(ctx != null);

    secp256k1.secp256k1_context_destroy(ctx);
}

test "Host: keypair creation from valid secret key" {
    const ctx = secp256k1.secp256k1_context_create(
        secp256k1.SECP256K1_CONTEXT_SIGN | secp256k1.SECP256K1_CONTEXT_VERIFY,
    );
    defer secp256k1.secp256k1_context_destroy(ctx);

    // Valid secret key (value 1)
    const secret_key = [_]u8{
        0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    };

    var keypair: secp256k1.secp256k1_keypair = undefined;
    const result = secp256k1.secp256k1_keypair_create(ctx, &keypair, &secret_key);

    try testing.expectEqual(@as(c_int, 1), result);
}

test "Host: extract x-only public key from keypair" {
    const ctx = secp256k1.secp256k1_context_create(
        secp256k1.SECP256K1_CONTEXT_SIGN | secp256k1.SECP256K1_CONTEXT_VERIFY,
    );
    defer secp256k1.secp256k1_context_destroy(ctx);

    const secret_key = [_]u8{
        0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    };

    var keypair: secp256k1.secp256k1_keypair = undefined;
    _ = secp256k1.secp256k1_keypair_create(ctx, &keypair, &secret_key);

    var xonly_pubkey: secp256k1.secp256k1_xonly_pubkey = undefined;
    var pk_parity: c_int = 0;
    const result = secp256k1.secp256k1_keypair_xonly_pub(ctx, &xonly_pubkey, &pk_parity, &keypair);

    try testing.expectEqual(@as(c_int, 1), result);

    // Serialize the public key
    var pubkey_bytes: [32]u8 = undefined;
    const serialize_result = secp256k1.secp256k1_xonly_pubkey_serialize(ctx, &pubkey_bytes, &xonly_pubkey);

    try testing.expectEqual(@as(c_int, 1), serialize_result);

    // Verify we got 32 bytes
    try testing.expectEqual(@as(usize, 32), pubkey_bytes.len);
}

test "Host: Schnorr signing produces 64-byte signature" {
    const ctx = secp256k1.secp256k1_context_create(
        secp256k1.SECP256K1_CONTEXT_SIGN | secp256k1.SECP256K1_CONTEXT_VERIFY,
    );
    defer secp256k1.secp256k1_context_destroy(ctx);

    const secret_key = [_]u8{
        0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    };

    var keypair: secp256k1.secp256k1_keypair = undefined;
    _ = secp256k1.secp256k1_keypair_create(ctx, &keypair, &secret_key);

    // 32-byte message digest
    const digest = [_]u8{0} ** 32;

    var signature: [64]u8 = undefined;
    const result = secp256k1.secp256k1_schnorrsig_sign32(
        ctx,
        &signature,
        &digest,
        &keypair,
        null, // aux_rand - NULL means generate random nonce internally
    );

    try testing.expectEqual(@as(c_int, 1), result);
    try testing.expectEqual(@as(usize, 64), signature.len);
}

test "Host: Schnorr verification of valid signature" {
    const ctx = secp256k1.secp256k1_context_create(
        secp256k1.SECP256K1_CONTEXT_SIGN | secp256k1.SECP256K1_CONTEXT_VERIFY,
    );
    defer secp256k1.secp256k1_context_destroy(ctx);

    const secret_key = [_]u8{
        0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    };

    var keypair: secp256k1.secp256k1_keypair = undefined;
    _ = secp256k1.secp256k1_keypair_create(ctx, &keypair, &secret_key);

    var xonly_pubkey: secp256k1.secp256k1_xonly_pubkey = undefined;
    var pk_parity: c_int = 0;
    _ = secp256k1.secp256k1_keypair_xonly_pub(ctx, &xonly_pubkey, &pk_parity, &keypair);

    var pubkey_bytes: [32]u8 = undefined;
    _ = secp256k1.secp256k1_xonly_pubkey_serialize(ctx, &pubkey_bytes, &xonly_pubkey);

    // Sign a message
    const digest = [_]u8{0} ** 32;
    var signature: [64]u8 = undefined;
    _ = secp256k1.secp256k1_schnorrsig_sign32(ctx, &signature, &digest, &keypair, null);

    // Verify the signature
    const verify_result = secp256k1.secp256k1_schnorrsig_verify(
        ctx,
        &signature,
        &digest,
        32,
        &xonly_pubkey,
    );

    try testing.expectEqual(@as(c_int, 1), verify_result);
}

test "Host: all-zeros secret key fails keypair creation" {
    const ctx = secp256k1.secp256k1_context_create(
        secp256k1.SECP256K1_CONTEXT_SIGN | secp256k1.SECP256K1_CONTEXT_VERIFY,
    );
    defer secp256k1.secp256k1_context_destroy(ctx);

    // Invalid secret key (all zeros)
    const secret_key = [_]u8{0} ** 32;

    var keypair: secp256k1.secp256k1_keypair = undefined;
    const result = secp256k1.secp256k1_keypair_create(ctx, &keypair, &secret_key);

    try testing.expectEqual(@as(c_int, 0), result);
}

test "Host: wrong signature length fails verification" {
    const ctx = secp256k1.secp256k1_context_create(
        secp256k1.SECP256K1_CONTEXT_SIGN | secp256k1.SECP256K1_CONTEXT_VERIFY,
    );
    defer secp256k1.secp256k1_context_destroy(ctx);

    const secret_key = [_]u8{
        0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    };

    var keypair: secp256k1.secp256k1_keypair = undefined;
    _ = secp256k1.secp256k1_keypair_create(ctx, &keypair, &secret_key);

    var xonly_pubkey: secp256k1.secp256k1_xonly_pubkey = undefined;
    var pk_parity: c_int = 0;
    _ = secp256k1.secp256k1_keypair_xonly_pub(ctx, &xonly_pubkey, &pk_parity, &keypair);

    var pubkey_bytes: [32]u8 = undefined;
    _ = secp256k1.secp256k1_xonly_pubkey_serialize(ctx, &pubkey_bytes, &xonly_pubkey);

    // Sign a message
    const digest = [_]u8{0} ** 32;
    var signature: [64]u8 = undefined;
    _ = secp256k1.secp256k1_schnorrsig_sign32(ctx, &signature, &digest, &keypair, null);

    // Try to verify with wrong message length (should fail)
    const verify_result = secp256k1.secp256k1_schnorrsig_verify(
        ctx,
        &signature,
        &digest,
        16, // Wrong length (should be 32)
        &xonly_pubkey,
    );

    try testing.expectEqual(@as(c_int, 0), verify_result);
}
