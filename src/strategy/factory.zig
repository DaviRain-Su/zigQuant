//! Strategy Factory
//!
//! Creates strategy instances from name and JSON configuration.
//! Provides a unified interface for managing strategy lifecycle.
//!
//! Supported Strategies:
//! - `dual_ma` - Dual Moving Average Strategy
//! - `rsi_mean_reversion` - RSI Mean Reversion Strategy
//! - `bollinger_breakout` - Bollinger Bands Breakout Strategy
//!
//! Usage:
//! ```zig
//! var factory = StrategyFactory.init(allocator);
//! const config_json = try std.fs.cwd().readFileAlloc(allocator, "config.json", 1024*1024);
//! defer allocator.free(config_json);
//!
//! var wrapper = try factory.create("dual_ma", config_json);
//! defer wrapper.deinit();
//!
//! const strategy = wrapper.interface;
//! try strategy.init();
//! const signal = try strategy.analyze(&candles, timestamp);
//! ```

const std = @import("std");
const Decimal = @import("../root.zig").Decimal;
const TradingPair = @import("../root.zig").TradingPair;
const Timeframe = @import("../root.zig").Timeframe;
const IStrategy = @import("./interface.zig").IStrategy;

const DualMAStrategy = @import("./builtin/dual_ma.zig").DualMAStrategy;
const DualMAConfig = @import("./builtin/dual_ma.zig").Config;
const MAType = @import("./builtin/dual_ma.zig").MAType;
const RSIMeanReversionStrategy = @import("./builtin/mean_reversion.zig").RSIMeanReversionStrategy;
const RSIConfig = @import("./builtin/mean_reversion.zig").Config;
const BollingerBreakoutStrategy = @import("./builtin/breakout.zig").BollingerBreakoutStrategy;
const BollingerConfig = @import("./builtin/breakout.zig").Config;
const GridStrategy = @import("./builtin/grid.zig").GridStrategy;
const GridConfig = @import("./builtin/grid.zig").Config;

// ============================================================================
// Errors
// ============================================================================

pub const StrategyFactoryError = error{
    UnknownStrategy,
    InvalidConfig,
    MissingParameter,
    InvalidParameter,
    ConfigLoadFailed,
};

// ============================================================================
// Strategy Wrapper
// ============================================================================

/// Wrapper for strategy lifecycle management
pub const StrategyWrapper = struct {
    strategy_ptr: *anyopaque,
    interface: IStrategy,
    destroy_fn: *const fn (*anyopaque) void,

    /// Cleanup strategy resources
    pub fn deinit(self: *StrategyWrapper) void {
        self.destroy_fn(self.strategy_ptr);
    }
};

// ============================================================================
// Strategy Metadata
// ============================================================================

const StrategyInfo = struct {
    name: []const u8,
    description: []const u8,
};

const strategy_list = [_]StrategyInfo{
    .{ .name = "dual_ma", .description = "Dual Moving Average Strategy" },
    .{ .name = "rsi_mean_reversion", .description = "RSI Mean Reversion Strategy" },
    .{ .name = "bollinger_breakout", .description = "Bollinger Bands Breakout Strategy" },
    .{ .name = "grid", .description = "Grid Trading Strategy" },
};

// ============================================================================
// Strategy Factory
// ============================================================================

