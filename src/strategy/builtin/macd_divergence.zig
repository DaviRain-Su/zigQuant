//! MACD Histogram Divergence Strategy
//!
//! Reversal-catching strategy that detects divergences between price and MACD histogram:
//! - **Bullish Divergence**: Price makes lower low, MACD histogram makes higher low → Buy signal
//! - **Bearish Divergence**: Price makes higher high, MACD histogram makes lower high → Sell signal
//!
//! Divergence detection logic:
//! 1. Find local extremes (peaks and troughs) in price
//! 2. Find corresponding extremes in MACD histogram
//! 3. Compare the direction of extremes to detect divergence
//!
//! Strategy Parameters:
//! - `fast_period` - MACD fast EMA period (default: 12)
//! - `slow_period` - MACD slow EMA period (default: 26)
//! - `signal_period` - MACD signal line period (default: 9)
//! - `lookback_period` - Divergence detection lookback (default: 14)
//!
//! Performance:
//! - Works best in ranging/reversal markets
//! - High win rate signals but less frequent
//! - Signal strength: 0.9 (very reliable when confirmed)

const std = @import("std");
const Decimal = @import("../../root.zig").Decimal;
const Candles = @import("../../root.zig").Candles;
const TradingPair = @import("../../root.zig").TradingPair;
const Timestamp = @import("../../root.zig").Timestamp;
const Side = @import("../../root.zig").Side;
const IStrategy = @import("../interface.zig").IStrategy;
const StrategyContext = @import("../interface.zig").StrategyContext;
const Signal = @import("../signal.zig").Signal;
const SignalType = @import("../signal.zig").SignalType;
const SignalMetadata = @import("../signal.zig").SignalMetadata;
const IndicatorValue = @import("../signal.zig").IndicatorValue;
const StrategyMetadata = @import("../types.zig").StrategyMetadata;
const StrategyParameter = @import("../types.zig").StrategyParameter;
const StrategyType = @import("../types.zig").StrategyType;
const Position = @import("../../backtest/position.zig").Position;
const Account = @import("../../backtest/account.zig").Account;
const IndicatorManager = @import("../../root.zig").IndicatorManager;
const indicator_helpers = @import("../../root.zig").indicator_helpers;
const Logger = @import("../../root.zig").Logger;
const Timeframe = @import("../../root.zig").Timeframe;

// ============================================================================
// Configuration
// ============================================================================

/// Strategy configuration
pub const Config = struct {
    /// Trading pair
    pair: TradingPair,

    /// Fast EMA period for MACD
    fast_period: u32 = 12,

    /// Slow EMA period for MACD
    slow_period: u32 = 26,

    /// Signal line period for MACD
    signal_period: u32 = 9,

    /// Lookback period for divergence detection
    lookback_period: u32 = 14,

    /// Minimum bars between peaks/troughs for valid divergence
    min_bars_between: u32 = 5,

    /// Validate configuration
    pub fn validate(self: Config) !void {
        if (self.fast_period >= self.slow_period) {
            return error.InvalidFastPeriod;
        }
        if (self.fast_period < 2) {
            return error.FastPeriodTooSmall;
        }
        if (self.lookback_period < 5) {
            return error.LookbackTooSmall;
        }
        if (self.min_bars_between < 2) {
            return error.MinBarsTooSmall;
        }
    }
};

// ============================================================================
// MACD Divergence Strategy
// ============================================================================

