//! StopLossManager - Stop Loss / Take Profit Management (Story 041)
//!
//! Provides automated stop loss and take profit management:
//! - Fixed stop loss and take profit
//! - Trailing stop (percentage or fixed distance)
//! - Time-based stop
//! - Partial close support

const std = @import("std");
const Allocator = std.mem.Allocator;
const Decimal = @import("../core/decimal.zig").Decimal;
const Position = @import("../trading/position.zig").Position;
const Side = @import("../exchange/types.zig").Side;
const IExchange = @import("../exchange/interface.zig").IExchange;
const OrderRequest = @import("../exchange/types.zig").OrderRequest;
const OrderType = @import("../exchange/types.zig").OrderType;
const TradingPair = @import("../exchange/types.zig").TradingPair;
const Order = @import("../exchange/types.zig").Order;

/// Stop execution callback type
pub const StopExecutionCallback = *const fn (
    position_id: []const u8,
    trigger: StopTrigger,
    order: ?Order,
    err: ?anyerror,
) void;

/// Stop execution result
pub const StopExecutionResult = struct {
    success: bool,
    trigger: StopTrigger,
    order: ?Order = null,
    error_message: ?[]const u8 = null,
};

/// Stop Loss Manager - Automated stop loss and take profit
pub const StopLossManager = struct {
    allocator: Allocator,
    stops: std.StringHashMap(StopConfig),
    mutex: std.Thread.Mutex,

    // Optional exchange for order execution
    exchange: ?IExchange,

    // Optional callback for stop execution
    on_stop_executed: ?StopExecutionCallback,

    // Statistics
    stops_triggered: u64,
    takes_triggered: u64,
    trailing_updates: u64,
    execution_errors: u64,

    const Self = @This();

    pub fn init(allocator: Allocator) Self {
        return .{
            .allocator = allocator,
            .stops = std.StringHashMap(StopConfig).init(allocator),
            .mutex = .{},
            .exchange = null,
            .on_stop_executed = null,
            .stops_triggered = 0,
            .takes_triggered = 0,
            .trailing_updates = 0,
            .execution_errors = 0,
        };
    }

    /// Set exchange for order execution
    pub fn setExchange(self: *Self, exchange: IExchange) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.exchange = exchange;
    }

    /// Set callback for stop execution notifications
    pub fn setExecutionCallback(self: *Self, callback: StopExecutionCallback) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.on_stop_executed = callback;
    }

    pub fn deinit(self: *Self) void {
        // Free all owned keys
        var iter = self.stops.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.stops.deinit();
    }

    /// Set fixed stop loss
    pub fn setStopLoss(
        self: *Self,
        position_id: []const u8,
        entry_price: Decimal,
        side: Side,
        price: Decimal,
        stop_type: StopType,
    ) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Validate stop loss price
        if (side == .buy and price.cmp(entry_price) != .lt) {
            return error.InvalidStopLoss; // Long stop must be below entry
        }
        if (side == .sell and price.cmp(entry_price) != .gt) {
            return error.InvalidStopLoss; // Short stop must be above entry
        }

        const config = try self.getOrCreateConfig(position_id);

        config.stop_loss = price;
        config.stop_loss_type = stop_type;
        config.last_updated = std.time.timestamp();
    }

    /// Set fixed take profit
    pub fn setTakeProfit(
        self: *Self,
        position_id: []const u8,
        entry_price: Decimal,
        side: Side,
        price: Decimal,
        stop_type: StopType,
    ) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Validate take profit price
        if (side == .buy and price.cmp(entry_price) != .gt) {
            return error.InvalidTakeProfit; // Long take profit must be above entry
        }
        if (side == .sell and price.cmp(entry_price) != .lt) {
            return error.InvalidTakeProfit; // Short take profit must be below entry
        }

        const config = try self.getOrCreateConfig(position_id);

        config.take_profit = price;
        config.take_profit_type = stop_type;
        config.last_updated = std.time.timestamp();
    }

    /// Set trailing stop (percentage)
    pub fn setTrailingStopPct(
        self: *Self,
        position_id: []const u8,
        entry_price: Decimal,
        side: Side,
        trail_pct: f64,
    ) !void {
        if (trail_pct <= 0 or trail_pct >= 1) {
            return error.InvalidTrailingPercent;
        }

        self.mutex.lock();
        defer self.mutex.unlock();

        const config = try self.getOrCreateConfig(position_id);

        config.trailing_stop_pct = trail_pct;
        config.trailing_stop_active = true;

        // Initialize trailing price
        if (side == .buy) {
            config.trailing_stop_high = entry_price;
        } else {
            config.trailing_stop_low = entry_price;
        }

        config.last_updated = std.time.timestamp();
    }

    /// Set trailing stop (fixed distance)
    pub fn setTrailingStopDistance(
        self: *Self,
        position_id: []const u8,
        entry_price: Decimal,
        side: Side,
        distance: Decimal,
    ) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const config = try self.getOrCreateConfig(position_id);

        config.trailing_stop_distance = distance;
        config.trailing_stop_active = true;

        if (side == .buy) {
            config.trailing_stop_high = entry_price;
        } else {
            config.trailing_stop_low = entry_price;
        }

        config.last_updated = std.time.timestamp();
    }

    /// Set time-based stop
    pub fn setTimeStop(
        self: *Self,
        position_id: []const u8,
        expire_timestamp: i64,
        action: TimeStopAction,
    ) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const config = try self.getOrCreateConfig(position_id);

        config.time_stop = expire_timestamp;
        config.time_stop_action = action;
        config.last_updated = std.time.timestamp();
    }

    /// Check if stop loss should trigger
    pub fn checkStopLoss(
        self: *Self,
        position_id: []const u8,
        side: Side,
        current_price: Decimal,
    ) ?StopTrigger {
        self.mutex.lock();
        defer self.mutex.unlock();

        const config = self.stops.get(position_id) orelse return null;

        // 1. Check fixed stop loss
        if (config.stop_loss) |sl| {
            if (self.shouldTriggerStopLoss(side, current_price, sl)) {
                return .stop_loss;
            }
        }

        // 2. Check fixed take profit
        if (config.take_profit) |tp| {
            if (self.shouldTriggerTakeProfit(side, current_price, tp)) {
                return .take_profit;
            }
        }

        // 3. Check trailing stop
        if (config.trailing_stop_active) {
            if (self.shouldTriggerTrailingStop(side, current_price, config)) {
                return .trailing_stop;
            }
        }

        // 4. Check time stop
        if (config.time_stop) |ts| {
            if (std.time.timestamp() >= ts) {
                return .time_stop;
            }
        }

        return null;
    }

    /// Check and execute stop loss if triggered
    /// Returns the execution result if a stop was triggered, null otherwise
    pub fn checkAndExecute(
        self: *Self,
        position_id: []const u8,
        symbol: []const u8,
        side: Side,
        quantity: Decimal,
        current_price: Decimal,
    ) ?StopExecutionResult {
        // First check if stop should trigger
        const trigger = self.checkStopLoss(position_id, side, current_price) orelse return null;

        // Execute the stop order
        return self.executeStop(position_id, symbol, side, quantity, trigger, current_price);
    }

    /// Execute a stop order via exchange
    pub fn executeStop(
        self: *Self,
        position_id: []const u8,
        symbol: []const u8,
        side: Side,
        quantity: Decimal,
        trigger: StopTrigger,
        current_price: Decimal,
    ) StopExecutionResult {
        self.mutex.lock();
        const config = self.stops.get(position_id);
        const exchange = self.exchange;
        const callback = self.on_stop_executed;
        self.mutex.unlock();

        // Determine close side (opposite of position side)
        const close_side: Side = if (side == .buy) .sell else .buy;

        // Determine order type and price based on stop config
        var order_type: OrderType = .market;
        var limit_price: ?Decimal = null;

        if (config) |cfg| {
            switch (trigger) {
                .stop_loss => {
                    if (cfg.stop_loss_type == .limit) {
                        order_type = .limit;
                        limit_price = cfg.stop_loss;
                    }
                },
                .take_profit => {
                    if (cfg.take_profit_type == .limit) {
                        order_type = .limit;
                        limit_price = cfg.take_profit;
                    }
                },
                .trailing_stop, .time_stop => {
                    // Use market order for trailing and time stops
                    order_type = .market;
                },
            }
        }

        // Calculate actual close quantity based on partial close setting
        const close_qty = if (config) |cfg|
            quantity.mul(Decimal.fromFloat(cfg.partial_close_pct))
        else
            quantity;

        // Execute if exchange is available
        if (exchange) |ex| {
            const order_request = OrderRequest{
                .pair = TradingPair{ .base = symbol, .quote = "USDC" },
                .side = close_side,
                .order_type = order_type,
                .amount = close_qty,
                .price = if (order_type == .limit) limit_price else null,
                .reduce_only = true,
            };

            const order = ex.createOrder(order_request) catch |err| {
                // Log error
                std.log.err("[STOP_LOSS] Failed to execute {s} for {s}: {}", .{
                    @tagName(trigger),
                    position_id,
                    err,
                });

                self.mutex.lock();
                self.execution_errors += 1;
                self.mutex.unlock();

                // Call callback with error
                if (callback) |cb| {
                    cb(position_id, trigger, null, err);
                }

                return StopExecutionResult{
                    .success = false,
                    .trigger = trigger,
                    .error_message = "Order execution failed",
                };
            };

            // Success - update stats and call callback
            self.markTriggered(position_id, trigger);

            std.log.info("[STOP_LOSS] Executed {s} for {s}: order_id={}, price={d:.2}", .{
                @tagName(trigger),
                position_id,
                order.id,
                current_price.toFloat(),
            });

            if (callback) |cb| {
                cb(position_id, trigger, order, null);
            }

            return StopExecutionResult{
                .success = true,
                .trigger = trigger,
                .order = order,
            };
        } else {
            // No exchange - just mark as triggered and log
            self.markTriggered(position_id, trigger);

            std.log.warn("[STOP_LOSS] {s} triggered for {s} but no exchange set - manual execution required", .{
                @tagName(trigger),
                position_id,
            });

            if (callback) |cb| {
                cb(position_id, trigger, null, null);
            }

            return StopExecutionResult{
                .success = true, // Trigger was successful, just not executed
                .trigger = trigger,
            };
        }
    }

    /// Update trailing stop price (call on price update)
    pub fn updateTrailingStop(
        self: *Self,
        position_id: []const u8,
        side: Side,
        current_price: Decimal,
    ) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const config = self.stops.getPtr(position_id) orelse return;

        if (!config.trailing_stop_active) return;

        switch (side) {
            .buy => {
                // Long: track highest price
                if (config.trailing_stop_high) |high| {
                    if (current_price.cmp(high) == .gt) {
                        config.trailing_stop_high = current_price;
                        self.trailing_updates += 1;
                    }
                } else {
                    config.trailing_stop_high = current_price;
                }
            },
            .sell => {
                // Short: track lowest price
                if (config.trailing_stop_low) |low| {
                    if (current_price.cmp(low) == .lt) {
                        config.trailing_stop_low = current_price;
                        self.trailing_updates += 1;
                    }
                } else {
                    config.trailing_stop_low = current_price;
                }
            },
        }
    }

    /// Mark stop as triggered (call after execution)
    pub fn markTriggered(self: *Self, position_id: []const u8, trigger: StopTrigger) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        switch (trigger) {
            .stop_loss, .trailing_stop => self.stops_triggered += 1,
            .take_profit => self.takes_triggered += 1,
            .time_stop => {},
        }

        // Remove config after trigger (assuming full close)
        if (self.stops.fetchRemove(position_id)) |kv| {
            self.allocator.free(kv.key);
        }
    }

    /// Get stop config for a position
    pub fn getConfig(self: *Self, position_id: []const u8) ?StopConfig {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.stops.get(position_id);
    }

    /// Cancel stop loss
    pub fn cancelStopLoss(self: *Self, position_id: []const u8) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.stops.getPtr(position_id)) |config| {
            config.stop_loss = null;
            config.last_updated = std.time.timestamp();
        }
    }

    /// Cancel take profit
    pub fn cancelTakeProfit(self: *Self, position_id: []const u8) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.stops.getPtr(position_id)) |config| {
            config.take_profit = null;
            config.last_updated = std.time.timestamp();
        }
    }

    /// Cancel trailing stop
    pub fn cancelTrailingStop(self: *Self, position_id: []const u8) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.stops.getPtr(position_id)) |config| {
            config.trailing_stop_active = false;
            config.trailing_stop_pct = null;
            config.trailing_stop_distance = null;
            config.trailing_stop_high = null;
            config.trailing_stop_low = null;
            config.last_updated = std.time.timestamp();
        }
    }

    /// Remove all stop settings for a position
    pub fn removeAll(self: *Self, position_id: []const u8) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.stops.fetchRemove(position_id)) |kv| {
            self.allocator.free(kv.key);
        }
    }

    /// Get statistics
    pub fn getStats(self: *Self) StopLossStats {
        self.mutex.lock();
        defer self.mutex.unlock();

        return .{
            .stops_triggered = self.stops_triggered,
            .takes_triggered = self.takes_triggered,
            .trailing_updates = self.trailing_updates,
            .active_stops = self.stops.count(),
            .execution_errors = self.execution_errors,
            .has_exchange = self.exchange != null,
        };
    }

    // Internal helpers

    fn getOrCreateConfig(self: *Self, position_id: []const u8) !*StopConfig {
        if (self.stops.getPtr(position_id)) |config| {
            return config;
        }

        const key = try self.allocator.dupe(u8, position_id);
        errdefer self.allocator.free(key);

        try self.stops.put(key, StopConfig{});
        return self.stops.getPtr(position_id).?;
    }

    fn shouldTriggerStopLoss(_: *Self, side: Side, current: Decimal, stop: Decimal) bool {
        return switch (side) {
            .buy => current.cmp(stop) != .gt, // Long: current <= stop
            .sell => current.cmp(stop) != .lt, // Short: current >= stop
        };
    }

    fn shouldTriggerTakeProfit(_: *Self, side: Side, current: Decimal, take: Decimal) bool {
        return switch (side) {
            .buy => current.cmp(take) != .lt, // Long: current >= take
            .sell => current.cmp(take) != .gt, // Short: current <= take
        };
    }

    fn shouldTriggerTrailingStop(_: *Self, side: Side, current: Decimal, config: StopConfig) bool {
        // Calculate trailing stop price
        const stop_price: ?Decimal = switch (side) {
            .buy => blk: {
                const high = config.trailing_stop_high orelse break :blk null;
                if (config.trailing_stop_pct) |pct| {
                    break :blk high.mul(Decimal.fromFloat(1.0 - pct));
                } else if (config.trailing_stop_distance) |dist| {
                    break :blk high.sub(dist);
                } else {
                    break :blk null;
                }
            },
            .sell => blk: {
                const low = config.trailing_stop_low orelse break :blk null;
                if (config.trailing_stop_pct) |pct| {
                    break :blk low.mul(Decimal.fromFloat(1.0 + pct));
                } else if (config.trailing_stop_distance) |dist| {
                    break :blk low.add(dist);
                } else {
                    break :blk null;
                }
            },
        };

        if (stop_price) |sp| {
            return switch (side) {
                .buy => current.cmp(sp) != .gt,
                .sell => current.cmp(sp) != .lt,
            };
        }

        return false;
    }

    /// Calculate trailing stop price for display
    pub fn getTrailingStopPrice(self: *Self, position_id: []const u8, side: Side) ?Decimal {
        self.mutex.lock();
        defer self.mutex.unlock();

        const config = self.stops.get(position_id) orelse return null;

        if (!config.trailing_stop_active) return null;

        return switch (side) {
            .buy => blk: {
                const high = config.trailing_stop_high orelse break :blk null;
                if (config.trailing_stop_pct) |pct| {
                    break :blk high.mul(Decimal.fromFloat(1.0 - pct));
                } else if (config.trailing_stop_distance) |dist| {
                    break :blk high.sub(dist);
                } else {
                    break :blk null;
                }
            },
            .sell => blk: {
                const low = config.trailing_stop_low orelse break :blk null;
                if (config.trailing_stop_pct) |pct| {
                    break :blk low.mul(Decimal.fromFloat(1.0 + pct));
                } else if (config.trailing_stop_distance) |dist| {
                    break :blk low.add(dist);
                } else {
                    break :blk null;
                }
            },
        };
    }
};

