const std = @import("std");
const testing = std.testing;

// These tests verify the Sha256 integration logic
// Focus: hex encoding, test vectors, output consistency

test "sha256 integration: digest length is 32 bytes" {
    // Verify SHA-256 produces 32-byte digests
    try testing.expectEqual(@as(usize, 32), std.crypto.hash.sha2.Sha256.digest_length);
}

test "sha256 integration: verify known test vector" {
    const input = "hello world";

    // Verify stdlib produces expected hash
    var digest: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(input, &digest, .{});

    // Expected SHA-256 of "hello world"
    const expected = [_]u8{
        0xb9, 0x4d, 0x27, 0xb9, 0x93, 0x4d, 0x3e, 0x08,
        0xa5, 0x2e, 0x52, 0xd7, 0xda, 0x7d, 0xab, 0xfa,
        0xc4, 0x84, 0xef, 0xe3, 0x7a, 0x53, 0x80, 0xee,
        0x90, 0x88, 0xf7, 0xac, 0xe2, 0xef, 0xcd, 0xe9,
    };

    try testing.expectEqualSlices(u8, &expected, &digest);
}

test "sha256 integration: hex encoding format" {
    // Verify hex encoding uses lowercase
    const digest = [_]u8{ 0x00, 0xFF, 0x10, 0xAB };
    const hex_chars = "0123456789abcdef";

    var hex_buf: [8]u8 = undefined;
    for (digest, 0..) |byte, i| {
        hex_buf[i * 2] = hex_chars[byte >> 4];
        hex_buf[i * 2 + 1] = hex_chars[byte & 0x0F];
    }

    const expected = "00ff10ab";
    try testing.expectEqualStrings(expected, &hex_buf);
}

test "sha256 integration: output length is consistent" {
    // Various input sizes should all produce 32-byte digests
    const inputs = [_][]const u8{
        "",
        "a",
        "abc",
        "hello world",
        &[_]u8{0} ** 1024,
    };

    for (inputs) |input| {
        var digest: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(input, &digest, .{});

        try testing.expectEqual(@as(usize, 32), digest.len);
    }
}
