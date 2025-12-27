//! SIMD 加速指标计算模块
//!
//! 利用 Zig 的 @Vector 类型实现 SIMD 加速的技术指标计算。
//! 提供标量回退以支持不同 CPU 架构。

const std = @import("std");
const Allocator = std.mem.Allocator;

/// SIMD 向量大小 (使用 4 元素向量适配 AVX2)
const SIMD_WIDTH = 4;
const Vec4 = @Vector(SIMD_WIDTH, f64);

/// SIMD 指标计算器
pub const SimdIndicators = struct {
    allocator: Allocator,
    use_simd: bool,

    const Self = @This();

    pub fn init(allocator: Allocator, use_simd: bool) Self {
        return .{
            .allocator = allocator,
            .use_simd = use_simd,
        };
    }

    /// 计算简单移动平均线 (SMA)
    /// 使用 SIMD 批量计算多个 SMA 值
    pub fn computeSMA(self: *const Self, prices: []const f64, period: usize, result: []f64) void {
        if (prices.len < period or result.len < prices.len) return;

        // 前 period-1 个值设为 NaN
        for (0..period - 1) |i| {
            result[i] = std.math.nan(f64);
        }

        if (self.use_simd and prices.len >= period + SIMD_WIDTH) {
            self.computeSMASimd(prices, period, result);
        } else {
            self.computeSMAScalar(prices, period, result);
        }
    }

    fn computeSMASimd(self: *const Self, prices: []const f64, period: usize, result: []f64) void {
        _ = self;

        // 计算第一个完整 SMA 值
        var sum: f64 = 0;
        for (0..period) |i| {
            sum += prices[i];
        }
        result[period - 1] = sum / @as(f64, @floatFromInt(period));

        // 使用滑动窗口计算剩余值
        var i: usize = period;
        const period_f: f64 = @floatFromInt(period);

        // SIMD 批量处理
        while (i + SIMD_WIDTH <= prices.len) : (i += SIMD_WIDTH) {
            // 加载新值和旧值
            const new_vals: Vec4 = prices[i..][0..SIMD_WIDTH].*;
            const old_vals: Vec4 = prices[i - period ..][0..SIMD_WIDTH].*;

            // 计算差值
            const diff = new_vals - old_vals;

            // 逐个更新 (因为 SMA 有依赖关系)
            inline for (0..SIMD_WIDTH) |j| {
                sum += diff[j];
                result[i + j] = sum / period_f;
            }
        }

        // 处理剩余元素 (标量)
        while (i < prices.len) : (i += 1) {
            sum += prices[i] - prices[i - period];
            result[i] = sum / period_f;
        }
    }

    fn computeSMAScalar(_: *const Self, prices: []const f64, period: usize, result: []f64) void {
        var sum: f64 = 0;
        for (0..period) |i| {
            sum += prices[i];
        }
        result[period - 1] = sum / @as(f64, @floatFromInt(period));

        for (period..prices.len) |i| {
            sum += prices[i] - prices[i - period];
            result[i] = sum / @as(f64, @floatFromInt(period));
        }
    }

    /// 计算指数移动平均线 (EMA)
    /// EMA 有严格的数据依赖，无法完全向量化，但优化内存访问
    pub fn computeEMA(_: *const Self, prices: []const f64, period: usize, result: []f64) void {
        if (prices.len == 0 or result.len < prices.len) return;

        const multiplier = 2.0 / @as(f64, @floatFromInt(period + 1));

        // 第一个值使用 SMA 作为初始值
        var sum: f64 = 0;
        for (0..@min(period, prices.len)) |i| {
            sum += prices[i];
            result[i] = std.math.nan(f64);
        }

        if (prices.len < period) return;

        // 第一个 EMA 值
        result[period - 1] = sum / @as(f64, @floatFromInt(period));

        // 计算后续 EMA 值
        for (period..prices.len) |i| {
            result[i] = (prices[i] - result[i - 1]) * multiplier + result[i - 1];
        }
    }

    /// 计算相对强弱指数 (RSI)
    pub fn computeRSI(self: *Self, prices: []const f64, period: usize, result: []f64) !void {
        if (prices.len < period + 1 or result.len < prices.len) return;

        // 分配临时数组存储涨跌幅
        const changes = try self.allocator.alloc(f64, prices.len - 1);
        defer self.allocator.free(changes);

        const gains = try self.allocator.alloc(f64, prices.len - 1);
        defer self.allocator.free(gains);

        const losses = try self.allocator.alloc(f64, prices.len - 1);
        defer self.allocator.free(losses);

        // 1. 计算价格变化 (可 SIMD 化)
        self.computeChanges(prices, changes);

        // 2. 分离涨跌
        self.separateGainsLosses(changes, gains, losses);

        // 3. 计算平均涨跌幅和 RSI
        self.computeRSIFromGainsLosses(gains, losses, period, result);
    }

    fn computeChanges(self: *const Self, prices: []const f64, changes: []f64) void {
        if (self.use_simd and prices.len >= SIMD_WIDTH + 1) {
            var i: usize = 0;
            while (i + SIMD_WIDTH < prices.len) : (i += SIMD_WIDTH) {
                const curr: Vec4 = prices[i + 1 ..][0..SIMD_WIDTH].*;
                const prev: Vec4 = prices[i..][0..SIMD_WIDTH].*;
                const diff = curr - prev;
                changes[i..][0..SIMD_WIDTH].* = diff;
            }
            // 处理剩余
            while (i + 1 < prices.len) : (i += 1) {
                changes[i] = prices[i + 1] - prices[i];
            }
        } else {
            for (0..prices.len - 1) |i| {
                changes[i] = prices[i + 1] - prices[i];
            }
        }
    }

    fn separateGainsLosses(self: *const Self, changes: []const f64, gains: []f64, losses: []f64) void {
        if (self.use_simd and changes.len >= SIMD_WIDTH) {
            const zeros: Vec4 = @splat(0.0);

            var i: usize = 0;
            while (i + SIMD_WIDTH <= changes.len) : (i += SIMD_WIDTH) {
                const ch: Vec4 = changes[i..][0..SIMD_WIDTH].*;

                // gains = max(changes, 0)
                const g = @max(ch, zeros);
                // losses = abs(min(changes, 0))
                const l = @abs(@min(ch, zeros));

                gains[i..][0..SIMD_WIDTH].* = g;
                losses[i..][0..SIMD_WIDTH].* = l;
            }
            // 处理剩余
            while (i < changes.len) : (i += 1) {
                if (changes[i] > 0) {
                    gains[i] = changes[i];
                    losses[i] = 0;
                } else {
                    gains[i] = 0;
                    losses[i] = -changes[i];
                }
            }
        } else {
            for (changes, 0..) |ch, i| {
                if (ch > 0) {
                    gains[i] = ch;
                    losses[i] = 0;
                } else {
                    gains[i] = 0;
                    losses[i] = -ch;
                }
            }
        }
    }

    fn computeRSIFromGainsLosses(_: *const Self, gains: []const f64, losses: []const f64, period: usize, result: []f64) void {
        // 前 period 个值设为 NaN
        for (0..period) |i| {
            result[i] = std.math.nan(f64);
        }

        // 计算初始平均涨跌幅
        var avg_gain: f64 = 0;
        var avg_loss: f64 = 0;
        for (0..period) |i| {
            avg_gain += gains[i];
            avg_loss += losses[i];
        }
        avg_gain /= @floatFromInt(period);
        avg_loss /= @floatFromInt(period);

        // 计算第一个 RSI
        if (avg_loss == 0) {
            result[period] = 100;
        } else {
            const rs = avg_gain / avg_loss;
            result[period] = 100 - (100 / (1 + rs));
        }

        // 使用 Wilder 平滑计算后续 RSI
        const period_f: f64 = @floatFromInt(period);
        for (period..gains.len) |i| {
            avg_gain = (avg_gain * (period_f - 1) + gains[i]) / period_f;
            avg_loss = (avg_loss * (period_f - 1) + losses[i]) / period_f;

            if (avg_loss == 0) {
                result[i + 1] = 100;
            } else {
                const rs = avg_gain / avg_loss;
                result[i + 1] = 100 - (100 / (1 + rs));
            }
        }
    }

    /// 计算布林带
    pub fn computeBollingerBands(
        self: *Self,
        prices: []const f64,
        period: usize,
        num_std: f64,
        upper: []f64,
        middle: []f64,
        lower: []f64,
    ) !void {
        if (prices.len < period) return;

        // 计算 SMA 作为中轨
        self.computeSMA(prices, period, middle);

        // 计算标准差
        const std_dev = try self.allocator.alloc(f64, prices.len);
        defer self.allocator.free(std_dev);

        self.computeStdDev(prices, period, middle, std_dev);

        // 计算上下轨
        if (self.use_simd and prices.len >= SIMD_WIDTH) {
            const multiplier: Vec4 = @splat(num_std);
            var i: usize = period - 1;
            while (i + SIMD_WIDTH <= prices.len) : (i += SIMD_WIDTH) {
                const mid: Vec4 = middle[i..][0..SIMD_WIDTH].*;
                const sd: Vec4 = std_dev[i..][0..SIMD_WIDTH].*;
                const band = sd * multiplier;

                upper[i..][0..SIMD_WIDTH].* = mid + band;
                lower[i..][0..SIMD_WIDTH].* = mid - band;
            }
            // 处理剩余
            while (i < prices.len) : (i += 1) {
                const band = std_dev[i] * num_std;
                upper[i] = middle[i] + band;
                lower[i] = middle[i] - band;
            }
        } else {
            for (period - 1..prices.len) |i| {
                const band = std_dev[i] * num_std;
                upper[i] = middle[i] + band;
                lower[i] = middle[i] - band;
            }
        }

        // 前 period-1 个值设为 NaN
        for (0..period - 1) |i| {
            upper[i] = std.math.nan(f64);
            lower[i] = std.math.nan(f64);
        }
    }

    fn computeStdDev(self: *const Self, prices: []const f64, period: usize, mean: []const f64, result: []f64) void {
        const period_f: f64 = @floatFromInt(period);

        for (0..period - 1) |i| {
            result[i] = std.math.nan(f64);
        }

        if (self.use_simd and prices.len >= period + SIMD_WIDTH) {
            // SIMD 优化版本 (处理每个窗口)
            for (period - 1..prices.len) |i| {
                var sum_sq: f64 = 0;
                const m = mean[i];
                const start_idx = i + 1 - period;
                var j: usize = start_idx;

                // 使用 SIMD 计算平方和
                while (j + SIMD_WIDTH <= i + 1) : (j += SIMD_WIDTH) {
                    const vals: Vec4 = prices[j..][0..SIMD_WIDTH].*;
                    const m_vec: Vec4 = @splat(m);
                    const diff = vals - m_vec;
                    const sq = diff * diff;
                    sum_sq += @reduce(.Add, sq);
                }
                // 处理剩余
                while (j <= i) : (j += 1) {
                    const diff = prices[j] - m;
                    sum_sq += diff * diff;
                }

                result[i] = @sqrt(sum_sq / period_f);
            }
        } else {
            // 标量版本
            for (period - 1..prices.len) |i| {
                var sum_sq: f64 = 0;
                const m = mean[i];
                const start_idx = i + 1 - period;
                for (start_idx..i + 1) |j| {
                    const diff = prices[j] - m;
                    sum_sq += diff * diff;
                }
                result[i] = @sqrt(sum_sq / period_f);
            }
        }
    }

    /// 计算 MACD
    pub fn computeMACD(
        self: *Self,
        prices: []const f64,
        fast_period: usize,
        slow_period: usize,
        signal_period: usize,
        macd_line: []f64,
        signal_line: []f64,
        histogram: []f64,
    ) !void {
        if (prices.len < slow_period) return;

        // 计算快速和慢速 EMA
        const fast_ema = try self.allocator.alloc(f64, prices.len);
        defer self.allocator.free(fast_ema);

        const slow_ema = try self.allocator.alloc(f64, prices.len);
        defer self.allocator.free(slow_ema);

        self.computeEMA(prices, fast_period, fast_ema);
        self.computeEMA(prices, slow_period, slow_ema);

        // MACD Line = Fast EMA - Slow EMA
        if (self.use_simd and prices.len >= SIMD_WIDTH) {
            var i: usize = slow_period - 1;
            while (i + SIMD_WIDTH <= prices.len) : (i += SIMD_WIDTH) {
                const fast: Vec4 = fast_ema[i..][0..SIMD_WIDTH].*;
                const slow: Vec4 = slow_ema[i..][0..SIMD_WIDTH].*;
                macd_line[i..][0..SIMD_WIDTH].* = fast - slow;
            }
            while (i < prices.len) : (i += 1) {
                macd_line[i] = fast_ema[i] - slow_ema[i];
            }
        } else {
            for (slow_period - 1..prices.len) |i| {
                macd_line[i] = fast_ema[i] - slow_ema[i];
            }
        }

        // 前 slow_period-1 个值设为 NaN
        for (0..slow_period - 1) |i| {
            macd_line[i] = std.math.nan(f64);
        }

        // Signal Line = EMA of MACD Line
        self.computeEMA(macd_line[slow_period - 1 ..], signal_period, signal_line[slow_period - 1 ..]);
        for (0..slow_period - 1) |i| {
            signal_line[i] = std.math.nan(f64);
        }

        // Histogram = MACD Line - Signal Line
        const start = slow_period + signal_period - 2;
        if (self.use_simd and prices.len >= start + SIMD_WIDTH) {
            var i: usize = start;
            while (i + SIMD_WIDTH <= prices.len) : (i += SIMD_WIDTH) {
                const macd: Vec4 = macd_line[i..][0..SIMD_WIDTH].*;
                const signal: Vec4 = signal_line[i..][0..SIMD_WIDTH].*;
                histogram[i..][0..SIMD_WIDTH].* = macd - signal;
            }
            while (i < prices.len) : (i += 1) {
                histogram[i] = macd_line[i] - signal_line[i];
            }
        } else {
            for (start..prices.len) |i| {
                histogram[i] = macd_line[i] - signal_line[i];
            }
        }

        for (0..start) |i| {
            histogram[i] = std.math.nan(f64);
        }
    }
};