/// Stop Configuration
pub const StopConfig = struct {
    // Fixed stop loss
    stop_loss: ?Decimal = null,
    stop_loss_type: StopType = .market,

    // Fixed take profit
    take_profit: ?Decimal = null,
    take_profit_type: StopType = .market,

    // Trailing stop
    trailing_stop_pct: ?f64 = null,
    trailing_stop_distance: ?Decimal = null,
    trailing_stop_active: bool = false,
    trailing_stop_high: ?Decimal = null, // Long: track highest price
    trailing_stop_low: ?Decimal = null, // Short: track lowest price

    // Partial close
    partial_close_pct: f64 = 1.0, // 1.0 = full close

    // Time stop
    time_stop: ?i64 = null, // Expiration timestamp
    time_stop_action: TimeStopAction = .close,

    // Timestamps
    created_at: i64 = 0,
    last_updated: i64 = 0,
};

/// Stop Order Type
pub const StopType = enum {
    market, // Market order
    limit, // Limit order
    stop_limit, // Stop-limit order
};

/// Time Stop Action
pub const TimeStopAction = enum {
    close, // Close position
    reduce, // Reduce position
    alert_only, // Alert only
};

/// Stop Trigger Type
pub const StopTrigger = enum {
    stop_loss,
    take_profit,
    trailing_stop,
    time_stop,
};