pub const StrategyFactory = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) StrategyFactory {
        return .{ .allocator = allocator };
    }

    /// Create strategy from name and JSON config
    pub fn create(
        self: *StrategyFactory,
        strategy_name: []const u8,
        config_json: []const u8,
    ) !StrategyWrapper {
        // Parse JSON
        const parsed = std.json.parseFromSlice(
            std.json.Value,
            self.allocator,
            config_json,
            .{},
        ) catch return StrategyFactoryError.InvalidConfig;
        defer parsed.deinit();

        const root = parsed.value;

        // Dispatch to appropriate strategy
        if (std.mem.eql(u8, strategy_name, "dual_ma")) {
            return try self.createDualMA(root);
        } else if (std.mem.eql(u8, strategy_name, "rsi_mean_reversion")) {
            return try self.createRSIMeanReversion(root);
        } else if (std.mem.eql(u8, strategy_name, "bollinger_breakout")) {
            return try self.createBollingerBreakout(root);
        } else if (std.mem.eql(u8, strategy_name, "grid")) {
            return try self.createGrid(root);
        } else {
            return StrategyFactoryError.UnknownStrategy;
        }
    }

    /// List all available strategies
    pub fn listStrategies(self: *const StrategyFactory) []const StrategyInfo {
        _ = self;
        return &strategy_list;
    }

    // ------------------------------------------------------------------------
    // Dual MA Strategy
    // ------------------------------------------------------------------------

    fn createDualMA(self: *StrategyFactory, root: std.json.Value) !StrategyWrapper {
        const pair = try self.parseTradingPair(root, "pair");

        const params_obj = root.object.get("parameters") orelse
            return StrategyFactoryError.MissingParameter;

        const fast_period = try self.getU32(params_obj, "fast_period", 10);
        const slow_period = try self.getU32(params_obj, "slow_period", 20);

        const ma_type_str = try self.getString(params_obj, "ma_type", "sma");
        const ma_type: MAType = if (std.mem.eql(u8, ma_type_str, "sma"))
            .sma
        else if (std.mem.eql(u8, ma_type_str, "ema"))
            .ema
        else
            return StrategyFactoryError.InvalidParameter;

        const config = DualMAConfig{
            .pair = pair,
            .fast_period = fast_period,
            .slow_period = slow_period,
            .ma_type = ma_type,
        };

        try config.validate();

        const strategy = try DualMAStrategy.create(self.allocator, config);

        return StrategyWrapper{
            .strategy_ptr = strategy,
            .interface = strategy.toStrategy(),
            .destroy_fn = destroyDualMA,
        };
    }

    fn destroyDualMA(ptr: *anyopaque) void {
        const strategy: *DualMAStrategy = @ptrCast(@alignCast(ptr));
        strategy.destroy();
    }

    // ------------------------------------------------------------------------
    // RSI Mean Reversion Strategy
    // ------------------------------------------------------------------------

    fn createRSIMeanReversion(self: *StrategyFactory, root: std.json.Value) !StrategyWrapper {
        const pair = try self.parseTradingPair(root, "pair");

        const params_obj = root.object.get("parameters") orelse
            return StrategyFactoryError.MissingParameter;

        const rsi_period = try self.getU32(params_obj, "rsi_period", 14);
        const oversold_threshold = try self.getU32(params_obj, "oversold_threshold", 30);
        const overbought_threshold = try self.getU32(params_obj, "overbought_threshold", 70);
        const exit_rsi_level = try self.getU32(params_obj, "exit_rsi_level", 50);
        const enable_long = try self.getBool(params_obj, "enable_long", true);
        const enable_short = try self.getBool(params_obj, "enable_short", true);

        const config = RSIConfig{
            .pair = pair,
            .rsi_period = rsi_period,
            .oversold_threshold = oversold_threshold,
            .overbought_threshold = overbought_threshold,
            .exit_rsi_level = exit_rsi_level,
            .enable_long = enable_long,
            .enable_short = enable_short,
        };

        try config.validate();

        const strategy = try RSIMeanReversionStrategy.create(self.allocator, config);

        return StrategyWrapper{
            .strategy_ptr = strategy,
            .interface = strategy.toStrategy(),
            .destroy_fn = destroyRSIMeanReversion,
        };
    }

    fn destroyRSIMeanReversion(ptr: *anyopaque) void {
        const strategy: *RSIMeanReversionStrategy = @ptrCast(@alignCast(ptr));
        strategy.destroy();
    }

    // ------------------------------------------------------------------------
    // Bollinger Breakout Strategy
    // ------------------------------------------------------------------------

    fn createBollingerBreakout(self: *StrategyFactory, root: std.json.Value) !StrategyWrapper {
        const pair = try self.parseTradingPair(root, "pair");

        const params_obj = root.object.get("parameters") orelse
            return StrategyFactoryError.MissingParameter;

        const bb_period = try self.getU32(params_obj, "bb_period", 20);
        const bb_std_dev = try self.getF64(params_obj, "bb_std_dev", 2.0);
        const breakout_threshold = try self.getF64(params_obj, "breakout_threshold", 0.001);
        const enable_long = try self.getBool(params_obj, "enable_long", true);
        const enable_short = try self.getBool(params_obj, "enable_short", true);
        const use_volume_filter = try self.getBool(params_obj, "use_volume_filter", false);
        const volume_multiplier = try self.getF64(params_obj, "volume_multiplier", 1.5);

        const config = BollingerConfig{
            .pair = pair,
            .bb_period = bb_period,
            .bb_std_dev = bb_std_dev,
            .breakout_threshold = breakout_threshold,
            .enable_long = enable_long,
            .enable_short = enable_short,
            .use_volume_filter = use_volume_filter,
            .volume_multiplier = volume_multiplier,
        };

        try config.validate();

        const strategy = try BollingerBreakoutStrategy.create(self.allocator, config);

        return StrategyWrapper{
            .strategy_ptr = strategy,
            .interface = strategy.toStrategy(),
            .destroy_fn = destroyBollingerBreakout,
        };
    }

    fn destroyBollingerBreakout(ptr: *anyopaque) void {
        const strategy: *BollingerBreakoutStrategy = @ptrCast(@alignCast(ptr));
        strategy.destroy();
    }

    // ------------------------------------------------------------------------
    // Grid Strategy
    // ------------------------------------------------------------------------

    fn createGrid(self: *StrategyFactory, root: std.json.Value) !StrategyWrapper {
        const pair = try self.parseTradingPair(root, "pair");

        const params_obj = root.object.get("parameters") orelse
            return StrategyFactoryError.MissingParameter;

        // Required parameters
        const upper_price = try self.getDecimal(params_obj, "upper_price", null);
        const lower_price = try self.getDecimal(params_obj, "lower_price", null);

        if (upper_price == null or lower_price == null) {
            return StrategyFactoryError.MissingParameter;
        }

        // Optional parameters with defaults
        const grid_count = try self.getU32(params_obj, "grid_count", 10);
        const order_size = try self.getDecimal(params_obj, "order_size", Decimal.fromFloat(0.001));
        const take_profit_pct = try self.getF64(params_obj, "take_profit_pct", 0.5);
        const enable_long = try self.getBool(params_obj, "enable_long", true);
        const enable_short = try self.getBool(params_obj, "enable_short", false);
        const max_position = try self.getDecimal(params_obj, "max_position", Decimal.fromFloat(1.0));

        const config = GridConfig{
            .pair = pair,
            .upper_price = upper_price.?,
            .lower_price = lower_price.?,
            .grid_count = grid_count,
            .order_size = order_size.?,
            .take_profit_pct = take_profit_pct,
            .enable_long = enable_long,
            .enable_short = enable_short,
            .max_position = max_position.?,
        };

        try config.validate();

        const strategy = try GridStrategy.create(self.allocator, config);

        return StrategyWrapper{
            .strategy_ptr = strategy,
            .interface = strategy.toStrategy(),
            .destroy_fn = destroyGrid,
        };
    }

    fn destroyGrid(ptr: *anyopaque) void {
        const strategy: *GridStrategy = @ptrCast(@alignCast(ptr));
        strategy.destroy();
    }

    // ------------------------------------------------------------------------
    // JSON Parsing Helpers
    // ------------------------------------------------------------------------

    fn parseTradingPair(self: *StrategyFactory, root: std.json.Value, key: []const u8) !TradingPair {
        _ = self;
        const pair_obj = root.object.get(key) orelse return StrategyFactoryError.MissingParameter;

        const base = pair_obj.object.get("base") orelse return StrategyFactoryError.MissingParameter;
        const quote = pair_obj.object.get("quote") orelse return StrategyFactoryError.MissingParameter;

        if (base != .string or quote != .string) {
            return StrategyFactoryError.InvalidParameter;
        }

        return TradingPair{
            .base = base.string,
            .quote = quote.string,
        };
    }

    fn getU32(self: *StrategyFactory, obj: std.json.Value, key: []const u8, default: u32) !u32 {
        _ = self;
        const value = obj.object.get(key) orelse return default;

        return switch (value) {
            .integer => |i| if (i >= 0 and i <= std.math.maxInt(u32))
                @intCast(i)
            else
                return StrategyFactoryError.InvalidParameter,
            else => return StrategyFactoryError.InvalidParameter,
        };
    }

    fn getF64(self: *StrategyFactory, obj: std.json.Value, key: []const u8, default: f64) !f64 {
        _ = self;
        const value = obj.object.get(key) orelse return default;

        return switch (value) {
            .float => |f| f,
            .integer => |i| @floatFromInt(i),
            else => return StrategyFactoryError.InvalidParameter,
        };
    }

    fn getBool(self: *StrategyFactory, obj: std.json.Value, key: []const u8, default: bool) !bool {
        _ = self;
        const value = obj.object.get(key) orelse return default;

        return switch (value) {
            .bool => |b| b,
            else => return StrategyFactoryError.InvalidParameter,
        };
    }

    fn getString(self: *StrategyFactory, obj: std.json.Value, key: []const u8, default: []const u8) ![]const u8 {
        _ = self;
        const value = obj.object.get(key) orelse return default;

        return switch (value) {
            .string => |s| s,
            else => return StrategyFactoryError.InvalidParameter,
        };
    }

    fn getDecimal(self: *StrategyFactory, obj: std.json.Value, key: []const u8, default: ?Decimal) !?Decimal {
        _ = self;
        const value = obj.object.get(key) orelse return default;

        return switch (value) {
            .float => |f| Decimal.fromFloat(f),
            .integer => |i| Decimal.fromInt(i),
            .string => |s| Decimal.fromString(s) catch return StrategyFactoryError.InvalidParameter,
            else => return StrategyFactoryError.InvalidParameter,
        };
    }
};