// ============================================================================
// 单元测试
// ============================================================================

test "SMA calculation" {
    const allocator = std.testing.allocator;
    const indicators = SimdIndicators.init(allocator, true);

    const prices = [_]f64{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 };
    var result: [10]f64 = undefined;

    indicators.computeSMA(&prices, 3, &result);

    // 检查 SMA 值
    try std.testing.expect(std.math.isNan(result[0]));
    try std.testing.expect(std.math.isNan(result[1]));
    try std.testing.expectApproxEqAbs(@as(f64, 2.0), result[2], 1e-10);
    try std.testing.expectApproxEqAbs(@as(f64, 3.0), result[3], 1e-10);
    try std.testing.expectApproxEqAbs(@as(f64, 4.0), result[4], 1e-10);
    try std.testing.expectApproxEqAbs(@as(f64, 9.0), result[9], 1e-10);
}

test "SMA SIMD matches scalar" {
    const allocator = std.testing.allocator;
    const simd_indicators = SimdIndicators.init(allocator, true);
    const scalar_indicators = SimdIndicators.init(allocator, false);

    // 生成测试数据
    var prices: [100]f64 = undefined;
    for (0..100) |i| {
        prices[i] = @as(f64, @floatFromInt(i)) + @sin(@as(f64, @floatFromInt(i)) * 0.1) * 10;
    }

    var simd_result: [100]f64 = undefined;
    var scalar_result: [100]f64 = undefined;

    simd_indicators.computeSMA(&prices, 10, &simd_result);
    scalar_indicators.computeSMA(&prices, 10, &scalar_result);

    for (0..100) |i| {
        if (std.math.isNan(simd_result[i])) {
            try std.testing.expect(std.math.isNan(scalar_result[i]));
        } else {
            try std.testing.expectApproxEqAbs(simd_result[i], scalar_result[i], 1e-10);
        }
    }
}