/// Stop Loss Statistics
pub const StopLossStats = struct {
    stops_triggered: u64,
    takes_triggered: u64,
    trailing_updates: u64,
    active_stops: usize,
    execution_errors: u64,
    has_exchange: bool,
};

// ============================================================================
// Tests
// ============================================================================

test "StopLossManager: initialization" {
    const allocator = std.testing.allocator;

    var manager = StopLossManager.init(allocator);
    defer manager.deinit();

    const stats = manager.getStats();
    try std.testing.expectEqual(@as(u64, 0), stats.stops_triggered);
    try std.testing.expectEqual(@as(usize, 0), stats.active_stops);
}

test "StopLossManager: set stop loss" {
    const allocator = std.testing.allocator;

    var manager = StopLossManager.init(allocator);
    defer manager.deinit();

    const entry = Decimal.fromFloat(50000);
    const stop = Decimal.fromFloat(49000);

    // Valid long stop loss (below entry)
    try manager.setStopLoss("pos-001", entry, .buy, stop, .market);

    const config = manager.getConfig("pos-001");
    try std.testing.expect(config != null);
    try std.testing.expect(config.?.stop_loss != null);

    // Invalid stop loss (above entry for long)
    const bad_stop = Decimal.fromFloat(51000);
    try std.testing.expectError(error.InvalidStopLoss, manager.setStopLoss("pos-002", entry, .buy, bad_stop, .market));
}

