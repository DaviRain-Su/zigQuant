//! Position Manager
//!
//! Manages strategy positions including:
//! - Position list tracking
//! - PnL calculation
//! - Total exposure calculation
//! - Position lifecycle management
//!
//! Design principles:
//! - Simple and efficient position tracking
//! - Clear separation of concerns
//! - Memory-safe with proper cleanup

const std = @import("std");
const Decimal = @import("../root.zig").Decimal;
const TradingPair = @import("../root.zig").TradingPair;
const Side = @import("../root.zig").Side;
const Timestamp = @import("../root.zig").Timestamp;

// ============================================================================
// Strategy Position
// ============================================================================

/// Strategy position status
pub const PositionStatus = enum {
    open,
    closed,

    pub fn toString(self: PositionStatus) []const u8 {
        return switch (self) {
            .open => "OPEN",
            .closed => "CLOSED",
        };
    }
};

/// Strategy position (simplified for strategy framework)
pub const StrategyPosition = struct {
    /// Trading pair
    pair: TradingPair,

    /// Position side
    side: Side,

    /// Position size (absolute value)
    size: Decimal,

    /// Entry price
    entry_price: Decimal,

    /// Exit price (null if still open)
    exit_price: ?Decimal,

    /// Position status
    status: PositionStatus,

    /// Realized PnL (only set when closed)
    pnl: ?Decimal,

    /// Entry timestamp
    opened_at: Timestamp,

    /// Exit timestamp
    closed_at: ?Timestamp,

    /// Initialize a new open position
    pub fn init(
        pair: TradingPair,
        side: Side,
        size: Decimal,
        entry_price: Decimal,
    ) !StrategyPosition {
        if (size.cmp(Decimal.ZERO) != .gt) {
            return error.InvalidPositionSize;
        }
        if (entry_price.cmp(Decimal.ZERO) != .gt) {
            return error.InvalidEntryPrice;
        }

        return StrategyPosition{
            .pair = pair,
            .side = side,
            .size = size,
            .entry_price = entry_price,
            .exit_price = null,
            .status = .open,
            .pnl = null,
            .opened_at = Timestamp.now(),
            .closed_at = null,
        };
    }

    /// Close the position and calculate PnL
    pub fn close(self: *StrategyPosition, exit_price: Decimal) !void {
        if (self.status == .closed) {
            return error.PositionAlreadyClosed;
        }
        if (exit_price.cmp(Decimal.ZERO) != .gt) {
            return error.InvalidExitPrice;
        }

        self.exit_price = exit_price;
        self.status = .closed;
        self.closed_at = Timestamp.now();
        self.pnl = try self.calculatePnl();
    }

    /// Calculate PnL based on entry and exit prices
    fn calculatePnl(self: *const StrategyPosition) !Decimal {
        if (self.exit_price == null) {
            return Decimal.ZERO;
        }

        const exit_price = self.exit_price.?;
        const entry_value = self.size.mul(self.entry_price);
        const exit_value = self.size.mul(exit_price);

        return switch (self.side) {
            .buy => exit_value.sub(entry_value), // Long: profit when price goes up
            .sell => entry_value.sub(exit_value), // Short: profit when price goes down
        };
    }

    /// Calculate unrealized PnL with current market price
    pub fn calculateUnrealizedPnl(self: *const StrategyPosition, current_price: Decimal) !Decimal {
        if (self.status == .closed) {
            return self.pnl orelse Decimal.ZERO;
        }

        const entry_value = self.size.mul(self.entry_price);
        const current_value = self.size.mul(current_price);

        return switch (self.side) {
            .buy => current_value.sub(entry_value),
            .sell => entry_value.sub(current_value),
        };
    }

    /// Get position value at entry
    pub fn getEntryValue(self: *const StrategyPosition) Decimal {
        return self.size.mul(self.entry_price);
    }

    /// Check if position matches pair
    pub fn matchesPair(self: *const StrategyPosition, pair: TradingPair) bool {
        return std.mem.eql(u8, self.pair.base, pair.base) and
            std.mem.eql(u8, self.pair.quote, pair.quote);
    }
};

// ============================================================================
// Position Manager
// ============================================================================

