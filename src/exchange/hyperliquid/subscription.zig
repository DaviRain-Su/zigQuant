//! Subscription Manager
//!
//! Thread-safe management of WebSocket subscriptions.

const std = @import("std");
const ws_types = @import("ws_types.zig");
const Subscription = ws_types.Subscription;
const Channel = ws_types.Channel;

// ============================================================================
// Subscription Manager
// ============================================================================

pub const SubscriptionManager = struct {
    allocator: std.mem.Allocator,
    subscriptions: std.ArrayList(Subscription),
    mutex: std.Thread.Mutex,

    pub fn init(allocator: std.mem.Allocator) SubscriptionManager {
        return .{
            .allocator = allocator,
            .subscriptions = std.ArrayList(Subscription).initCapacity(allocator, 0) catch unreachable,
            .mutex = .{},
        };
    }

    pub fn deinit(self: *SubscriptionManager) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.subscriptions.deinit(self.allocator);
    }

    /// Add a subscription
    pub fn add(self: *SubscriptionManager, sub: Subscription) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Check if already subscribed
        for (self.subscriptions.items) |existing| {
            if (self.isSameSubscription(existing, sub)) {
                return; // Already subscribed
            }
        }

        try self.subscriptions.append(self.allocator, sub);
    }

    /// Remove a subscription
    pub fn remove(self: *SubscriptionManager, sub: Subscription) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        var i: usize = 0;
        while (i < self.subscriptions.items.len) {
            if (self.isSameSubscription(self.subscriptions.items[i], sub)) {
                _ = self.subscriptions.swapRemove(i);
                return;
            }
            i += 1;
        }
    }

    /// Remove all subscriptions
    pub fn clear(self: *SubscriptionManager) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.subscriptions.clearRetainingCapacity();
    }

    /// Get all subscriptions (caller must not modify the returned slice)
    pub fn getAll(self: *SubscriptionManager) []const Subscription {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.subscriptions.items;
    }

    /// Get subscription count
    pub fn count(self: *SubscriptionManager) usize {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.subscriptions.items.len;
    }

    /// Check if two subscriptions are the same
    fn isSameSubscription(self: *SubscriptionManager, a: Subscription, b: Subscription) bool {
        _ = self;

        if (a.channel != b.channel) return false;

        // Compare coin if present
        if (a.coin) |a_coin| {
            if (b.coin) |b_coin| {
                if (!std.mem.eql(u8, a_coin, b_coin)) return false;
            } else {
                return false;
            }
        } else if (b.coin != null) {
            return false;
        }

        // Compare user if present
        if (a.user) |a_user| {
            if (b.user) |b_user| {
                if (!std.mem.eql(u8, a_user, b_user)) return false;
            } else {
                return false;
            }
        } else if (b.user != null) {
            return false;
        }

        return true;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "SubscriptionManager: add and count" {
    const allocator = std.testing.allocator;

    var mgr = SubscriptionManager.init(allocator);
    defer mgr.deinit();

    try mgr.add(.{ .channel = .allMids });
    try std.testing.expectEqual(@as(usize, 1), mgr.count());

    try mgr.add(.{ .channel = .l2Book, .coin = "ETH" });
    try std.testing.expectEqual(@as(usize, 2), mgr.count());
}

test "SubscriptionManager: duplicate prevention" {
    const allocator = std.testing.allocator;

    var mgr = SubscriptionManager.init(allocator);
    defer mgr.deinit();

    try mgr.add(.{ .channel = .allMids });
    try mgr.add(.{ .channel = .allMids }); // Duplicate

    try std.testing.expectEqual(@as(usize, 1), mgr.count());
}

test "SubscriptionManager: remove" {
    const allocator = std.testing.allocator;

    var mgr = SubscriptionManager.init(allocator);
    defer mgr.deinit();

    const sub = Subscription{ .channel = .allMids };
    try mgr.add(sub);
    try std.testing.expectEqual(@as(usize, 1), mgr.count());

    mgr.remove(sub);
    try std.testing.expectEqual(@as(usize, 0), mgr.count());
}

test "SubscriptionManager: clear" {
    const allocator = std.testing.allocator;

    var mgr = SubscriptionManager.init(allocator);
    defer mgr.deinit();

    try mgr.add(.{ .channel = .allMids });
    try mgr.add(.{ .channel = .l2Book, .coin = "ETH" });
    try std.testing.expectEqual(@as(usize, 2), mgr.count());

    mgr.clear();
    try std.testing.expectEqual(@as(usize, 0), mgr.count());
}

test "SubscriptionManager: remove non-existent" {
    const allocator = std.testing.allocator;

    var mgr = SubscriptionManager.init(allocator);
    defer mgr.deinit();

    try mgr.add(.{ .channel = .allMids });
    try std.testing.expectEqual(@as(usize, 1), mgr.count());

    // Try to remove a subscription that doesn't exist
    mgr.remove(.{ .channel = .l2Book, .coin = "ETH" });

    // Count should remain unchanged
    try std.testing.expectEqual(@as(usize, 1), mgr.count());
}

test "SubscriptionManager: getAll" {
    const allocator = std.testing.allocator;

    var mgr = SubscriptionManager.init(allocator);
    defer mgr.deinit();

    try mgr.add(.{ .channel = .allMids });
    try mgr.add(.{ .channel = .l2Book, .coin = "ETH" });
    try mgr.add(.{ .channel = .trades, .coin = "BTC" });

    const all = mgr.getAll();
    try std.testing.expectEqual(@as(usize, 3), all.len);
}

test "SubscriptionManager: same channel different coins" {
    const allocator = std.testing.allocator;

    var mgr = SubscriptionManager.init(allocator);
    defer mgr.deinit();

    // Add l2Book for different coins
    try mgr.add(.{ .channel = .l2Book, .coin = "ETH" });
    try mgr.add(.{ .channel = .l2Book, .coin = "BTC" });
    try mgr.add(.{ .channel = .l2Book, .coin = "SOL" });

    try std.testing.expectEqual(@as(usize, 3), mgr.count());

    // Remove one
    mgr.remove(.{ .channel = .l2Book, .coin = "BTC" });
    try std.testing.expectEqual(@as(usize, 2), mgr.count());
}

test "SubscriptionManager: user subscriptions" {
    const allocator = std.testing.allocator;

    var mgr = SubscriptionManager.init(allocator);
    defer mgr.deinit();

    try mgr.add(.{ .channel = .user, .user = "0xabc123" });
    try mgr.add(.{ .channel = .orderUpdates, .user = "0xabc123" });
    try mgr.add(.{ .channel = .userFills, .user = "0xabc123" });

    try std.testing.expectEqual(@as(usize, 3), mgr.count());
}

test "SubscriptionManager: duplicate with coin" {
    const allocator = std.testing.allocator;

    var mgr = SubscriptionManager.init(allocator);
    defer mgr.deinit();

    try mgr.add(.{ .channel = .l2Book, .coin = "ETH" });
    try mgr.add(.{ .channel = .l2Book, .coin = "ETH" }); // Duplicate

    try std.testing.expectEqual(@as(usize, 1), mgr.count());
}

test "SubscriptionManager: duplicate with user" {
    const allocator = std.testing.allocator;

    var mgr = SubscriptionManager.init(allocator);
    defer mgr.deinit();

    try mgr.add(.{ .channel = .user, .user = "0xabc123" });
    try mgr.add(.{ .channel = .user, .user = "0xabc123" }); // Duplicate

    try std.testing.expectEqual(@as(usize, 1), mgr.count());
}

test "SubscriptionManager: different users same channel" {
    const allocator = std.testing.allocator;

    var mgr = SubscriptionManager.init(allocator);
    defer mgr.deinit();

    try mgr.add(.{ .channel = .user, .user = "0xabc123" });
    try mgr.add(.{ .channel = .user, .user = "0xdef456" });

    try std.testing.expectEqual(@as(usize, 2), mgr.count());
}

test "SubscriptionManager: clear and reuse" {
    const allocator = std.testing.allocator;

    var mgr = SubscriptionManager.init(allocator);
    defer mgr.deinit();

    // Add some subscriptions
    try mgr.add(.{ .channel = .allMids });
    try mgr.add(.{ .channel = .l2Book, .coin = "ETH" });
    try std.testing.expectEqual(@as(usize, 2), mgr.count());

    // Clear
    mgr.clear();
    try std.testing.expectEqual(@as(usize, 0), mgr.count());

    // Add again
    try mgr.add(.{ .channel = .trades, .coin = "BTC" });
    try std.testing.expectEqual(@as(usize, 1), mgr.count());
}

test "SubscriptionManager: complex subscription with coin and user" {
    const allocator = std.testing.allocator;

    var mgr = SubscriptionManager.init(allocator);
    defer mgr.deinit();

    // Some subscriptions may have both coin and user
    try mgr.add(.{ .channel = .trades, .coin = "ETH", .user = "0xabc123" });
    try mgr.add(.{ .channel = .trades, .coin = "ETH", .user = "0xdef456" });
    try mgr.add(.{ .channel = .trades, .coin = "BTC", .user = "0xabc123" });

    try std.testing.expectEqual(@as(usize, 3), mgr.count());

    // Remove specific subscription
    mgr.remove(.{ .channel = .trades, .coin = "ETH", .user = "0xabc123" });
    try std.testing.expectEqual(@as(usize, 2), mgr.count());
}
