//! 批量信号生成模块
//!
//! 基于指标数据批量生成交易信号，支持多种信号类型。

const std = @import("std");
const Allocator = std.mem.Allocator;

/// SIMD 向量大小
const SIMD_WIDTH = 4;
const Vec4 = @Vector(SIMD_WIDTH, f64);

/// 信号方向
pub const SignalDirection = enum(i8) {
    short = -1,
    neutral = 0,
    long = 1,
};

/// 交易信号
pub const Signal = struct {
    direction: SignalDirection,
    strength: f64, // 信号强度 [0, 1]
    timestamp: i64 = 0,

    pub const NEUTRAL: Signal = .{ .direction = .neutral, .strength = 0.0 };
    pub const LONG: Signal = .{ .direction = .long, .strength = 1.0 };
    pub const SHORT: Signal = .{ .direction = .short, .strength = 1.0 };
};

/// 批量信号生成器
pub const BatchSignalGenerator = struct {
    allocator: Allocator,
    use_simd: bool,

    const Self = @This();

    pub fn init(allocator: Allocator, use_simd: bool) Self {
        return .{
            .allocator = allocator,
            .use_simd = use_simd,
        };
    }

    /// 生成双均线交叉信号
    /// 金叉 (快线上穿慢线) -> Long
    /// 死叉 (快线下穿慢线) -> Short
    pub fn generateCrossSignals(
        self: *Self,
        fast_ma: []const f64,
        slow_ma: []const f64,
        timestamps: []const i64,
        result: []Signal,
    ) void {
        _ = self;
        std.debug.assert(fast_ma.len == slow_ma.len);
        std.debug.assert(fast_ma.len == result.len);
        std.debug.assert(fast_ma.len == timestamps.len);

        if (fast_ma.len == 0) return;

        // 第一个信号为中性
        result[0] = .{
            .direction = .neutral,
            .strength = 0.0,
            .timestamp = timestamps[0],
        };

        // 初始状态
        var prev_above = if (std.math.isNan(fast_ma[0]) or std.math.isNan(slow_ma[0]))
            false
        else
            fast_ma[0] > slow_ma[0];

        for (1..fast_ma.len) |i| {
            // 跳过 NaN 值
            if (std.math.isNan(fast_ma[i]) or std.math.isNan(slow_ma[i])) {
                result[i] = .{
                    .direction = .neutral,
                    .strength = 0.0,
                    .timestamp = timestamps[i],
                };
                continue;
            }

            const curr_above = fast_ma[i] > slow_ma[i];

            if (curr_above and !prev_above) {
                // 金叉 - 买入信号
                const strength = @min((fast_ma[i] - slow_ma[i]) / slow_ma[i] * 100, 1.0);
                result[i] = .{
                    .direction = .long,
                    .strength = @max(strength, 0.1),
                    .timestamp = timestamps[i],
                };
            } else if (!curr_above and prev_above) {
                // 死叉 - 卖出信号
                const strength = @min((slow_ma[i] - fast_ma[i]) / slow_ma[i] * 100, 1.0);
                result[i] = .{
                    .direction = .short,
                    .strength = @max(strength, 0.1),
                    .timestamp = timestamps[i],
                };
            } else {
                result[i] = .{
                    .direction = .neutral,
                    .strength = 0.0,
                    .timestamp = timestamps[i],
                };
            }

            prev_above = curr_above;
        }
    }

    /// 生成 RSI 信号
    /// RSI < oversold -> Long
    /// RSI > overbought -> Short
    pub fn generateRSISignals(
        self: *Self,
        rsi: []const f64,
        timestamps: []const i64,
        oversold: f64,
        overbought: f64,
        result: []Signal,
    ) void {
        std.debug.assert(rsi.len == result.len);
        std.debug.assert(rsi.len == timestamps.len);

        if (self.use_simd and rsi.len >= SIMD_WIDTH) {
            self.generateRSISignalsSimd(rsi, timestamps, oversold, overbought, result);
        } else {
            self.generateRSISignalsScalar(rsi, timestamps, oversold, overbought, result);
        }
    }

    fn generateRSISignalsSimd(
        _: *Self,
        rsi: []const f64,
        timestamps: []const i64,
        oversold: f64,
        overbought: f64,
        result: []Signal,
    ) void {
        const oversold_vec: Vec4 = @splat(oversold);
        const overbought_vec: Vec4 = @splat(overbought);
        const hundred: Vec4 = @splat(100.0);

        var i: usize = 0;

        // SIMD 批量处理
        while (i + SIMD_WIDTH <= rsi.len) : (i += SIMD_WIDTH) {
            const r: Vec4 = rsi[i..][0..SIMD_WIDTH].*;

            // 检查每个值
            inline for (0..SIMD_WIDTH) |j| {
                const idx = i + j;
                if (std.math.isNan(r[j])) {
                    result[idx] = .{
                        .direction = .neutral,
                        .strength = 0.0,
                        .timestamp = timestamps[idx],
                    };
                } else if (r[j] < oversold_vec[j]) {
                    const strength = (oversold_vec[j] - r[j]) / oversold_vec[j];
                    result[idx] = .{
                        .direction = .long,
                        .strength = @min(strength, 1.0),
                        .timestamp = timestamps[idx],
                    };
                } else if (r[j] > overbought_vec[j]) {
                    const strength = (r[j] - overbought_vec[j]) / (hundred[j] - overbought_vec[j]);
                    result[idx] = .{
                        .direction = .short,
                        .strength = @min(strength, 1.0),
                        .timestamp = timestamps[idx],
                    };
                } else {
                    result[idx] = .{
                        .direction = .neutral,
                        .strength = 0.0,
                        .timestamp = timestamps[idx],
                    };
                }
            }
        }

        // 处理剩余元素
        while (i < rsi.len) : (i += 1) {
            const r = rsi[i];
            if (std.math.isNan(r)) {
                result[i] = .{
                    .direction = .neutral,
                    .strength = 0.0,
                    .timestamp = timestamps[i],
                };
            } else if (r < oversold) {
                result[i] = .{
                    .direction = .long,
                    .strength = @min((oversold - r) / oversold, 1.0),
                    .timestamp = timestamps[i],
                };
            } else if (r > overbought) {
                result[i] = .{
                    .direction = .short,
                    .strength = @min((r - overbought) / (100 - overbought), 1.0),
                    .timestamp = timestamps[i],
                };
            } else {
                result[i] = .{
                    .direction = .neutral,
                    .strength = 0.0,
                    .timestamp = timestamps[i],
                };
            }
        }
    }

    fn generateRSISignalsScalar(
        _: *Self,
        rsi: []const f64,
        timestamps: []const i64,
        oversold: f64,
        overbought: f64,
        result: []Signal,
    ) void {
        for (rsi, timestamps, 0..) |r, ts, i| {
            if (std.math.isNan(r)) {
                result[i] = .{
                    .direction = .neutral,
                    .strength = 0.0,
                    .timestamp = ts,
                };
            } else if (r < oversold) {
                result[i] = .{
                    .direction = .long,
                    .strength = @min((oversold - r) / oversold, 1.0),
                    .timestamp = ts,
                };
            } else if (r > overbought) {
                result[i] = .{
                    .direction = .short,
                    .strength = @min((r - overbought) / (100 - overbought), 1.0),
                    .timestamp = ts,
                };
            } else {
                result[i] = .{
                    .direction = .neutral,
                    .strength = 0.0,
                    .timestamp = ts,
                };
            }
        }
    }

    /// 生成布林带信号
    /// Price < Lower Band -> Long
    /// Price > Upper Band -> Short
    pub fn generateBollingerSignals(
        _: *Self,
        prices: []const f64,
        upper: []const f64,
        middle: []const f64,
        lower: []const f64,
        timestamps: []const i64,
        result: []Signal,
    ) void {
        std.debug.assert(prices.len == result.len);

        for (prices, upper, middle, lower, timestamps, 0..) |price, u, m, l, ts, i| {
            if (std.math.isNan(u) or std.math.isNan(l) or std.math.isNan(m)) {
                result[i] = .{
                    .direction = .neutral,
                    .strength = 0.0,
                    .timestamp = ts,
                };
                continue;
            }

            if (price < l) {
                // 价格低于下轨 - 超卖
                const band_width = u - l;
                const strength = if (band_width > 0) @min((l - price) / band_width, 1.0) else 0.5;
                result[i] = .{
                    .direction = .long,
                    .strength = strength,
                    .timestamp = ts,
                };
            } else if (price > u) {
                // 价格高于上轨 - 超买
                const band_width = u - l;
                const strength = if (band_width > 0) @min((price - u) / band_width, 1.0) else 0.5;
                result[i] = .{
                    .direction = .short,
                    .strength = strength,
                    .timestamp = ts,
                };
            } else {
                result[i] = .{
                    .direction = .neutral,
                    .strength = 0.0,
                    .timestamp = ts,
                };
            }
        }
    }

    /// 生成 MACD 信号
    /// MACD 上穿 Signal -> Long
    /// MACD 下穿 Signal -> Short
    pub fn generateMACDSignals(
        _: *Self,
        macd_line: []const f64,
        signal_line: []const f64,
        histogram: []const f64,
        timestamps: []const i64,
        result: []Signal,
    ) void {
        std.debug.assert(macd_line.len == result.len);

        if (macd_line.len == 0) return;

        result[0] = .{
            .direction = .neutral,
            .strength = 0.0,
            .timestamp = timestamps[0],
        };

        var prev_above = if (std.math.isNan(macd_line[0]) or std.math.isNan(signal_line[0]))
            false
        else
            macd_line[0] > signal_line[0];

        for (1..macd_line.len) |i| {
            if (std.math.isNan(macd_line[i]) or std.math.isNan(signal_line[i])) {
                result[i] = .{
                    .direction = .neutral,
                    .strength = 0.0,
                    .timestamp = timestamps[i],
                };
                continue;
            }

            const curr_above = macd_line[i] > signal_line[i];
            const hist = histogram[i];

            if (curr_above and !prev_above) {
                // MACD 上穿信号线
                const strength = if (!std.math.isNan(hist)) @min(@abs(hist) * 10, 1.0) else 0.5;
                result[i] = .{
                    .direction = .long,
                    .strength = strength,
                    .timestamp = timestamps[i],
                };
            } else if (!curr_above and prev_above) {
                // MACD 下穿信号线
                const strength = if (!std.math.isNan(hist)) @min(@abs(hist) * 10, 1.0) else 0.5;
                result[i] = .{
                    .direction = .short,
                    .strength = strength,
                    .timestamp = timestamps[i],
                };
            } else {
                result[i] = .{
                    .direction = .neutral,
                    .strength = 0.0,
                    .timestamp = timestamps[i],
                };
            }

            prev_above = curr_above;
        }
    }

    /// 合并多个信号 (多数投票)
    pub fn combineSignals(
        self: *Self,
        signals: []const []const Signal,
        timestamps: []const i64,
        result: []Signal,
    ) void {
        _ = self;
        if (signals.len == 0) return;

        const len = result.len;
        for (0..len) |i| {
            var long_votes: i32 = 0;
            var short_votes: i32 = 0;
            var total_strength: f64 = 0;
            var count: f64 = 0;

            for (signals) |signal_array| {
                if (i < signal_array.len) {
                    const sig = signal_array[i];
                    switch (sig.direction) {
                        .long => {
                            long_votes += 1;
                            total_strength += sig.strength;
                        },
                        .short => {
                            short_votes += 1;
                            total_strength += sig.strength;
                        },
                        .neutral => {},
                    }
                    count += 1;
                }
            }

            if (long_votes > short_votes and long_votes > 0) {
                result[i] = .{
                    .direction = .long,
                    .strength = total_strength / count,
                    .timestamp = timestamps[i],
                };
            } else if (short_votes > long_votes and short_votes > 0) {
                result[i] = .{
                    .direction = .short,
                    .strength = total_strength / count,
                    .timestamp = timestamps[i],
                };
            } else {
                result[i] = .{
                    .direction = .neutral,
                    .strength = 0.0,
                    .timestamp = timestamps[i],
                };
            }
        }
    }

    /// 过滤信号 (移除连续相同方向的信号)
    pub fn filterConsecutiveSignals(
        _: *Self,
        signals: []Signal,
    ) void {
        if (signals.len < 2) return;

        var last_direction = signals[0].direction;

        for (signals[1..]) |*sig| {
            if (sig.direction == last_direction and sig.direction != .neutral) {
                sig.* = .{
                    .direction = .neutral,
                    .strength = 0.0,
                    .timestamp = sig.timestamp,
                };
            } else if (sig.direction != .neutral) {
                last_direction = sig.direction;
            }
        }
    }
};

