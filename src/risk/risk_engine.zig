//! RiskEngine - Pre-trade risk control (Story 040)
//!
//! Provides comprehensive risk checks before order submission:
//! - Position size limits
//! - Leverage limits
//! - Daily loss limits
//! - Order rate limits
//! - Kill Switch functionality

const std = @import("std");
const Allocator = std.mem.Allocator;
const Decimal = @import("../core/decimal.zig").Decimal;
const PositionTracker = @import("../trading/position_tracker.zig").PositionTracker;
const Account = @import("../trading/account.zig").Account;
const OrderRequest = @import("../exchange/types.zig").OrderRequest;
const TradingPair = @import("../exchange/types.zig").TradingPair;
const Side = @import("../exchange/types.zig").Side;

/// Risk Engine - Pre-trade risk control
pub const RiskEngine = struct {
    allocator: Allocator,
    config: RiskConfig,
    positions: ?*PositionTracker,
    account: *Account,

    // Daily tracking
    daily_pnl: Decimal,
    daily_start_equity: Decimal,
    last_day_start: i64,

    // Order rate tracking
    order_count_per_minute: u32,
    last_minute_start: i64,

    // Kill Switch state
    kill_switch_active: std.atomic.Value(bool),

    // Statistics
    total_checks: u64,
    rejected_orders: u64,

    const Self = @This();

    pub fn init(
        allocator: Allocator,
        config: RiskConfig,
        positions: ?*PositionTracker,
        account: *Account,
    ) Self {
        const now = std.time.timestamp();
        return .{
            .allocator = allocator,
            .config = config,
            .positions = positions,
            .account = account,
            .daily_pnl = Decimal.ZERO,
            .daily_start_equity = account.getAccountValue(),
            .last_day_start = now,
            .order_count_per_minute = 0,
            .last_minute_start = now,
            .kill_switch_active = std.atomic.Value(bool).init(false),
            .total_checks = 0,
            .rejected_orders = 0,
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    /// Check if an order passes risk controls
    pub fn checkOrder(self: *Self, order: OrderRequest) RiskCheckResult {
        self.total_checks += 1;

        // 0. Kill Switch check (highest priority)
        if (self.kill_switch_active.load(.acquire)) {
            self.rejected_orders += 1;
            return RiskCheckResult{
                .passed = false,
                .reason = .kill_switch_active,
                .message = "Kill switch is active, all trading halted",
            };
        }

        // 1. Position size check
        if (self.checkPositionSize(order)) |result| {
            self.rejected_orders += 1;
            return result;
        }

        // 2. Leverage check
        if (self.checkLeverage(order)) |result| {
            self.rejected_orders += 1;
            return result;
        }

        // 3. Daily loss check
        if (self.checkDailyLoss()) |result| {
            self.rejected_orders += 1;
            return result;
        }

        // 4. Order rate check
        if (self.checkOrderRate()) |result| {
            self.rejected_orders += 1;
            return result;
        }

        // 5. Available margin check
        if (self.checkAvailableMargin(order)) |result| {
            self.rejected_orders += 1;
            return result;
        }

        return RiskCheckResult{ .passed = true };
    }

    /// Check position size limits
    fn checkPositionSize(self: *Self, order: OrderRequest) ?RiskCheckResult {
        const price = order.price orelse Decimal.ONE;
        const order_value = order.amount.mul(price);

        // Check single order size
        if (order_value.cmp(self.config.max_position_size) == .gt) {
            return RiskCheckResult{
                .passed = false,
                .reason = .position_size_exceeded,
                .message = "Order size exceeds maximum position limit",
                .details = RiskCheckDetails{
                    .limit = self.config.max_position_size,
                    .actual = order_value,
                },
            };
        }

        // Check total position after order (integrates with PositionTracker)
        if (self.positions) |positions| {
            const coin = order.pair.base;

            // Get current position for this symbol
            var current_value = Decimal.ZERO;
            if (positions.getPosition(coin)) |pos| {
                current_value = pos.position_value;
            }

            // Calculate new position value after order
            var new_value: Decimal = undefined;
            if (order.side == .buy) {
                new_value = current_value.add(order_value);
            } else {
                // Selling reduces position (could go negative for short)
                new_value = current_value.sub(order_value);
            }

            // Check against symbol limit
            if (new_value.abs().cmp(self.config.max_position_per_symbol) == .gt) {
                return RiskCheckResult{
                    .passed = false,
                    .reason = .position_size_exceeded,
                    .message = "Total position would exceed symbol limit",
                    .details = RiskCheckDetails{
                        .limit = self.config.max_position_per_symbol,
                        .actual = new_value.abs(),
                    },
                };
            }
        } else {
            // No position tracker, just check order value against symbol limit
            if (order_value.cmp(self.config.max_position_per_symbol) == .gt) {
                return RiskCheckResult{
                    .passed = false,
                    .reason = .position_size_exceeded,
                    .message = "Order value exceeds symbol limit",
                    .details = RiskCheckDetails{
                        .limit = self.config.max_position_per_symbol,
                        .actual = order_value,
                    },
                };
            }
        }

        return null;
    }

    /// Check leverage limits
    fn checkLeverage(self: *Self, order: OrderRequest) ?RiskCheckResult {
        const account_value = self.account.getAccountValue();
        if (account_value.isZero()) {
            return RiskCheckResult{
                .passed = false,
                .reason = .insufficient_margin,
                .message = "Account equity is zero",
            };
        }

        const price = order.price orelse Decimal.ONE;
        const order_value = order.amount.mul(price);

        const current_exposure = self.calculateTotalExposure();
        const total_exposure = current_exposure.add(order_value);
        const leverage = total_exposure.div(account_value) catch Decimal.ZERO;

        if (leverage.cmp(self.config.max_leverage) == .gt) {
            return RiskCheckResult{
                .passed = false,
                .reason = .leverage_exceeded,
                .message = "Order would exceed maximum leverage",
                .details = RiskCheckDetails{
                    .limit = self.config.max_leverage,
                    .actual = leverage,
                },
            };
        }

        return null;
    }

    /// Check daily loss limits
    fn checkDailyLoss(self: *Self) ?RiskCheckResult {
        self.updateDailyPnL();

        const loss = self.daily_pnl.negate();

        // Check absolute loss
        if (loss.cmp(self.config.max_daily_loss) == .gt) {
            return RiskCheckResult{
                .passed = false,
                .reason = .daily_loss_exceeded,
                .message = "Daily loss limit reached",
                .details = RiskCheckDetails{
                    .limit = self.config.max_daily_loss,
                    .actual = loss,
                },
            };
        }

        // Check percentage loss
        if (!self.daily_start_equity.isZero()) {
            const loss_pct = (loss.div(self.daily_start_equity) catch Decimal.ZERO).toFloat();
            if (loss_pct > self.config.max_daily_loss_pct) {
                return RiskCheckResult{
                    .passed = false,
                    .reason = .daily_loss_exceeded,
                    .message = "Daily loss percentage limit reached",
                };
            }
        }

        return null;
    }

    /// Check order rate limits
    fn checkOrderRate(self: *Self) ?RiskCheckResult {
        const now = std.time.timestamp();

        // Reset if new minute
        if (now - self.last_minute_start >= 60) {
            self.order_count_per_minute = 0;
            self.last_minute_start = now;
        }

        self.order_count_per_minute += 1;

        if (self.order_count_per_minute > self.config.max_orders_per_minute) {
            return RiskCheckResult{
                .passed = false,
                .reason = .order_rate_exceeded,
                .message = "Order rate limit exceeded",
            };
        }

        return null;
    }

    /// Check available margin
    fn checkAvailableMargin(self: *Self, order: OrderRequest) ?RiskCheckResult {
        const price = order.price orelse Decimal.ONE;
        const order_value = order.amount.mul(price);
        const required_margin = order_value.div(self.config.max_leverage) catch Decimal.ZERO;
        const available_margin = self.account.getAvailableMargin();

        if (required_margin.cmp(available_margin) == .gt) {
            return RiskCheckResult{
                .passed = false,
                .reason = .insufficient_margin,
                .message = "Insufficient available margin",
                .details = RiskCheckDetails{
                    .required = required_margin,
                    .available = available_margin,
                },
            };
        }

        return null;
    }

    /// Calculate total exposure across all positions
    fn calculateTotalExposure(self: *Self) Decimal {
        // If PositionTracker is available, sum all position values
        if (self.positions) |positions| {
            const all_positions = positions.getAllPositions() catch {
                // Fall back to account data on error
                return self.account.cross_margin_summary.total_ntl_pos;
            };
            defer self.allocator.free(all_positions);

            var total_exposure = Decimal.ZERO;
            for (all_positions) |pos| {
                // Use absolute position value for exposure
                total_exposure = total_exposure.add(pos.position_value.abs());
            }
            return total_exposure;
        }

        // Fall back to account's total notional position value
        return self.account.cross_margin_summary.total_ntl_pos;
    }

    /// Update daily PnL tracking
    fn updateDailyPnL(self: *Self) void {
        const now = std.time.timestamp();
        const account_value = self.account.getAccountValue();

        // Check for new day (simplified: every 24 hours)
        if (now - self.last_day_start >= 86400) {
            self.daily_pnl = Decimal.ZERO;
            self.daily_start_equity = account_value;
            self.last_day_start = now;
        }

        // Calculate current daily PnL
        self.daily_pnl = account_value.sub(self.daily_start_equity);
    }

    /// Trigger Kill Switch - halt all trading
    pub fn killSwitch(self: *Self) void {
        self.kill_switch_active.store(true, .release);
        std.log.warn("[RISK] Kill Switch triggered!", .{});
    }

    /// Reset Kill Switch
    pub fn resetKillSwitch(self: *Self) void {
        self.kill_switch_active.store(false, .release);
        std.log.info("[RISK] Kill switch reset", .{});
    }

    /// Check if Kill Switch is active
    pub fn isKillSwitchActive(self: *Self) bool {
        return self.kill_switch_active.load(.acquire);
    }

    /// Check if Kill Switch should be triggered
    pub fn checkKillSwitchConditions(self: *Self) bool {
        self.updateDailyPnL();

        const loss = self.daily_pnl.negate();
        if (loss.cmp(self.config.kill_switch_threshold) == .gt) {
            std.log.warn("[RISK] Kill switch threshold reached", .{});
            return true;
        }

        return false;
    }

    /// Get engine statistics
    pub fn getStats(self: *Self) RiskEngineStats {
        self.updateDailyPnL();
        const exposure = self.calculateTotalExposure();
        const account_value = self.account.getAccountValue();
        const leverage = if (!account_value.isZero())
            exposure.div(account_value) catch Decimal.ZERO
        else
            Decimal.ZERO;

        const rejection_rate = if (self.total_checks > 0)
            @as(f64, @floatFromInt(self.rejected_orders)) / @as(f64, @floatFromInt(self.total_checks))
        else
            0;

        return RiskEngineStats{
            .total_checks = self.total_checks,
            .rejected_orders = self.rejected_orders,
            .rejection_rate = rejection_rate,
            .daily_pnl = self.daily_pnl,
            .current_leverage = leverage,
            .kill_switch_active = self.isKillSwitchActive(),
        };
    }
};

/// Risk Configuration
pub const RiskConfig = struct {
    /// Maximum single position size (USD)
    max_position_size: Decimal = Decimal.fromFloat(100000),

    /// Maximum position per symbol (USD)
    max_position_per_symbol: Decimal = Decimal.fromFloat(50000),

    /// Maximum leverage
    max_leverage: Decimal = Decimal.fromFloat(3.0),

    /// Maximum daily loss (absolute USD)
    max_daily_loss: Decimal = Decimal.fromFloat(5000),

    /// Maximum daily loss (percentage, 0.05 = 5%)
    max_daily_loss_pct: f64 = 0.05,

    /// Maximum drawdown (percentage)
    max_drawdown_pct: f64 = 0.20,

    /// Maximum orders per minute
    max_orders_per_minute: u32 = 60,

    /// Maximum single order value (USD)
    max_order_value: Decimal = Decimal.fromFloat(50000),

    /// Kill Switch trigger threshold (USD)
    kill_switch_threshold: Decimal = Decimal.fromFloat(10000),

    /// Close all positions when Kill Switch triggers
    close_positions_on_kill_switch: bool = true,

    /// Get default configuration
    pub fn default() RiskConfig {
        return .{};
    }

    /// Get conservative configuration
    pub fn conservative() RiskConfig {
        return .{
            .max_position_size = Decimal.fromFloat(25000),
            .max_position_per_symbol = Decimal.fromFloat(10000),
            .max_leverage = Decimal.fromFloat(1.0),
            .max_daily_loss = Decimal.fromFloat(1000),
            .max_daily_loss_pct = 0.02,
            .max_drawdown_pct = 0.10,
            .max_orders_per_minute = 30,
            .max_order_value = Decimal.fromFloat(10000),
            .kill_switch_threshold = Decimal.fromFloat(2000),
            .close_positions_on_kill_switch = true,
        };
    }
};

/// Risk Check Result
pub const RiskCheckResult = struct {
    passed: bool,
    reason: ?RiskRejectReason = null,
    message: ?[]const u8 = null,
    details: ?RiskCheckDetails = null,
};

/// Rejection Reason
pub const RiskRejectReason = enum {
    position_size_exceeded,
    leverage_exceeded,
    daily_loss_exceeded,
    order_rate_exceeded,
    insufficient_margin,
    kill_switch_active,
    symbol_not_allowed,
    order_value_exceeded,
    max_drawdown_exceeded,
};

/// Check Details
pub const RiskCheckDetails = struct {
    limit: ?Decimal = null,
    actual: ?Decimal = null,
    required: ?Decimal = null,
    available: ?Decimal = null,
};

/// Engine Statistics
pub const RiskEngineStats = struct {
    total_checks: u64,
    rejected_orders: u64,
    rejection_rate: f64,
    daily_pnl: Decimal,
    current_leverage: Decimal,
    kill_switch_active: bool,
};

// ============================================================================
// Tests
// ============================================================================

test "RiskEngine: initialization" {
    const allocator = std.testing.allocator;

    var account = Account.init();
    account.cross_margin_summary.account_value = Decimal.fromFloat(100000);

    const config = RiskConfig.default();
    var engine = RiskEngine.init(allocator, config, null, &account);
    defer engine.deinit();

    try std.testing.expect(!engine.isKillSwitchActive());
    try std.testing.expectEqual(@as(u64, 0), engine.total_checks);
}

test "RiskEngine: kill switch" {
    const allocator = std.testing.allocator;

    var account = Account.init();
    account.cross_margin_summary.account_value = Decimal.fromFloat(100000);

    var engine = RiskEngine.init(allocator, RiskConfig.default(), null, &account);
    defer engine.deinit();

    try std.testing.expect(!engine.isKillSwitchActive());

    engine.killSwitch();
    try std.testing.expect(engine.isKillSwitchActive());

    // Order should be rejected
    const order = OrderRequest{
        .pair = TradingPair{ .base = "BTC", .quote = "USDT" },
        .side = .buy,
        .order_type = .market,
        .amount = Decimal.fromFloat(0.1),
        .price = null,
        .client_order_id = null,
        .reduce_only = false,
        .time_in_force = .gtc,
    };
    const result = engine.checkOrder(order);
    try std.testing.expect(!result.passed);
    try std.testing.expectEqual(RiskRejectReason.kill_switch_active, result.reason.?);

    engine.resetKillSwitch();
    try std.testing.expect(!engine.isKillSwitchActive());
}

test "RiskEngine: order rate limit" {
    const allocator = std.testing.allocator;

    var account = Account.init();
    account.cross_margin_summary.account_value = Decimal.fromFloat(100000);

    const config = RiskConfig{
        .max_orders_per_minute = 5,
        .max_position_size = Decimal.fromFloat(1000000),
        .max_leverage = Decimal.fromFloat(10),
        .max_daily_loss = Decimal.fromFloat(100000),
    };

    var engine = RiskEngine.init(allocator, config, null, &account);
    defer engine.deinit();

    const order = OrderRequest{
        .pair = TradingPair{ .base = "BTC", .quote = "USDT" },
        .side = .buy,
        .order_type = .limit,
        .amount = Decimal.fromFloat(0.01),
        .price = Decimal.fromFloat(50000),
        .client_order_id = null,
        .reduce_only = false,
        .time_in_force = .gtc,
    };

    // First 5 should pass
    for (0..5) |_| {
        const result = engine.checkOrder(order);
        try std.testing.expect(result.passed);
    }

    // 6th should fail
    const result = engine.checkOrder(order);
    try std.testing.expect(!result.passed);
    try std.testing.expectEqual(RiskRejectReason.order_rate_exceeded, result.reason.?);
}

test "RiskEngine: stats" {
    const allocator = std.testing.allocator;

    var account = Account.init();
    account.cross_margin_summary.account_value = Decimal.fromFloat(100000);

    var engine = RiskEngine.init(allocator, RiskConfig.default(), null, &account);
    defer engine.deinit();

    const stats = engine.getStats();
    try std.testing.expectEqual(@as(u64, 0), stats.total_checks);
    try std.testing.expect(!stats.kill_switch_active);
}