test "EMA calculation" {
    const allocator = std.testing.allocator;
    const indicators = SimdIndicators.init(allocator, true);

    const prices = [_]f64{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 };
    var result: [10]f64 = undefined;

    indicators.computeEMA(&prices, 3, &result);

    // 第一个有效值是 SMA
    try std.testing.expectApproxEqAbs(@as(f64, 2.0), result[2], 1e-10);

    // 后续值使用 EMA 公式
    // EMA = (Price - PrevEMA) * multiplier + PrevEMA
    // multiplier = 2 / (3 + 1) = 0.5
    try std.testing.expect(result[3] > result[2]);
    try std.testing.expect(result[9] > result[8]);
}

test "RSI calculation" {
    const allocator = std.testing.allocator;
    var indicators = SimdIndicators.init(allocator, true);

    // 上涨趋势 - RSI 应该 > 50
    const up_prices = [_]f64{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15 };
    var up_result: [15]f64 = undefined;

    try indicators.computeRSI(&up_prices, 5, &up_result);

    // RSI 在强上涨趋势中应接近 100
    try std.testing.expect(up_result[14] > 90);

    // 下跌趋势 - RSI 应该 < 50
    const down_prices = [_]f64{ 15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1 };
    var down_result: [15]f64 = undefined;

    try indicators.computeRSI(&down_prices, 5, &down_result);

    // RSI 在强下跌趋势中应接近 0
    try std.testing.expect(down_result[14] < 10);
}

test "Bollinger Bands calculation" {
    const allocator = std.testing.allocator;
    var indicators = SimdIndicators.init(allocator, true);

    const prices = [_]f64{ 10, 11, 12, 11, 10, 9, 10, 11, 12, 13 };
    var upper: [10]f64 = undefined;
    var middle: [10]f64 = undefined;
    var lower: [10]f64 = undefined;

    try indicators.computeBollingerBands(&prices, 5, 2.0, &upper, &middle, &lower);

    // 中轨是 SMA
    for (4..10) |i| {
        try std.testing.expect(!std.math.isNan(middle[i]));
        try std.testing.expect(upper[i] > middle[i]);
        try std.testing.expect(lower[i] < middle[i]);
    }
}
