//! JWT (JSON Web Token) Authentication
//!
//! Implements JWT generation and verification using HS256 algorithm.
//! Compatible with standard JWT libraries in other languages.

const std = @import("std");
const Allocator = std.mem.Allocator;

/// JWT payload structure
pub const JwtPayload = struct {
    /// Subject (usually user ID)
    sub: []const u8,
    /// Issued at timestamp
    iat: i64,
    /// Expiration timestamp
    exp: i64,
    /// Optional issuer
    iss: ?[]const u8 = null,
    /// Optional audience
    aud: ?[]const u8 = null,
};

/// JWT Manager for generating and verifying tokens
pub const JwtManager = struct {
    allocator: Allocator,
    secret: []const u8,
    expiry_seconds: i64,
    issuer: ?[]const u8,

    const Self = @This();

    /// Initialize a new JWT manager
    pub fn init(
        allocator: Allocator,
        secret: []const u8,
        expiry_hours: u32,
        issuer: ?[]const u8,
    ) Self {
        return .{
            .allocator = allocator,
            .secret = secret,
            .expiry_seconds = @as(i64, expiry_hours) * 3600,
            .issuer = issuer,
        };
    }

    /// Generate a new JWT token for the given user ID
    pub fn generateToken(self: *const Self, user_id: []const u8) ![]const u8 {
        const now = std.time.timestamp();

        // Create header (always HS256)
        const header = "{\"alg\":\"HS256\",\"typ\":\"JWT\"}";
        const header_b64 = try base64UrlEncode(self.allocator, header);
        defer self.allocator.free(header_b64);

        // Create payload JSON string
        var payload_buf: [512]u8 = undefined;
        const payload = if (self.issuer) |iss|
            try std.fmt.bufPrint(&payload_buf, "{{\"sub\":\"{s}\",\"iat\":{d},\"exp\":{d},\"iss\":\"{s}\"}}", .{ user_id, now, now + self.expiry_seconds, iss })
        else
            try std.fmt.bufPrint(&payload_buf, "{{\"sub\":\"{s}\",\"iat\":{d},\"exp\":{d}}}", .{ user_id, now, now + self.expiry_seconds });

        const payload_b64 = try base64UrlEncode(self.allocator, payload);
        defer self.allocator.free(payload_b64);

        // Create signature
        const message = try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ header_b64, payload_b64 });
        defer self.allocator.free(message);

        const signature = try hmacSha256(self.allocator, message, self.secret);
        defer self.allocator.free(signature);

        const signature_b64 = try base64UrlEncode(self.allocator, signature);
        defer self.allocator.free(signature_b64);

        // Combine all parts
        return try std.fmt.allocPrint(self.allocator, "{s}.{s}.{s}", .{ header_b64, payload_b64, signature_b64 });
    }

    /// Verify a JWT token and return the payload
    pub fn verifyToken(self: *const Self, token: []const u8) !JwtPayload {
        // Split token into parts
        var parts_iter = std.mem.splitScalar(u8, token, '.');
        const header_b64 = parts_iter.next() orelse return error.InvalidToken;
        const payload_b64 = parts_iter.next() orelse return error.InvalidToken;
        const signature_b64 = parts_iter.next() orelse return error.InvalidToken;

        // Check no extra parts
        if (parts_iter.next() != null) return error.InvalidToken;

        // Verify signature
        const message = try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ header_b64, payload_b64 });
        defer self.allocator.free(message);

        const expected_sig = try hmacSha256(self.allocator, message, self.secret);
        defer self.allocator.free(expected_sig);

        const expected_sig_b64 = try base64UrlEncode(self.allocator, expected_sig);
        defer self.allocator.free(expected_sig_b64);

        if (!std.mem.eql(u8, signature_b64, expected_sig_b64)) {
            return error.InvalidSignature;
        }

        // Decode payload
        const payload_json = try base64UrlDecode(self.allocator, payload_b64);
        defer self.allocator.free(payload_json);

        // Parse payload JSON
        const parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, payload_json, .{});
        defer parsed.deinit();

        const obj = parsed.value.object;

        const sub = obj.get("sub") orelse return error.MissingSubject;
        const iat = obj.get("iat") orelse return error.MissingIssuedAt;
        const exp = obj.get("exp") orelse return error.MissingExpiration;

        // Check expiration
        const exp_time = switch (exp) {
            .integer => |i| i,
            else => return error.InvalidExpiration,
        };

        const now = std.time.timestamp();
        if (now > exp_time) {
            return error.TokenExpired;
        }

        // Extract string values
        const sub_str = switch (sub) {
            .string => |s| s,
            else => return error.InvalidSubject,
        };

        const iat_time = switch (iat) {
            .integer => |i| i,
            else => return error.InvalidIssuedAt,
        };

        var iss_str: ?[]const u8 = null;
        if (obj.get("iss")) |iss| {
            iss_str = switch (iss) {
                .string => |s| s,
                else => null,
            };
        }

        var aud_str: ?[]const u8 = null;
        if (obj.get("aud")) |aud| {
            aud_str = switch (aud) {
                .string => |s| s,
                else => null,
            };
        }

        return JwtPayload{
            .sub = sub_str,
            .iat = iat_time,
            .exp = exp_time,
            .iss = iss_str,
            .aud = aud_str,
        };
    }

    /// Refresh a token (generate a new one with updated expiration)
    pub fn refreshToken(self: *const Self, token: []const u8) ![]const u8 {
        const payload = try self.verifyToken(token);
        return try self.generateToken(payload.sub);
    }
};

