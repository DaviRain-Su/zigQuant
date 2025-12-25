//! Backtest Engine - Position Management
//!
//! Manages open positions and calculates P&L.

const std = @import("std");
const Decimal = @import("../core/decimal.zig").Decimal;
const Timestamp = @import("../core/time.zig").Timestamp;
const TradingPair = @import("../exchange/types.zig").TradingPair;
const PositionSide = @import("types.zig").PositionSide;
const BacktestError = @import("types.zig").BacktestError;

// ============================================================================
// Position
// ============================================================================

/// Open position tracking
pub const Position = struct {
    /// Trading pair
    pair: TradingPair,

    /// Position side (long or short)
    side: PositionSide,

    /// Position size in base asset
    size: Decimal,

    /// Entry price
    entry_price: Decimal,

    /// Entry timestamp
    entry_time: Timestamp,

    /// Unrealized P&L
    unrealized_pnl: Decimal,

    /// Initialize new position
    pub fn init(
        pair: TradingPair,
        side: PositionSide,
        size: Decimal,
        entry_price: Decimal,
        entry_time: Timestamp,
    ) Position {
        return .{
            .pair = pair,
            .side = side,
            .size = size,
            .entry_price = entry_price,
            .entry_time = entry_time,
            .unrealized_pnl = Decimal.ZERO,
        };
    }

    /// Update unrealized P&L based on current price
    pub fn updateUnrealizedPnL(self: *Position, current_price: Decimal) void {
        const price_diff = if (self.side == .long)
            // Long: profit when price up
            current_price.sub(self.entry_price)
        else
            // Short: profit when price down
            self.entry_price.sub(current_price);

        self.unrealized_pnl = price_diff.mul(self.size);
    }

    /// Calculate realized P&L for given exit price
    pub fn calculatePnL(self: *const Position, exit_price: Decimal) Decimal {
        const price_diff = if (self.side == .long)
            exit_price.sub(self.entry_price)
        else
            self.entry_price.sub(exit_price);

        return price_diff.mul(self.size);
    }

    /// Calculate return percentage
    pub fn getReturnPercent(self: *const Position, exit_price: Decimal) !f64 {
        const pnl = self.calculatePnL(exit_price);
        const cost = self.entry_price.mul(self.size);
        const return_pct = try pnl.div(cost);
        return return_pct.toFloat();
    }

    /// Get position duration in milliseconds
    pub fn getDuration(self: *const Position, current_time: Timestamp) i64 {
        return current_time.millis - self.entry_time.millis;
    }
};

// ============================================================================
// Position Manager
// ============================================================================

