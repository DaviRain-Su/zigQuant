//! Risk Manager
//!
//! Provides risk management functionality for strategies:
//! - Position size validation
//! - Maximum open trades enforcement
//! - Total exposure limits
//! - Risk ratio calculation
//! - Position sizing (Kelly criterion)
//!
//! Design principles:
//! - Conservative risk management
//! - Clear error messages
//! - Configurable limits

const std = @import("std");
const Decimal = @import("../root.zig").Decimal;
const OrderRequest = @import("../root.zig").OrderRequest;
const StrategyConfig = @import("types.zig").StrategyConfig;
const PositionManager = @import("position_manager.zig").PositionManager;

// ============================================================================
// Risk Manager
// ============================================================================

/// Risk manager for strategy execution
pub const RiskManager = struct {
    allocator: std.mem.Allocator,
    config: StrategyConfig,

    // Risk limits
    max_position_size: Decimal, // Maximum size per position
    max_total_exposure: Decimal, // Maximum total exposure
    max_open_trades: u32, // Maximum number of open positions

    /// Initialize risk manager
    pub fn init(allocator: std.mem.Allocator, config: StrategyConfig) !RiskManager {
        const max_total_exposure = config.stake_amount.mul(Decimal.fromInt(@as(i64, config.max_open_trades)));

        return RiskManager{
            .allocator = allocator,
            .config = config,
            .max_position_size = config.stake_amount,
            .max_total_exposure = max_total_exposure,
            .max_open_trades = config.max_open_trades,
        };
    }

    /// Clean up resources
    pub fn deinit(self: *RiskManager) void {
        _ = self;
        // No dynamic allocations to clean up
    }

    /// Validate order against risk limits
    pub fn validateOrder(
        self: *RiskManager,
        order: OrderRequest,
        position_manager: *const PositionManager,
    ) !void {
        // Check 1: Maximum open trades limit
        const open_positions = position_manager.getOpenPositionCount();
        if (open_positions >= self.max_open_trades) {
            return error.MaxOpenTradesReached;
        }

        // Check 2: Position size limit
        const order_value = order.amount.mul(order.price orelse Decimal.ZERO);
        if (order_value.cmp(self.max_position_size) == .gt) {
            return error.PositionSizeTooLarge;
        }

        // Check 3: Total exposure limit
        const current_exposure = position_manager.getTotalExposure();
        const new_exposure = current_exposure.add(order_value);
        if (new_exposure.cmp(self.max_total_exposure) == .gt) {
            return error.TotalExposureTooLarge;
        }
    }

    /// Calculate current risk ratio [0.0, 1.0]
    pub fn calculateRisk(self: *RiskManager, position_manager: *const PositionManager) !f64 {
        const current_exposure = position_manager.getTotalExposure();

        if (self.max_total_exposure.isZero()) {
            return 0.0;
        }

        const risk_ratio = try current_exposure.div(self.max_total_exposure);
        return risk_ratio.toFloat();
    }

    /// Calculate suggested position size using simplified Kelly criterion
    ///
    /// Kelly formula: f = (p * b - q) / b
    /// where:
    /// - p = win rate
    /// - q = 1 - p (loss rate)
    /// - b = average win / average loss
    /// - f = fraction of capital to bet
    ///
    /// We use Kelly / 4 for safety (quarter-Kelly)
    pub fn calculatePositionSize(
        self: *RiskManager,
        win_rate: f64,
        avg_win: Decimal,
        avg_loss: Decimal,
        account_balance: Decimal,
    ) !Decimal {
        _ = self;

        // Validate inputs
        if (win_rate < 0.0 or win_rate > 1.0) {
            return error.InvalidWinRate;
        }

        if (avg_loss.isZero() or avg_loss.isNegative()) {
            // Default to 1% of account if we don't have loss data
            return account_balance.mul(Decimal.fromFloat(0.01));
        }

        if (avg_win.cmp(Decimal.ZERO) != .gt) {
            // Default to 1% if no profit data
            return account_balance.mul(Decimal.fromFloat(0.01));
        }

        // Calculate Kelly criterion
        const b_decimal = try avg_win.div(avg_loss);
        const b = b_decimal.toFloat();
        const p = win_rate;
        const q = 1.0 - win_rate;

        const kelly = (p * b - q) / b;

        // Use quarter-Kelly for safety and limit to max 10%
        const safe_kelly = @max(0.0, @min(kelly / 4.0, 0.10));

        return account_balance.mul(Decimal.fromFloat(safe_kelly));
    }

    /// Check if adding a new position would exceed risk limits
    pub fn canOpenNewPosition(
        self: *RiskManager,
        position_manager: *const PositionManager,
        position_value: Decimal,
    ) bool {
        // Check open trades limit
        if (position_manager.getOpenPositionCount() >= self.max_open_trades) {
            return false;
        }

        // Check position size
        if (position_value.cmp(self.max_position_size) == .gt) {
            return false;
        }

        // Check total exposure
        const current_exposure = position_manager.getTotalExposure();
        const new_exposure = current_exposure.add(position_value);
        if (new_exposure.cmp(self.max_total_exposure) == .gt) {
            return false;
        }

        return true;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "RiskManager: initialization" {
    const allocator = std.testing.allocator;

    const metadata = @import("types.zig").StrategyMetadata{
        .name = "Test",
        .version = "1.0",
        .author = "Test",
        .description = "Test",
    };

    const config = try StrategyConfig.init(
        allocator,
        metadata,
        .{ .base = "BTC", .quote = "USDT" },
        .h1,
        &[_]@import("types.zig").StrategyParameter{},
        null,
        null,
        3, // max_open_trades
        Decimal.fromInt(1000), // stake_amount
    );
    defer config.deinit();

    var risk_manager = try RiskManager.init(allocator, config);
    defer risk_manager.deinit();

    try std.testing.expectEqual(@as(u32, 3), risk_manager.max_open_trades);
    try std.testing.expect(risk_manager.max_position_size.eql(Decimal.fromInt(1000)));
    try std.testing.expect(risk_manager.max_total_exposure.eql(Decimal.fromInt(3000)));
}

test "RiskManager: reject order exceeding max open trades" {
    const allocator = std.testing.allocator;

    const metadata = @import("types.zig").StrategyMetadata{
        .name = "Test",
        .version = "1.0",
        .author = "Test",
        .description = "Test",
    };

    const config = try StrategyConfig.init(
        allocator,
        metadata,
        .{ .base = "BTC", .quote = "USDT" },
        .h1,
        &[_]@import("types.zig").StrategyParameter{},
        null,
        null,
        2, // max 2 open trades
        Decimal.fromInt(1000),
    );
    defer config.deinit();

    var risk_manager = try RiskManager.init(allocator, config);
    defer risk_manager.deinit();

    var position_manager = try PositionManager.init(allocator);
    defer position_manager.deinit();

    // Add 2 positions
    const StrategyPosition = @import("position_manager.zig").StrategyPosition;
    const pos1 = try StrategyPosition.init(
        .{ .base = "BTC", .quote = "USDT" },
        .buy,
        Decimal.fromFloat(0.01),
        Decimal.fromInt(50000),
    );
    try position_manager.addPosition(pos1);

    const pos2 = try StrategyPosition.init(
        .{ .base = "ETH", .quote = "USDT" },
        .buy,
        Decimal.fromFloat(0.1),
        Decimal.fromInt(3000),
    );
    try position_manager.addPosition(pos2);

    // Try to add third order
    const order = OrderRequest{
        .pair = .{ .base = "SOL", .quote = "USDT" },
        .side = .buy,
        .order_type = .market,
        .amount = Decimal.fromInt(10),
        .price = Decimal.fromInt(100),
    };

    try std.testing.expectError(
        error.MaxOpenTradesReached,
        risk_manager.validateOrder(order, &position_manager),
    );
}

test "RiskManager: reject oversized position" {
    const allocator = std.testing.allocator;

    const metadata = @import("types.zig").StrategyMetadata{
        .name = "Test",
        .version = "1.0",
        .author = "Test",
        .description = "Test",
    };

    const config = try StrategyConfig.init(
        allocator,
        metadata,
        .{ .base = "BTC", .quote = "USDT" },
        .h1,
        &[_]@import("types.zig").StrategyParameter{},
        null,
        null,
        5,
        Decimal.fromInt(1000), // max $1000 per position
    );
    defer config.deinit();

    var risk_manager = try RiskManager.init(allocator, config);
    defer risk_manager.deinit();

    var position_manager = try PositionManager.init(allocator);
    defer position_manager.deinit();

    // Order value = 0.1 * 50000 = $5000 > $1000
    const order = OrderRequest{
        .pair = .{ .base = "BTC", .quote = "USDT" },
        .side = .buy,
        .order_type = .market,
        .amount = Decimal.fromFloat(0.1),
        .price = Decimal.fromInt(50000),
    };

    try std.testing.expectError(
        error.PositionSizeTooLarge,
        risk_manager.validateOrder(order, &position_manager),
    );
}

test "RiskManager: reject excessive total exposure" {
    const allocator = std.testing.allocator;

    const metadata = @import("types.zig").StrategyMetadata{
        .name = "Test",
        .version = "1.0",
        .author = "Test",
        .description = "Test",
    };

    const config = try StrategyConfig.init(
        allocator,
        metadata,
        .{ .base = "BTC", .quote = "USDT" },
        .h1,
        &[_]@import("types.zig").StrategyParameter{},
        null,
        null,
        3,
        Decimal.fromInt(1000), // max exposure = 3 * 1000 = 3000
    );
    defer config.deinit();

    var risk_manager = try RiskManager.init(allocator, config);
    defer risk_manager.deinit();

    var position_manager = try PositionManager.init(allocator);
    defer position_manager.deinit();

    // Add position with $2500 exposure
    const StrategyPosition = @import("position_manager.zig").StrategyPosition;
    const pos1 = try StrategyPosition.init(
        .{ .base = "BTC", .quote = "USDT" },
        .buy,
        Decimal.fromFloat(0.05),
        Decimal.fromInt(50000), // 0.05 * 50000 = $2500
    );
    try position_manager.addPosition(pos1);

    // Try to add another $1000 order (total would be $3500 > $3000)
    const order = OrderRequest{
        .pair = .{ .base = "ETH", .quote = "USDT" },
        .side = .buy,
        .order_type = .market,
        .amount = Decimal.fromFloat(0.333),
        .price = Decimal.fromInt(3000), // 0.333 * 3000 = ~$1000
    };

    try std.testing.expectError(
        error.TotalExposureTooLarge,
        risk_manager.validateOrder(order, &position_manager),
    );
}

test "RiskManager: calculate risk ratio" {
    const allocator = std.testing.allocator;

    const metadata = @import("types.zig").StrategyMetadata{
        .name = "Test",
        .version = "1.0",
        .author = "Test",
        .description = "Test",
    };

    const config = try StrategyConfig.init(
        allocator,
        metadata,
        .{ .base = "BTC", .quote = "USDT" },
        .h1,
        &[_]@import("types.zig").StrategyParameter{},
        null,
        null,
        5,
        Decimal.fromInt(1000), // max exposure = 5000
    );
    defer config.deinit();

    var risk_manager = try RiskManager.init(allocator, config);
    defer risk_manager.deinit();

    var position_manager = try PositionManager.init(allocator);
    defer position_manager.deinit();

    // Add position with $2500 exposure
    const StrategyPosition = @import("position_manager.zig").StrategyPosition;
    const pos1 = try StrategyPosition.init(
        .{ .base = "BTC", .quote = "USDT" },
        .buy,
        Decimal.fromFloat(0.05),
        Decimal.fromInt(50000), // $2500
    );
    try position_manager.addPosition(pos1);

    const risk = try risk_manager.calculateRisk(&position_manager);
    // Risk ratio = 2500 / 5000 = 0.5
    try std.testing.expectApproxEqAbs(@as(f64, 0.5), risk, 0.01);
}

test "RiskManager: Kelly criterion position sizing" {
    const allocator = std.testing.allocator;

    const metadata = @import("types.zig").StrategyMetadata{
        .name = "Test",
        .version = "1.0",
        .author = "Test",
        .description = "Test",
    };

    const config = try StrategyConfig.init(
        allocator,
        metadata,
        .{ .base = "BTC", .quote = "USDT" },
        .h1,
        &[_]@import("types.zig").StrategyParameter{},
        null,
        null,
        5,
        Decimal.fromInt(1000),
    );
    defer config.deinit();

    var risk_manager = try RiskManager.init(allocator, config);
    defer risk_manager.deinit();

    const account_balance = Decimal.fromInt(10000);
    const win_rate = 0.6; // 60% win rate
    const avg_win = Decimal.fromInt(100);
    const avg_loss = Decimal.fromInt(50); // Risk/reward = 2:1

    const position_size = try risk_manager.calculatePositionSize(
        win_rate,
        avg_win,
        avg_loss,
        account_balance,
    );

    // Kelly = (0.6 * 2 - 0.4) / 2 = 0.4
    // Quarter-Kelly = 0.1 (capped at 10%)
    // Position = 10000 * 0.1 = 1000
    const expected_value = 1000.0;
    const actual_value = position_size.toFloat();
    try std.testing.expectApproxEqAbs(expected_value, actual_value, 1.0);
}

test "RiskManager: no memory leak" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            @panic("Memory leak detected!");
        }
    }
    const allocator = gpa.allocator();

    const metadata = @import("types.zig").StrategyMetadata{
        .name = "Test",
        .version = "1.0",
        .author = "Test",
        .description = "Test",
    };

    const config = try StrategyConfig.init(
        allocator,
        metadata,
        .{ .base = "BTC", .quote = "USDT" },
        .h1,
        &[_]@import("types.zig").StrategyParameter{},
        null,
        null,
        3,
        Decimal.fromInt(1000),
    );
    defer config.deinit();

    var risk_manager = try RiskManager.init(allocator, config);
    defer risk_manager.deinit();

    var position_manager = try PositionManager.init(allocator);
    defer position_manager.deinit();

    _ = try risk_manager.calculateRisk(&position_manager);
}