/// Base64 URL-safe encoding (no padding)
fn base64UrlEncode(allocator: Allocator, data: []const u8) ![]const u8 {
    const codecs = std.base64.url_safe_no_pad;
    const size = codecs.Encoder.calcSize(data.len);
    const result = try allocator.alloc(u8, size);
    _ = codecs.Encoder.encode(result, data);
    return result;
}

/// Base64 URL-safe decoding
fn base64UrlDecode(allocator: Allocator, encoded: []const u8) ![]const u8 {
    const codecs = std.base64.url_safe_no_pad;
    const size = try codecs.Decoder.calcSizeForSlice(encoded);
    const result = try allocator.alloc(u8, size);
    try codecs.Decoder.decode(result, encoded);
    return result;
}

/// HMAC-SHA256 signature
fn hmacSha256(allocator: Allocator, message: []const u8, key: []const u8) ![]const u8 {
    const HmacSha256 = std.crypto.auth.hmac.sha2.HmacSha256;
    var out: [HmacSha256.mac_length]u8 = undefined;
    HmacSha256.create(&out, message, key);
    const result = try allocator.alloc(u8, HmacSha256.mac_length);
    @memcpy(result, &out);
    return result;
}

// ============================================================================
// Tests
// ============================================================================

test "JwtManager: generate and verify token" {
    const allocator = std.testing.allocator;
    const secret = "test-secret-key-with-32-bytes!!";

    var manager = JwtManager.init(allocator, secret, 24, "zigquant");

    // Generate token
    const token = try manager.generateToken("user123");
    defer allocator.free(token);

    // Verify token structure (3 parts separated by dots)
    var parts: usize = 0;
    var iter = std.mem.splitScalar(u8, token, '.');
    while (iter.next()) |_| {
        parts += 1;
    }
    try std.testing.expectEqual(@as(usize, 3), parts);

    // Verify token
    const payload = try manager.verifyToken(token);
    try std.testing.expectEqualStrings("user123", payload.sub);
    try std.testing.expectEqualStrings("zigquant", payload.iss.?);
}

test "JwtManager: invalid signature" {
    const allocator = std.testing.allocator;

    var manager1 = JwtManager.init(allocator, "secret-key-1-with-32-bytes!!", 24, null);
    var manager2 = JwtManager.init(allocator, "secret-key-2-with-32-bytes!!", 24, null);

    // Generate with one key
    const token = try manager1.generateToken("user123");
    defer allocator.free(token);

    // Try to verify with different key
    const result = manager2.verifyToken(token);
    try std.testing.expectError(error.InvalidSignature, result);
}

test "JwtManager: expired token" {
    const allocator = std.testing.allocator;

    // Create manager with 0 hour expiry (immediately expired)
    var manager = JwtManager.init(allocator, "test-secret-key-with-32-bytes!!", 0, null);

    const token = try manager.generateToken("user123");
    defer allocator.free(token);

    // Token should be expired immediately
    const result = manager.verifyToken(token);
    try std.testing.expectError(error.TokenExpired, result);
}

test "base64UrlEncode: basic encoding" {
    const allocator = std.testing.allocator;

    const encoded = try base64UrlEncode(allocator, "Hello, World!");
    defer allocator.free(encoded);

    try std.testing.expectEqualStrings("SGVsbG8sIFdvcmxkIQ", encoded);
}

test "base64UrlDecode: basic decoding" {
    const allocator = std.testing.allocator;

    const decoded = try base64UrlDecode(allocator, "SGVsbG8sIFdvcmxkIQ");
    defer allocator.free(decoded);

    try std.testing.expectEqualStrings("Hello, World!", decoded);
}

test "hmacSha256: signature generation" {
    const allocator = std.testing.allocator;

    const sig = try hmacSha256(allocator, "message", "secret");
    defer allocator.free(sig);

    // HMAC-SHA256 always produces 32 bytes
    try std.testing.expectEqual(@as(usize, 32), sig.len);
}