// ============================================================================
// Tests
// ============================================================================

test "StrategyFactory: list strategies" {
    const testing = std.testing;
    var factory = StrategyFactory.init(testing.allocator);

    const strategies = factory.listStrategies();
    try testing.expectEqual(@as(usize, 4), strategies.len);
    try testing.expectEqualStrings("dual_ma", strategies[0].name);
    try testing.expectEqualStrings("rsi_mean_reversion", strategies[1].name);
    try testing.expectEqualStrings("bollinger_breakout", strategies[2].name);
    try testing.expectEqualStrings("grid", strategies[3].name);
}

test "StrategyFactory: create dual_ma" {
    const testing = std.testing;
    var factory = StrategyFactory.init(testing.allocator);

    const config_json =
        \\{
        \\  "strategy": "dual_ma",
        \\  "pair": { "base": "BTC", "quote": "USDC" },
        \\  "timeframe": "h1",
        \\  "parameters": {
        \\    "fast_period": 10,
        \\    "slow_period": 20,
        \\    "ma_type": "sma"
        \\  }
        \\}
    ;

    var wrapper = try factory.create("dual_ma", config_json);
    defer wrapper.deinit();

    const strategy = wrapper.interface;
    const metadata = strategy.getMetadata();
    try testing.expectEqualStrings("Dual Moving Average Strategy", metadata.name);
}