/// Manages position lifecycle (v0.4.0: single position only)
pub const PositionManager = struct {
    allocator: std.mem.Allocator,
    current_position: ?Position,

    pub fn init(allocator: std.mem.Allocator) PositionManager {
        return .{
            .allocator = allocator,
            .current_position = null,
        };
    }

    /// Check if has open position
    pub fn hasPosition(self: *const PositionManager) bool {
        return self.current_position != null;
    }

    /// Get current position (if any)
    pub fn getPosition(self: *PositionManager) ?*Position {
        return if (self.current_position) |*pos| pos else null;
    }

    /// Open new position
    pub fn openPosition(self: *PositionManager, pos: Position) !void {
        if (self.current_position != null) {
            return BacktestError.PositionAlreadyExists;
        }
        self.current_position = pos;
    }

    /// Close current position
    pub fn closePosition(self: *PositionManager) void {
        self.current_position = null;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "Position: long P&L calculation" {
    const testing = std.testing;

    const position = Position.init(
        TradingPair{ .base = "ETH", .quote = "USDC" },
        .long,
        Decimal.fromFloat(1.0), // size
        Decimal.fromInt(2000), // entry price
        .{ .millis = 1000 }, // entry time
    );

    // Price goes up to 2100
    const exit_price = Decimal.fromInt(2100);
    const pnl = position.calculatePnL(exit_price);

    // Expected: (2100 - 2000) × 1.0 = 100
    const expected = Decimal.fromInt(100);
    try testing.expect(pnl.eql(expected));
}

test "Position: short P&L calculation" {
    const testing = std.testing;

    const position = Position.init(
        TradingPair{ .base = "ETH", .quote = "USDC" },
        .short,
        Decimal.fromFloat(1.0),
        Decimal.fromInt(2000),
        .{ .millis = 1000 },
    );

    // Price goes down to 1900
    const exit_price = Decimal.fromInt(1900);
    const pnl = position.calculatePnL(exit_price);

    // Expected: (2000 - 1900) × 1.0 = 100
    const expected = Decimal.fromInt(100);
    try testing.expect(pnl.eql(expected));
}

test "Position: long losing trade" {
    const testing = std.testing;

    const position = Position.init(
        TradingPair{ .base = "ETH", .quote = "USDC" },
        .long,
        Decimal.fromFloat(1.0),
        Decimal.fromInt(2000),
        .{ .millis = 1000 },
    );

    // Price goes down to 1900
    const exit_price = Decimal.fromInt(1900);
    const pnl = position.calculatePnL(exit_price);

    // Expected: (1900 - 2000) × 1.0 = -100
    const expected = Decimal.fromInt(-100);
    try testing.expect(pnl.eql(expected));
}

test "Position: short losing trade" {
    const testing = std.testing;

    const position = Position.init(
        TradingPair{ .base = "ETH", .quote = "USDC" },
        .short,
        Decimal.fromFloat(1.0),
        Decimal.fromInt(2000),
        .{ .millis = 1000 },
    );

    // Price goes up to 2100
    const exit_price = Decimal.fromInt(2100);
    const pnl = position.calculatePnL(exit_price);

    // Expected: (2000 - 2100) × 1.0 = -100
    const expected = Decimal.fromInt(-100);
    try testing.expect(pnl.eql(expected));
}

test "Position: unrealized P&L update" {
    const testing = std.testing;

    var position = Position.init(
        TradingPair{ .base = "ETH", .quote = "USDC" },
        .long,
        Decimal.fromFloat(1.0),
        Decimal.fromInt(2000),
        .{ .millis = 1000 },
    );

    // Initially zero
    try testing.expect(position.unrealized_pnl.isZero());

    // Update with new price (up 50)
    position.updateUnrealizedPnL(Decimal.fromInt(2050));

    // Expected: (2050 - 2000) × 1.0 = 50
    const expected = Decimal.fromInt(50);
    try testing.expect(position.unrealized_pnl.eql(expected));

    // Update again (down 30 from entry)
    position.updateUnrealizedPnL(Decimal.fromInt(1970));

    // Expected: (1970 - 2000) × 1.0 = -30
    const expected2 = Decimal.fromInt(-30);
    try testing.expect(position.unrealized_pnl.eql(expected2));
}

test "Position: return percentage" {
    const testing = std.testing;

    const position = Position.init(
        TradingPair{ .base = "ETH", .quote = "USDC" },
        .long,
        Decimal.fromFloat(2.0), // size
        Decimal.fromInt(2000), // entry price
        .{ .millis = 1000 },
    );

    // Exit at 2100 (5% gain per unit)
    const exit_price = Decimal.fromInt(2100);
    const return_pct = try position.getReturnPercent(exit_price);

    // Return = (2100 - 2000) * 2 / (2000 * 2) = 200 / 4000 = 0.05 (5%)
    try testing.expectApproxEqAbs(@as(f64, 0.05), return_pct, 0.001);
}

test "Position: duration calculation" {
    const testing = std.testing;

    const position = Position.init(
        TradingPair{ .base = "ETH", .quote = "USDC" },
        .long,
        Decimal.fromFloat(1.0),
        Decimal.fromInt(2000),
        .{ .millis = 1000 }, // entry time
    );

    // Current time 1 hour later
    const current_time = Timestamp{ .millis = 1000 + (60 * 60 * 1000) };
    const duration = position.getDuration(current_time);

    // Expected: 1 hour = 3,600,000 ms
    try testing.expectEqual(@as(i64, 3_600_000), duration);
}

test "PositionManager: open and close position" {
    const testing = std.testing;

    var manager = PositionManager.init(testing.allocator);

    // Initially no position
    try testing.expect(!manager.hasPosition());
    try testing.expect(manager.getPosition() == null);

    // Open position
    const position = Position.init(
        TradingPair{ .base = "ETH", .quote = "USDC" },
        .long,
        Decimal.fromFloat(1.0),
        Decimal.fromInt(2000),
        .{ .millis = 1000 },
    );

    try manager.openPosition(position);
    try testing.expect(manager.hasPosition());

    // Get position
    const pos_ptr = manager.getPosition().?;
    try testing.expect(pos_ptr.pair.base[0] == 'E');
    try testing.expect(pos_ptr.side == .long);

    // Close position
    manager.closePosition();
    try testing.expect(!manager.hasPosition());
    try testing.expect(manager.getPosition() == null);
}

test "PositionManager: cannot open multiple positions" {
    const testing = std.testing;

    var manager = PositionManager.init(testing.allocator);

    const position1 = Position.init(
        TradingPair{ .base = "ETH", .quote = "USDC" },
        .long,
        Decimal.fromFloat(1.0),
        Decimal.fromInt(2000),
        .{ .millis = 1000 },
    );

    const position2 = Position.init(
        TradingPair{ .base = "BTC", .quote = "USDT" },
        .long,
        Decimal.fromFloat(0.1),
        Decimal.fromInt(50000),
        .{ .millis = 2000 },
    );

    // Open first position
    try manager.openPosition(position1);

    // Try to open second position - should fail
    try testing.expectError(
        BacktestError.PositionAlreadyExists,
        manager.openPosition(position2),
    );
}