test "StopLossManager: set take profit" {
    const allocator = std.testing.allocator;

    var manager = StopLossManager.init(allocator);
    defer manager.deinit();

    const entry = Decimal.fromFloat(50000);
    const take = Decimal.fromFloat(55000);

    // Valid long take profit (above entry)
    try manager.setTakeProfit("pos-001", entry, .buy, take, .market);

    const config = manager.getConfig("pos-001");
    try std.testing.expect(config != null);
    try std.testing.expect(config.?.take_profit != null);
}

test "StopLossManager: trailing stop" {
    const allocator = std.testing.allocator;

    var manager = StopLossManager.init(allocator);
    defer manager.deinit();

    const entry = Decimal.fromFloat(50000);

    // Set 5% trailing stop
    try manager.setTrailingStopPct("pos-001", entry, .buy, 0.05);

    // Price goes up
    manager.updateTrailingStop("pos-001", .buy, Decimal.fromFloat(52000));
    manager.updateTrailingStop("pos-001", .buy, Decimal.fromFloat(54000));

    // Check trailing stop price (should be 54000 * 0.95 = 51300)
    const stop_price = manager.getTrailingStopPrice("pos-001", .buy);
    try std.testing.expect(stop_price != null);

    const expected = Decimal.fromFloat(54000 * 0.95);
    const diff = stop_price.?.sub(expected).abs();
    try std.testing.expect(diff.cmp(Decimal.fromFloat(1)) == .lt);
}