/// MACD Histogram Divergence Strategy
pub const MACDDivergenceStrategy = struct {
    allocator: std.mem.Allocator,
    config: Config,
    indicator_manager: IndicatorManager,
    logger: Logger,
    initialized: bool,

    /// Create a new MACD Divergence strategy instance
    pub fn create(allocator: std.mem.Allocator, config: Config) !*MACDDivergenceStrategy {
        try config.validate();

        const self = try allocator.create(MACDDivergenceStrategy);
        errdefer allocator.destroy(self);

        self.* = .{
            .allocator = allocator,
            .config = config,
            .indicator_manager = IndicatorManager.init(allocator),
            .logger = undefined,
            .initialized = false,
        };

        return self;
    }

    /// Convert to IStrategy interface
    pub fn toStrategy(self: *MACDDivergenceStrategy) IStrategy {
        return .{
            .ptr = self,
            .vtable = &vtable,
        };
    }

    /// Destroy strategy and free resources
    pub fn destroy(self: *MACDDivergenceStrategy) void {
        self.indicator_manager.deinit();
        self.allocator.destroy(self);
    }

    // ========================================================================
    // Helper functions for divergence detection
    // ========================================================================

    /// Find local minimum (trough) in the lookback window
    fn findLocalMinimum(
        values: []const Decimal,
        end_idx: usize,
        lookback: u32,
        min_bars: u32,
    ) ?struct { idx: usize, value: Decimal } {
        if (end_idx < lookback) return null;

        const start_idx = end_idx - lookback;
        var min_idx: usize = start_idx;
        var min_val = values[start_idx];

        // Find the minimum in the window
        for (start_idx..end_idx) |i| {
            if (values[i].isNaN()) continue;
            if (values[i].cmp(min_val) == .lt) {
                min_val = values[i];
                min_idx = i;
            }
        }

        // Ensure minimum is not at the edges (needs to be a true local minimum)
        if (min_idx <= start_idx + min_bars or min_idx >= end_idx - min_bars) {
            return null;
        }

        // Verify it's a local minimum (lower than neighbors)
        if (min_idx > 0 and min_idx < values.len - 1) {
            const left_higher = !values[min_idx - 1].isNaN() and
                values[min_idx - 1].cmp(min_val) == .gt;
            const right_higher = !values[min_idx + 1].isNaN() and
                values[min_idx + 1].cmp(min_val) == .gt;
            if (left_higher and right_higher) {
                return .{ .idx = min_idx, .value = min_val };
            }
        }

        return null;
    }

    /// Find local maximum (peak) in the lookback window
    fn findLocalMaximum(
        values: []const Decimal,
        end_idx: usize,
        lookback: u32,
        min_bars: u32,
    ) ?struct { idx: usize, value: Decimal } {
        if (end_idx < lookback) return null;

        const start_idx = end_idx - lookback;
        var max_idx: usize = start_idx;
        var max_val = values[start_idx];

        // Find the maximum in the window
        for (start_idx..end_idx) |i| {
            if (values[i].isNaN()) continue;
            if (values[i].cmp(max_val) == .gt) {
                max_val = values[i];
                max_idx = i;
            }
        }

        // Ensure maximum is not at the edges
        if (max_idx <= start_idx + min_bars or max_idx >= end_idx - min_bars) {
            return null;
        }

        // Verify it's a local maximum (higher than neighbors)
        if (max_idx > 0 and max_idx < values.len - 1) {
            const left_lower = !values[max_idx - 1].isNaN() and
                values[max_idx - 1].cmp(max_val) == .lt;
            const right_lower = !values[max_idx + 1].isNaN() and
                values[max_idx + 1].cmp(max_val) == .lt;
            if (left_lower and right_lower) {
                return .{ .idx = max_idx, .value = max_val };
            }
        }

        return null;
    }

    /// Detect bullish divergence (price lower low, MACD higher low)
    fn detectBullishDivergence(
        self: *MACDDivergenceStrategy,
        candles: *Candles,
        histogram: []const Decimal,
        index: usize,
    ) bool {
        if (index < self.config.lookback_period * 2) return false;

        // Get close prices directly from candles
        const candle_slice = candles.candles[0..index + 1];
        var closes_buf: [2048]Decimal = undefined;
        if (candle_slice.len > closes_buf.len) return false;

        for (candle_slice, 0..) |c, i| {
            closes_buf[i] = c.close;
        }
        const closes = closes_buf[0..candle_slice.len];

        // Find recent price trough
        const price_trough1 = findLocalMinimum(
            closes,
            index,
            self.config.lookback_period,
            self.config.min_bars_between,
        ) orelse return false;

        // Find previous price trough
        if (price_trough1.idx < self.config.lookback_period) return false;
        const price_trough2 = findLocalMinimum(
            closes,
            price_trough1.idx - self.config.min_bars_between,
            self.config.lookback_period,
            self.config.min_bars_between,
        ) orelse return false;

        // Price makes lower low
        const price_lower_low = price_trough1.value.cmp(price_trough2.value) == .lt;

        if (!price_lower_low) return false;

        // Find corresponding MACD histogram troughs
        const hist_trough1 = findLocalMinimum(
            histogram,
            index,
            self.config.lookback_period,
            self.config.min_bars_between,
        ) orelse return false;

        if (hist_trough1.idx < self.config.lookback_period) return false;
        const hist_trough2 = findLocalMinimum(
            histogram,
            hist_trough1.idx - self.config.min_bars_between,
            self.config.lookback_period,
            self.config.min_bars_between,
        ) orelse return false;

        // MACD histogram makes higher low
        const macd_higher_low = hist_trough1.value.cmp(hist_trough2.value) == .gt;

        return price_lower_low and macd_higher_low;
    }

    /// Detect bearish divergence (price higher high, MACD lower high)
    fn detectBearishDivergence(
        self: *MACDDivergenceStrategy,
        candles: *Candles,
        histogram: []const Decimal,
        index: usize,
    ) bool {
        if (index < self.config.lookback_period * 2) return false;

        // Get close prices directly from candles
        const candle_slice = candles.candles[0..index + 1];
        var closes_buf: [2048]Decimal = undefined;
        if (candle_slice.len > closes_buf.len) return false;

        for (candle_slice, 0..) |c, i| {
            closes_buf[i] = c.close;
        }
        const closes = closes_buf[0..candle_slice.len];

        // Find recent price peak
        const price_peak1 = findLocalMaximum(
            closes,
            index,
            self.config.lookback_period,
            self.config.min_bars_between,
        ) orelse return false;

        // Find previous price peak
        if (price_peak1.idx < self.config.lookback_period) return false;
        const price_peak2 = findLocalMaximum(
            closes,
            price_peak1.idx - self.config.min_bars_between,
            self.config.lookback_period,
            self.config.min_bars_between,
        ) orelse return false;

        // Price makes higher high
        const price_higher_high = price_peak1.value.cmp(price_peak2.value) == .gt;

        if (!price_higher_high) return false;

        // Find corresponding MACD histogram peaks
        const hist_peak1 = findLocalMaximum(
            histogram,
            index,
            self.config.lookback_period,
            self.config.min_bars_between,
        ) orelse return false;

        if (hist_peak1.idx < self.config.lookback_period) return false;
        const hist_peak2 = findLocalMaximum(
            histogram,
            hist_peak1.idx - self.config.min_bars_between,
            self.config.lookback_period,
            self.config.min_bars_between,
        ) orelse return false;

        // MACD histogram makes lower high
        const macd_lower_high = hist_peak1.value.cmp(hist_peak2.value) == .lt;

        return price_higher_high and macd_lower_high;
    }

    // ========================================================================
    // VTable Implementation
    // ========================================================================

    fn init(ptr: *anyopaque, ctx: StrategyContext) !void {
        const self: *MACDDivergenceStrategy = @ptrCast(@alignCast(ptr));
        self.logger = ctx.logger;
        self.initialized = true;
    }

    fn deinit(ptr: *anyopaque) void {
        const self: *MACDDivergenceStrategy = @ptrCast(@alignCast(ptr));
        self.indicator_manager.deinit();
        self.initialized = false;
    }

    fn populateIndicators(ptr: *anyopaque, candles: *Candles) !void {
        const self: *MACDDivergenceStrategy = @ptrCast(@alignCast(ptr));

        // Calculate MACD
        const macd = try indicator_helpers.getMACD(
            &self.indicator_manager,
            candles,
            self.config.fast_period,
            self.config.slow_period,
            self.config.signal_period,
        );
        defer macd.deinit();

        // Add MACD components to candles
        try candles.addIndicatorValues("macd_line", macd.macd_line);
        try candles.addIndicatorValues("macd_signal", macd.signal_line);
        try candles.addIndicatorValues("macd_histogram", macd.histogram);
    }

    fn generateEntrySignal(
        ptr: *anyopaque,
        candles: *Candles,
        index: usize,
    ) !?Signal {
        const self: *MACDDivergenceStrategy = @ptrCast(@alignCast(ptr));

        const min_data = self.config.slow_period + self.config.signal_period + self.config.lookback_period * 2;
        if (index < min_data) {
            return null;
        }

        // Get MACD histogram
        const macd_hist = candles.getIndicator("macd_histogram") orelse return null;

        const current_candle = candles.get(index) orelse return null;
        const price = current_candle.close;
        const timestamp = current_candle.timestamp;

        // Check for bullish divergence → Entry Long
        if (self.detectBullishDivergence(candles, macd_hist.values, index)) {
            const curr_hist = macd_hist.values[index];
            const macd_line = candles.getIndicator("macd_line");
            const macd_val = if (macd_line) |m| m.values[index] else Decimal.ZERO;

            const metadata = try SignalMetadata.init(
                self.allocator,
                "MACD Bullish Divergence: Price lower low, MACD higher low",
                &[_]IndicatorValue{
                    .{ .name = "macd_histogram", .value = curr_hist },
                    .{ .name = "macd_line", .value = macd_val },
                },
            );

            const signal = try Signal.init(
                .entry_long,
                self.config.pair,
                .buy,
                price,
                0.9, // High signal strength for divergence
                timestamp,
                metadata,
            );
            return signal;
        }

        // Check for bearish divergence → Entry Short
        if (self.detectBearishDivergence(candles, macd_hist.values, index)) {
            const curr_hist = macd_hist.values[index];
            const macd_line = candles.getIndicator("macd_line");
            const macd_val = if (macd_line) |m| m.values[index] else Decimal.ZERO;

            const metadata = try SignalMetadata.init(
                self.allocator,
                "MACD Bearish Divergence: Price higher high, MACD lower high",
                &[_]IndicatorValue{
                    .{ .name = "macd_histogram", .value = curr_hist },
                    .{ .name = "macd_line", .value = macd_val },
                },
            );

            const signal = try Signal.init(
                .entry_short,
                self.config.pair,
                .sell,
                price,
                0.9, // High signal strength for divergence
                timestamp,
                metadata,
            );
            return signal;
        }

        return null;
    }

    fn generateExitSignal(
        ptr: *anyopaque,
        candles: *Candles,
        position: Position,
    ) !?Signal {
        const self: *MACDDivergenceStrategy = @ptrCast(@alignCast(ptr));

        const index = candles.len() - 1;
        if (index < 2) return null;

        // Get MACD line and signal line
        const macd_line = candles.getIndicator("macd_line") orelse return null;
        const signal_line = candles.getIndicator("macd_signal") orelse return null;

        const prev_macd = macd_line.values[index - 1];
        const curr_macd = macd_line.values[index];
        const prev_signal = signal_line.values[index - 1];
        const curr_signal = signal_line.values[index];

        if (prev_macd.isNaN() or curr_macd.isNaN() or prev_signal.isNaN() or curr_signal.isNaN()) {
            return null;
        }

        const current_candle = candles.get(index) orelse return null;
        const price = current_candle.close;
        const timestamp = current_candle.timestamp;

        // Exit Long: MACD crosses below signal line
        if (position.side == .long) {
            const macd_cross_down = prev_macd.cmp(prev_signal) != .lt and
                curr_macd.cmp(curr_signal) == .lt;

            if (macd_cross_down) {
                const metadata = try SignalMetadata.init(
                    self.allocator,
                    "MACD Cross Down: Exit long position",
                    &[_]IndicatorValue{
                        .{ .name = "macd_line", .value = curr_macd },
                        .{ .name = "macd_signal", .value = curr_signal },
                    },
                );

                const signal = try Signal.init(
                    .exit_long,
                    position.pair,
                    .sell,
                    price,
                    0.8,
                    timestamp,
                    metadata,
                );
                return signal;
            }
        }

        // Exit Short: MACD crosses above signal line
        if (position.side == .short) {
            const macd_cross_up = prev_macd.cmp(prev_signal) != .gt and
                curr_macd.cmp(curr_signal) == .gt;

            if (macd_cross_up) {
                const metadata = try SignalMetadata.init(
                    self.allocator,
                    "MACD Cross Up: Exit short position",
                    &[_]IndicatorValue{
                        .{ .name = "macd_line", .value = curr_macd },
                        .{ .name = "macd_signal", .value = curr_signal },
                    },
                );

                const signal = try Signal.init(
                    .exit_short,
                    position.pair,
                    .buy,
                    price,
                    0.8,
                    timestamp,
                    metadata,
                );
                return signal;
            }
        }

        return null;
    }

    fn calculatePositionSize(
        ptr: *anyopaque,
        signal: Signal,
        account: Account,
    ) !Decimal {
        _ = ptr;

        // Use 90% of available balance (conservative due to reversal nature)
        const available = account.balance.mul(Decimal.fromFloat(0.90));
        const position_size = try available.div(signal.price);
        return position_size;
    }

    fn getParameters(ptr: *anyopaque) []const StrategyParameter {
        const self: *MACDDivergenceStrategy = @ptrCast(@alignCast(ptr));

        const params = [_]StrategyParameter{
            .{
                .name = "fast_period",
                .description = "MACD fast EMA period",
                .value = .{ .integer = @intCast(self.config.fast_period) },
            },
            .{
                .name = "slow_period",
                .description = "MACD slow EMA period",
                .value = .{ .integer = @intCast(self.config.slow_period) },
            },
            .{
                .name = "signal_period",
                .description = "MACD signal line period",
                .value = .{ .integer = @intCast(self.config.signal_period) },
            },
            .{
                .name = "lookback_period",
                .description = "Divergence detection lookback",
                .value = .{ .integer = @intCast(self.config.lookback_period) },
            },
        };

        return &params;
    }

    fn getMetadata(ptr: *anyopaque) StrategyMetadata {
        const self: *MACDDivergenceStrategy = @ptrCast(@alignCast(ptr));

        const roi_targets = [_]@import("../types.zig").ROITarget{
            .{ .time_minutes = 0, .profit_ratio = Decimal.fromFloat(0.06) }, // 6% immediate
            .{ .time_minutes = 60, .profit_ratio = Decimal.fromFloat(0.04) }, // 4% after 1hr
            .{ .time_minutes = 180, .profit_ratio = Decimal.fromFloat(0.02) }, // 2% after 3hr
        };

        const startup = self.config.slow_period + self.config.signal_period +
            self.config.lookback_period * 2;

        return .{
            .name = "MACD Histogram Divergence Strategy",
            .version = "1.0.0",
            .author = "zigQuant",
            .description = "Reversal strategy detecting divergence between price and MACD histogram",
            .strategy_type = .mean_reversion,
            .timeframe = .h4,
            .startup_candle_count = startup,
            .minimal_roi = .{ .targets = &roi_targets },
            .stoploss = Decimal.fromFloat(-0.04), // -4% stop loss (tighter for reversal)
            .trailing_stop = null,
        };
    }

    const vtable = IStrategy.VTable{
        .init = init,
        .deinit = deinit,
        .populateIndicators = populateIndicators,
        .generateEntrySignal = generateEntrySignal,
        .generateExitSignal = generateExitSignal,
        .calculatePositionSize = calculatePositionSize,
        .getParameters = getParameters,
        .getMetadata = getMetadata,
    };
};