// ============================================================================
// 单元测试
// ============================================================================

test "cross signal generation - golden cross" {
    const allocator = std.testing.allocator;
    var generator = BatchSignalGenerator.init(allocator, true);

    // 模拟金叉场景: 快线从下向上穿越慢线
    const fast_ma = [_]f64{ 10.0, 11.0, 12.0, 13.0, 14.0 };
    const slow_ma = [_]f64{ 12.0, 12.0, 12.0, 12.0, 12.0 };
    const timestamps = [_]i64{ 1000, 1060, 1120, 1180, 1240 };
    var signals: [5]Signal = undefined;

    generator.generateCrossSignals(&fast_ma, &slow_ma, &timestamps, &signals);

    // 在索引 2 处应该有金叉 (fast 从 11 -> 12, slow = 12)
    // 实际上索引 3 处 fast > slow
    try std.testing.expectEqual(SignalDirection.neutral, signals[0].direction);
    try std.testing.expectEqual(SignalDirection.neutral, signals[1].direction);
    try std.testing.expectEqual(SignalDirection.neutral, signals[2].direction); // 正好相等
    try std.testing.expectEqual(SignalDirection.long, signals[3].direction); // 金叉
}

test "cross signal generation - death cross" {
    const allocator = std.testing.allocator;
    var generator = BatchSignalGenerator.init(allocator, true);

    // 模拟死叉场景: 快线从上向下穿越慢线
    const fast_ma = [_]f64{ 14.0, 13.0, 12.0, 11.0, 10.0 };
    const slow_ma = [_]f64{ 12.0, 12.0, 12.0, 12.0, 12.0 };
    const timestamps = [_]i64{ 1000, 1060, 1120, 1180, 1240 };
    var signals: [5]Signal = undefined;

    generator.generateCrossSignals(&fast_ma, &slow_ma, &timestamps, &signals);

    // 在索引 3 处应该有死叉 (fast 从 12 -> 11, slow = 12)
    try std.testing.expectEqual(SignalDirection.neutral, signals[0].direction);
    try std.testing.expectEqual(SignalDirection.neutral, signals[1].direction);
    try std.testing.expectEqual(SignalDirection.short, signals[2].direction); // 死叉 (或正好)
}