test "StopLossManager: check stop trigger" {
    const allocator = std.testing.allocator;

    var manager = StopLossManager.init(allocator);
    defer manager.deinit();

    const entry = Decimal.fromFloat(50000);
    const stop = Decimal.fromFloat(49000);
    const take = Decimal.fromFloat(55000);

    try manager.setStopLoss("pos-001", entry, .buy, stop, .market);
    try manager.setTakeProfit("pos-001", entry, .buy, take, .market);

    // Price above stop, below take - no trigger
    const trigger1 = manager.checkStopLoss("pos-001", .buy, Decimal.fromFloat(50500));
    try std.testing.expect(trigger1 == null);

    // Price hits stop loss
    const trigger2 = manager.checkStopLoss("pos-001", .buy, Decimal.fromFloat(48900));
    try std.testing.expectEqual(StopTrigger.stop_loss, trigger2.?);
}

test "StopLossManager: short position stops" {
    const allocator = std.testing.allocator;

    var manager = StopLossManager.init(allocator);
    defer manager.deinit();

    const entry = Decimal.fromFloat(50000);

    // Short stop loss must be above entry
    try manager.setStopLoss("short-001", entry, .sell, Decimal.fromFloat(51000), .market);

    // Short take profit must be below entry
    try manager.setTakeProfit("short-001", entry, .sell, Decimal.fromFloat(48000), .market);

    // Check trigger for short position
    const trigger = manager.checkStopLoss("short-001", .sell, Decimal.fromFloat(51500));
    try std.testing.expectEqual(StopTrigger.stop_loss, trigger.?);
}