// ============================================================================
// Tests
// ============================================================================

test "MACDDivergenceStrategy: config validation" {
    const allocator = std.testing.allocator;

    // Valid config
    {
        const config = Config{
            .pair = .{ .base = "ETH", .quote = "USDT" },
            .fast_period = 12,
            .slow_period = 26,
            .signal_period = 9,
            .lookback_period = 14,
            .min_bars_between = 5,
        };
        try config.validate();

        const strategy = try MACDDivergenceStrategy.create(allocator, config);
        defer strategy.destroy();
    }

    // Invalid: fast >= slow
    {
        const config = Config{
            .pair = .{ .base = "ETH", .quote = "USDT" },
            .fast_period = 26,
            .slow_period = 26,
            .signal_period = 9,
            .lookback_period = 14,
            .min_bars_between = 5,
        };
        try std.testing.expectError(error.InvalidFastPeriod, config.validate());
    }
}

test "MACDDivergenceStrategy: interface conversion" {
    const allocator = std.testing.allocator;

    const config = Config{
        .pair = .{ .base = "ETH", .quote = "USDT" },
        .fast_period = 12,
        .slow_period = 26,
        .signal_period = 9,
        .lookback_period = 14,
        .min_bars_between = 5,
    };

    const strategy = try MACDDivergenceStrategy.create(allocator, config);
    defer strategy.destroy();

    const interface = strategy.toStrategy();
    _ = interface;
}