test "RSI signal generation" {
    const allocator = std.testing.allocator;
    var generator = BatchSignalGenerator.init(allocator, true);

    const rsi = [_]f64{ 25.0, 30.0, 50.0, 75.0, 85.0 };
    const timestamps = [_]i64{ 1000, 1060, 1120, 1180, 1240 };
    var signals: [5]Signal = undefined;

    generator.generateRSISignals(&rsi, &timestamps, 30.0, 70.0, &signals);

    // RSI < 30 -> Long
    try std.testing.expectEqual(SignalDirection.long, signals[0].direction);
    // RSI == 30 -> Neutral (边界)
    try std.testing.expectEqual(SignalDirection.neutral, signals[1].direction);
    // RSI == 50 -> Neutral
    try std.testing.expectEqual(SignalDirection.neutral, signals[2].direction);
    // RSI > 70 -> Short
    try std.testing.expectEqual(SignalDirection.short, signals[3].direction);
    try std.testing.expectEqual(SignalDirection.short, signals[4].direction);
}

test "filter consecutive signals" {
    const allocator = std.testing.allocator;
    var generator = BatchSignalGenerator.init(allocator, true);

    var signals = [_]Signal{
        .{ .direction = .long, .strength = 1.0, .timestamp = 1000 },
        .{ .direction = .long, .strength = 0.8, .timestamp = 1060 }, // 连续 long
        .{ .direction = .neutral, .strength = 0.0, .timestamp = 1120 },
        .{ .direction = .short, .strength = 1.0, .timestamp = 1180 },
        .{ .direction = .short, .strength = 0.9, .timestamp = 1240 }, // 连续 short
    };

    generator.filterConsecutiveSignals(&signals);

    try std.testing.expectEqual(SignalDirection.long, signals[0].direction);
    try std.testing.expectEqual(SignalDirection.neutral, signals[1].direction); // 被过滤
    try std.testing.expectEqual(SignalDirection.neutral, signals[2].direction);
    try std.testing.expectEqual(SignalDirection.short, signals[3].direction);
    try std.testing.expectEqual(SignalDirection.neutral, signals[4].direction); // 被过滤
}