test "StopLossManager: cancel and remove" {
    const allocator = std.testing.allocator;

    var manager = StopLossManager.init(allocator);
    defer manager.deinit();

    const entry = Decimal.fromFloat(50000);
    try manager.setStopLoss("pos-001", entry, .buy, Decimal.fromFloat(49000), .market);
    try manager.setTakeProfit("pos-001", entry, .buy, Decimal.fromFloat(55000), .market);

    manager.cancelStopLoss("pos-001");
    const config = manager.getConfig("pos-001");
    try std.testing.expect(config.?.stop_loss == null);
    try std.testing.expect(config.?.take_profit != null);

    manager.removeAll("pos-001");
    try std.testing.expect(manager.getConfig("pos-001") == null);
}

test "StopLossManager: stats tracking" {
    const allocator = std.testing.allocator;

    var manager = StopLossManager.init(allocator);
    defer manager.deinit();

    const entry = Decimal.fromFloat(50000);
    try manager.setStopLoss("pos-001", entry, .buy, Decimal.fromFloat(49000), .market);

    manager.markTriggered("pos-001", .stop_loss);

    const stats = manager.getStats();
    try std.testing.expectEqual(@as(u64, 1), stats.stops_triggered);
    try std.testing.expectEqual(@as(usize, 0), stats.active_stops); // removed after trigger
}