test "StrategyFactory: create rsi_mean_reversion" {
    const testing = std.testing;
    var factory = StrategyFactory.init(testing.allocator);

    const config_json =
        \\{
        \\  "strategy": "rsi_mean_reversion",
        \\  "pair": { "base": "BTC", "quote": "USDC" },
        \\  "timeframe": "h1",
        \\  "parameters": {
        \\    "rsi_period": 14,
        \\    "oversold_threshold": 30,
        \\    "overbought_threshold": 70,
        \\    "exit_rsi_level": 50
        \\  }
        \\}
    ;

    var wrapper = try factory.create("rsi_mean_reversion", config_json);
    defer wrapper.deinit();

    const strategy = wrapper.interface;
    const metadata = strategy.getMetadata();
    try testing.expectEqualStrings("RSI Mean Reversion Strategy", metadata.name);
}

test "StrategyFactory: create bollinger_breakout" {
    const testing = std.testing;
    var factory = StrategyFactory.init(testing.allocator);

    const config_json =
        \\{
        \\  "strategy": "bollinger_breakout",
        \\  "pair": { "base": "BTC", "quote": "USDC" },
        \\  "timeframe": "h1",
        \\  "parameters": {
        \\    "bb_period": 20,
        \\    "bb_std_dev": 2.0,
        \\    "breakout_threshold": 0.001
        \\  }
        \\}
    ;

    var wrapper = try factory.create("bollinger_breakout", config_json);
    defer wrapper.deinit();

    const strategy = wrapper.interface;
    const metadata = strategy.getMetadata();
    try testing.expectEqualStrings("Bollinger Bands Breakout Strategy", metadata.name);
}

test "StrategyFactory: unknown strategy" {
    const testing = std.testing;
    var factory = StrategyFactory.init(testing.allocator);

    const config_json =
        \\{
        \\  "strategy": "unknown_strategy",
        \\  "pair": { "base": "BTC", "quote": "USDC" }
        \\}
    ;

    const result = factory.create("unknown_strategy", config_json);
    try testing.expectError(StrategyFactoryError.UnknownStrategy, result);
}

test "StrategyFactory: invalid JSON" {
    const testing = std.testing;
    var factory = StrategyFactory.init(testing.allocator);

    const config_json = "{ invalid json }";

    const result = factory.create("dual_ma", config_json);
    try testing.expectError(StrategyFactoryError.InvalidConfig, result);
}

test "StrategyFactory: missing parameters" {
    const testing = std.testing;
    var factory = StrategyFactory.init(testing.allocator);

    const config_json =
        \\{
        \\  "strategy": "dual_ma",
        \\  "pair": { "base": "BTC", "quote": "USDC" }
        \\}
    ;

    // Missing "parameters" field should fail
    const result = factory.create("dual_ma", config_json);
    try testing.expectError(StrategyFactoryError.MissingParameter, result);
}