/// Position manager for strategy execution
pub const PositionManager = struct {
    allocator: std.mem.Allocator,
    positions: std.ArrayList(StrategyPosition),

    /// Initialize position manager
    pub fn init(allocator: std.mem.Allocator) !PositionManager {
        return PositionManager{
            .allocator = allocator,
            .positions = try std.ArrayList(StrategyPosition).initCapacity(allocator, 0),
        };
    }

    /// Clean up resources
    pub fn deinit(self: *PositionManager) void {
        self.positions.deinit(self.allocator);
    }

    /// Add a new position
    pub fn addPosition(self: *PositionManager, position: StrategyPosition) !void {
        if (position.status != .open) {
            return error.CannotAddClosedPosition;
        }
        try self.positions.append(self.allocator, position);
    }

    /// Close a position by pair
    pub fn closePosition(
        self: *PositionManager,
        pair: TradingPair,
        exit_price: Decimal,
    ) !?StrategyPosition {
        for (self.positions.items, 0..) |*pos, i| {
            if (pos.matchesPair(pair) and pos.status == .open) {
                try pos.close(exit_price);
                const closed_position = pos.*;
                _ = self.positions.swapRemove(i);
                return closed_position;
            }
        }
        return null;
    }

    /// Get open position for a pair
    pub fn getPosition(self: *PositionManager, pair: TradingPair) ?*StrategyPosition {
        for (self.positions.items) |*pos| {
            if (pos.matchesPair(pair) and pos.status == .open) {
                return pos;
            }
        }
        return null;
    }

    /// Get number of open positions
    pub fn getOpenPositionCount(self: *const PositionManager) u32 {
        var count: u32 = 0;
        for (self.positions.items) |pos| {
            if (pos.status == .open) {
                count += 1;
            }
        }
        return count;
    }

    /// Calculate total exposure (sum of all open position values)
    pub fn getTotalExposure(self: *const PositionManager) Decimal {
        var total = Decimal.ZERO;
        for (self.positions.items) |pos| {
            if (pos.status == .open) {
                const value = pos.getEntryValue();
                total = total.add(value);
            }
        }
        return total;
    }

    /// Calculate total unrealized PnL
    pub fn getTotalUnrealizedPnl(
        self: *const PositionManager,
        current_prices: std.StringHashMap(Decimal),
    ) !Decimal {
        var total = Decimal.ZERO;
        for (self.positions.items) |pos| {
            if (pos.status == .open) {
                // Create key for hash map lookup
                const key = try std.fmt.allocPrint(
                    self.allocator,
                    "{s}-{s}",
                    .{ pos.pair.base, pos.pair.quote },
                );
                defer self.allocator.free(key);

                if (current_prices.get(key)) |price| {
                    const pnl = try pos.calculateUnrealizedPnl(price);
                    total = total.add(pnl);
                }
            }
        }
        return total;
    }

    /// Get all open positions
    pub fn getOpenPositions(self: *PositionManager) ![]StrategyPosition {
        var open_positions = std.ArrayList(StrategyPosition).init(self.allocator);
        defer open_positions.deinit();

        for (self.positions.items) |pos| {
            if (pos.status == .open) {
                try open_positions.append(pos);
            }
        }

        return try open_positions.toOwnedSlice();
    }

    /// Clear all positions
    pub fn clear(self: *PositionManager) void {
        self.positions.clearRetainingCapacity();
    }
};

// ============================================================================
// Tests
// ============================================================================

test "StrategyPosition: init and validation" {
    const valid = try StrategyPosition.init(
        .{ .base = "BTC", .quote = "USDT" },
        .buy,
        Decimal.fromInt(1),
        Decimal.fromInt(50000),
    );

    try std.testing.expectEqual(PositionStatus.open, valid.status);
    try std.testing.expect(valid.pnl == null);
    try std.testing.expect(valid.exit_price == null);

    // Invalid size
    const invalid_size = StrategyPosition.init(
        .{ .base = "BTC", .quote = "USDT" },
        .buy,
        Decimal.ZERO,
        Decimal.fromInt(50000),
    );
    try std.testing.expectError(error.InvalidPositionSize, invalid_size);

    // Invalid price
    const invalid_price = StrategyPosition.init(
        .{ .base = "BTC", .quote = "USDT" },
        .buy,
        Decimal.fromInt(1),
        Decimal.ZERO,
    );
    try std.testing.expectError(error.InvalidEntryPrice, invalid_price);
}

test "StrategyPosition: close and PnL calculation (long)" {
    var pos = try StrategyPosition.init(
        .{ .base = "BTC", .quote = "USDT" },
        .buy,
        Decimal.fromInt(1),
        Decimal.fromInt(50000),
    );

    // Close with profit
    try pos.close(Decimal.fromInt(51000));

    try std.testing.expectEqual(PositionStatus.closed, pos.status);
    try std.testing.expect(pos.exit_price != null);
    try std.testing.expect(pos.pnl != null);

    // PnL = (51000 - 50000) * 1 = 1000
    const expected_pnl = Decimal.fromInt(1000);
    try std.testing.expect(pos.pnl.?.eql(expected_pnl));

    // Cannot close again
    try std.testing.expectError(error.PositionAlreadyClosed, pos.close(Decimal.fromInt(52000)));
}

