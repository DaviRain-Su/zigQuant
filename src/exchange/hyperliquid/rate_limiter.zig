//! Rate Limiter for Hyperliquid API
//!
//! Implements token bucket algorithm for rate limiting:
//! - Default: 20 requests per second
//! - Configurable burst size
//! - Thread-safe operations

const std = @import("std");

// ============================================================================
// Rate Limiter
// ============================================================================

pub const RateLimiter = struct {
    tokens: f64,
    max_tokens: f64,
    refill_rate: f64, // tokens per second
    last_refill: i128, // timestamp in nanoseconds
    mutex: std.Thread.Mutex,

    /// Initialize rate limiter
    ///
    /// @param rate: requests per second
    /// @param burst: maximum burst size (defaults to rate if 0)
    pub fn init(rate: f64, burst: f64) RateLimiter {
        const max_tokens = if (burst > 0) burst else rate;
        return .{
            .tokens = max_tokens,
            .max_tokens = max_tokens,
            .refill_rate = rate,
            .last_refill = std.time.nanoTimestamp(),
            .mutex = std.Thread.Mutex{},
        };
    }

    /// Wait for permission to make a request
    ///
    /// Blocks until a token is available
    pub fn wait(self: *RateLimiter) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        while (true) {
            self.refill();

            if (self.tokens >= 1.0) {
                self.tokens -= 1.0;
                return;
            }

            // Calculate wait time
            const tokens_needed = 1.0 - self.tokens;
            const wait_seconds = tokens_needed / self.refill_rate;
            const wait_ns = @as(u64, @intFromFloat(wait_seconds * std.time.ns_per_s));

            // Release mutex during sleep
            self.mutex.unlock();
            std.Thread.sleep(wait_ns);
            self.mutex.lock();
        }
    }

    /// Try to acquire a token without blocking
    ///
    /// @return true if token acquired, false otherwise
    pub fn tryAcquire(self: *RateLimiter) bool {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.refill();

        if (self.tokens >= 1.0) {
            self.tokens -= 1.0;
            return true;
        }

        return false;
    }

    /// Refill tokens based on elapsed time
    fn refill(self: *RateLimiter) void {
        const now = std.time.nanoTimestamp();
        const elapsed_ns = now - self.last_refill;
        const elapsed_seconds = @as(f64, @floatFromInt(elapsed_ns)) / std.time.ns_per_s;

        const tokens_to_add = elapsed_seconds * self.refill_rate;
        self.tokens = @min(self.tokens + tokens_to_add, self.max_tokens);
        self.last_refill = now;
    }

    /// Get current available tokens
    pub fn availableTokens(self: *RateLimiter) f64 {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.refill();
        return self.tokens;
    }
};

// ============================================================================
// Hyperliquid-specific rate limiter
// ============================================================================

/// Create rate limiter for Hyperliquid API (20 req/s)
pub fn createHyperliquidRateLimiter() RateLimiter {
    return RateLimiter.init(20.0, 20.0);
}

// ============================================================================
// Tests
// ============================================================================

test "RateLimiter: initialization" {
    const limiter = RateLimiter.init(10.0, 10.0);
    try std.testing.expectEqual(@as(f64, 10.0), limiter.max_tokens);
    try std.testing.expectEqual(@as(f64, 10.0), limiter.refill_rate);
}

test "RateLimiter: tryAcquire" {
    var limiter = RateLimiter.init(10.0, 10.0);

    // Should be able to acquire initially
    try std.testing.expect(limiter.tryAcquire());
    try std.testing.expect(limiter.tokens < 10.0);
}

test "RateLimiter: refill" {
    var limiter = RateLimiter.init(10.0, 10.0);

    // Acquire all tokens
    var i: u32 = 0;
    while (i < 10) : (i += 1) {
        try std.testing.expect(limiter.tryAcquire());
    }

    // Should not be able to acquire now
    try std.testing.expect(!limiter.tryAcquire());

    // Wait for refill
    std.Thread.sleep(std.time.ns_per_s / 10); // 0.1 second = 1 token

    // Should be able to acquire again
    try std.testing.expect(limiter.tryAcquire());
}

test "RateLimiter: availableTokens" {
    var limiter = RateLimiter.init(10.0, 10.0);
    const initial = limiter.availableTokens();
    try std.testing.expectEqual(@as(f64, 10.0), initial);

    _ = limiter.tryAcquire();
    const after = limiter.availableTokens();
    try std.testing.expect(after < initial);
}

test "createHyperliquidRateLimiter" {
    const limiter = createHyperliquidRateLimiter();
    try std.testing.expectEqual(@as(f64, 20.0), limiter.max_tokens);
    try std.testing.expectEqual(@as(f64, 20.0), limiter.refill_rate);
}

test "RateLimiter: wait" {
    var limiter = RateLimiter.init(100.0, 2.0); // High rate, low burst

    // Acquire 2 tokens
    limiter.wait();
    limiter.wait();

    // Third wait should block briefly
    const start = std.time.milliTimestamp();
    limiter.wait();
    const elapsed = std.time.milliTimestamp() - start;

    // Should have waited at least a few milliseconds
    try std.testing.expect(elapsed >= 5);
}