test "StrategyPosition: close and PnL calculation (short)" {
    var pos = try StrategyPosition.init(
        .{ .base = "BTC", .quote = "USDT" },
        .sell,
        Decimal.fromInt(1),
        Decimal.fromInt(50000),
    );

    // Close with profit (price went down)
    try pos.close(Decimal.fromInt(49000));

    // PnL = (50000 - 49000) * 1 = 1000
    const expected_pnl = Decimal.fromInt(1000);
    try std.testing.expect(pos.pnl.?.eql(expected_pnl));
}

test "StrategyPosition: unrealized PnL" {
    const pos = try StrategyPosition.init(
        .{ .base = "BTC", .quote = "USDT" },
        .buy,
        Decimal.fromInt(1),
        Decimal.fromInt(50000),
    );

    const unrealized = try pos.calculateUnrealizedPnl(Decimal.fromInt(51000));
    const expected = Decimal.fromInt(1000);
    try std.testing.expect(unrealized.eql(expected));
}

test "PositionManager: add and count positions" {
    const allocator = std.testing.allocator;
    var manager = try PositionManager.init(allocator);
    defer manager.deinit();

    try std.testing.expectEqual(@as(u32, 0), manager.getOpenPositionCount());

    const pos1 = try StrategyPosition.init(
        .{ .base = "BTC", .quote = "USDT" },
        .buy,
        Decimal.fromInt(1),
        Decimal.fromInt(50000),
    );
    try manager.addPosition(pos1);

    try std.testing.expectEqual(@as(u32, 1), manager.getOpenPositionCount());

    const pos2 = try StrategyPosition.init(
        .{ .base = "ETH", .quote = "USDT" },
        .buy,
        Decimal.fromInt(10),
        Decimal.fromInt(3000),
    );
    try manager.addPosition(pos2);

    try std.testing.expectEqual(@as(u32, 2), manager.getOpenPositionCount());
}

test "PositionManager: close position" {
    const allocator = std.testing.allocator;
    var manager = try PositionManager.init(allocator);
    defer manager.deinit();

    const pos = try StrategyPosition.init(
        .{ .base = "BTC", .quote = "USDT" },
        .buy,
        Decimal.fromInt(1),
        Decimal.fromInt(50000),
    );
    try manager.addPosition(pos);

    const closed = try manager.closePosition(
        .{ .base = "BTC", .quote = "USDT" },
        Decimal.fromInt(51000),
    );

    try std.testing.expect(closed != null);
    try std.testing.expectEqual(PositionStatus.closed, closed.?.status);
    try std.testing.expectEqual(@as(u32, 0), manager.getOpenPositionCount());

    // PnL should be 1000
    const expected_pnl = Decimal.fromInt(1000);
    try std.testing.expect(closed.?.pnl.?.eql(expected_pnl));
}

test "PositionManager: get position" {
    const allocator = std.testing.allocator;
    var manager = try PositionManager.init(allocator);
    defer manager.deinit();

    const pos = try StrategyPosition.init(
        .{ .base = "BTC", .quote = "USDT" },
        .buy,
        Decimal.fromInt(1),
        Decimal.fromInt(50000),
    );
    try manager.addPosition(pos);

    const found = manager.getPosition(.{ .base = "BTC", .quote = "USDT" });
    try std.testing.expect(found != null);
    try std.testing.expect(found.?.size.eql(Decimal.fromInt(1)));

    const not_found = manager.getPosition(.{ .base = "ETH", .quote = "USDT" });
    try std.testing.expect(not_found == null);
}

test "PositionManager: calculate total exposure" {
    const allocator = std.testing.allocator;
    var manager = try PositionManager.init(allocator);
    defer manager.deinit();

    // BTC position: 1 * 50000 = 50000
    const pos1 = try StrategyPosition.init(
        .{ .base = "BTC", .quote = "USDT" },
        .buy,
        Decimal.fromInt(1),
        Decimal.fromInt(50000),
    );
    try manager.addPosition(pos1);

    // ETH position: 10 * 3000 = 30000
    const pos2 = try StrategyPosition.init(
        .{ .base = "ETH", .quote = "USDT" },
        .buy,
        Decimal.fromInt(10),
        Decimal.fromInt(3000),
    );
    try manager.addPosition(pos2);

    const exposure = manager.getTotalExposure();
    const expected = Decimal.fromInt(80000); // 50000 + 30000
    try std.testing.expect(exposure.eql(expected));
}

test "PositionManager: no memory leak" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            @panic("Memory leak detected!");
        }
    }
    const allocator = gpa.allocator();

    var manager = try PositionManager.init(allocator);
    defer manager.deinit();

    const pos = try StrategyPosition.init(
        .{ .base = "BTC", .quote = "USDT" },
        .buy,
        Decimal.fromInt(1),
        Decimal.fromInt(50000),
    );
    try manager.addPosition(pos);

    _ = try manager.closePosition(
        .{ .base = "BTC", .quote = "USDT" },
        Decimal.fromInt(51000),
    );
}
