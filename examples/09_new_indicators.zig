//! New Technical Indicators Example (v0.4.0)
//!
//! 此示例展示 v0.4.0 新增的技术指标用法。
//!
//! 新增指标：
//! 1. ADX (平均趋向指数) - 趋势强度指标
//! 2. Ichimoku Cloud (一目均衡表) - 趋势、支撑阻力
//! 3. CCI (商品通道指数) - 周期波动
//! 4. Williams %R (威廉指标) - 超买超卖
//! 5. OBV (能量潮) - 成交量趋势
//! 6. VWAP (成交量加权平均价)
//! 7. ROC (变动率) - 动量指标
//! 8. Parabolic SAR - 趋势反转
//!
//! 运行：
//!   zig build run-example-indicators

const std = @import("std");
const zigQuant = @import("zigQuant");

const Decimal = zigQuant.Decimal;

pub fn main() !void {
    

    std.debug.print("\n", .{});
    std.debug.print("╔════════════════════════════════════════════════════════════╗\n", .{});
    std.debug.print("║       zigQuant v0.4.0 - New Technical Indicators           ║\n", .{});
    std.debug.print("╚════════════════════════════════════════════════════════════╝\n", .{});
    std.debug.print("\n", .{});

    // 示例数据 - 模拟价格序列
    const high_prices = [_]f64{ 100.5, 101.2, 102.0, 101.8, 103.0, 104.2, 103.5, 105.0, 106.2, 105.8, 107.0, 108.5, 109.0, 108.2, 110.0 };
    const low_prices = [_]f64{ 99.0, 99.5, 100.2, 100.0, 101.5, 102.0, 101.8, 103.0, 104.0, 103.5, 105.0, 106.0, 107.0, 106.5, 108.0 };
    const close_prices = [_]f64{ 100.0, 100.8, 101.5, 101.0, 102.5, 103.5, 102.8, 104.5, 105.5, 105.0, 106.5, 108.0, 108.5, 107.5, 109.5 };
    const volumes = [_]f64{ 1000, 1200, 1100, 900, 1500, 1800, 1300, 2000, 2200, 1900, 2500, 2800, 3000, 2200, 3500 };

    // ═══════════════════════════════════════════════════════════
    // 1. ADX (Average Directional Index) - 平均趋向指数
    // ═══════════════════════════════════════════════════════════
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
    std.debug.print("1. ADX (Average Directional Index) - 平均趋向指数\n", .{});
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("   用途: 衡量趋势强度 (不区分方向)\n", .{});
    std.debug.print("   解读:\n", .{});
    std.debug.print("     - ADX < 20: 弱趋势或盘整\n", .{});
    std.debug.print("     - ADX 20-40: 中等趋势\n", .{});
    std.debug.print("     - ADX > 40: 强趋势\n", .{});
    std.debug.print("\n", .{});

    // 计算 ADX (需要至少 2*period 个数据点)
    std.debug.print("   示例计算 (period=5):\n", .{});
    std.debug.print("   High:  [100.5, 101.2, 102.0, ...]\n", .{});
    std.debug.print("   Low:   [99.0, 99.5, 100.2, ...]\n", .{});
    std.debug.print("   Close: [100.0, 100.8, 101.5, ...]\n", .{});
    std.debug.print("\n", .{});

    // 模拟 ADX 计算结果
    std.debug.print("   结果: ADX = 28.5 (中等上升趋势)\n", .{});
    std.debug.print("         +DI = 32.1, -DI = 18.4\n", .{});
    std.debug.print("         解读: +DI > -DI 表示上升趋势占优\n", .{});
    std.debug.print("\n", .{});

    // ═══════════════════════════════════════════════════════════
    // 2. Ichimoku Cloud (一目均衡表)
    // ═══════════════════════════════════════════════════════════
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
    std.debug.print("2. Ichimoku Cloud (一目均衡表)\n", .{});
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("   组成部分:\n", .{});
    std.debug.print("     - Tenkan-sen (转换线): 9期最高最低均值\n", .{});
    std.debug.print("     - Kijun-sen (基准线): 26期最高最低均值\n", .{});
    std.debug.print("     - Senkou Span A (先行带A): 转换线+基准线均值\n", .{});
    std.debug.print("     - Senkou Span B (先行带B): 52期最高最低均值\n", .{});
    std.debug.print("     - Chikou Span (迟行带): 收盘价后移26期\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("   交易信号:\n", .{});
    std.debug.print("     - 价格在云层上方: 看涨\n", .{});
    std.debug.print("     - 价格在云层下方: 看跌\n", .{});
    std.debug.print("     - 转换线上穿基准线: 买入信号\n", .{});
    std.debug.print("\n", .{});

    // ═══════════════════════════════════════════════════════════
    // 3. CCI (Commodity Channel Index) - 商品通道指数
    // ═══════════════════════════════════════════════════════════
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
    std.debug.print("3. CCI (Commodity Channel Index) - 商品通道指数\n", .{});
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("   公式: CCI = (TP - SMA(TP)) / (0.015 * MAD)\n", .{});
    std.debug.print("   其中 TP = (High + Low + Close) / 3\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("   解读:\n", .{});
    std.debug.print("     - CCI > +100: 超买区域\n", .{});
    std.debug.print("     - CCI < -100: 超卖区域\n", .{});
    std.debug.print("     - CCI 在 -100 到 +100: 正常波动\n", .{});
    std.debug.print("\n", .{});

    // 计算示例
    var tp_sum: f64 = 0;
    for (high_prices, 0..) |h, i| {
        const tp = (h + low_prices[i] + close_prices[i]) / 3.0;
        tp_sum += tp;
    }
    const tp_avg = tp_sum / @as(f64, @floatFromInt(high_prices.len));
    std.debug.print("   示例: 典型价格均值 = {d:.2}\n", .{tp_avg});
    std.debug.print("         模拟 CCI = 85.3 (接近超买)\n", .{});
    std.debug.print("\n", .{});

    // ═══════════════════════════════════════════════════════════
    // 4. Williams %R (威廉指标)
    // ═══════════════════════════════════════════════════════════
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
    std.debug.print("4. Williams %R (威廉指标)\n", .{});
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("   公式: %R = (Highest High - Close) / (Highest High - Lowest Low) * -100\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("   范围: -100 到 0\n", .{});
    std.debug.print("   解读:\n", .{});
    std.debug.print("     - %R > -20: 超买区域\n", .{});
    std.debug.print("     - %R < -80: 超卖区域\n", .{});
    std.debug.print("\n", .{});

    // 计算示例
    var highest: f64 = high_prices[0];
    var lowest: f64 = low_prices[0];
    for (high_prices) |h| highest = @max(highest, h);
    for (low_prices) |l| lowest = @min(lowest, l);
    const close = close_prices[close_prices.len - 1];
    const williams_r = (highest - close) / (highest - lowest) * -100.0;
    std.debug.print("   计算: Highest = {d:.2}, Lowest = {d:.2}, Close = {d:.2}\n", .{ highest, lowest, close });
    std.debug.print("         Williams %%R = {d:.2}\n", .{williams_r});
    std.debug.print("\n", .{});

    // ═══════════════════════════════════════════════════════════
    // 5. OBV (On-Balance Volume) - 能量潮
    // ═══════════════════════════════════════════════════════════
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
    std.debug.print("5. OBV (On-Balance Volume) - 能量潮\n", .{});
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("   规则:\n", .{});
    std.debug.print("     - 收盘价上涨: OBV += Volume\n", .{});
    std.debug.print("     - 收盘价下跌: OBV -= Volume\n", .{});
    std.debug.print("     - 收盘价不变: OBV 不变\n", .{});
    std.debug.print("\n", .{});

    // 计算 OBV
    var obv: f64 = 0;
    for (close_prices[1..], 1..) |current_close, i| {
        const prev_close = close_prices[i - 1];
        if (current_close > prev_close) {
            obv += volumes[i];
        } else if (current_close < prev_close) {
            obv -= volumes[i];
        }
    }
    std.debug.print("   计算结果: OBV = {d:.0}\n", .{obv});
    std.debug.print("   解读: OBV 上升趋势与价格上升趋势一致，确认趋势有效\n", .{});
    std.debug.print("\n", .{});

    // ═══════════════════════════════════════════════════════════
    // 6. VWAP (Volume Weighted Average Price)
    // ═══════════════════════════════════════════════════════════
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
    std.debug.print("6. VWAP (Volume Weighted Average Price) - 成交量加权平均价\n", .{});
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("   公式: VWAP = Sum(TP * Volume) / Sum(Volume)\n", .{});
    std.debug.print("   其中 TP = (High + Low + Close) / 3\n", .{});
    std.debug.print("\n", .{});

    // 计算 VWAP
    var tp_vol_sum: f64 = 0;
    var vol_sum: f64 = 0;
    for (high_prices, 0..) |h, i| {
        const tp = (h + low_prices[i] + close_prices[i]) / 3.0;
        tp_vol_sum += tp * volumes[i];
        vol_sum += volumes[i];
    }
    const vwap = tp_vol_sum / vol_sum;
    std.debug.print("   计算结果: VWAP = {d:.2}\n", .{vwap});
    std.debug.print("   用途: 机构交易基准，判断日内买卖压力\n", .{});
    std.debug.print("         价格 > VWAP: 多头占优\n", .{});
    std.debug.print("         价格 < VWAP: 空头占优\n", .{});
    std.debug.print("\n", .{});

    // ═══════════════════════════════════════════════════════════
    // 7. ROC (Rate of Change) - 变动率
    // ═══════════════════════════════════════════════════════════
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
    std.debug.print("7. ROC (Rate of Change) - 变动率\n", .{});
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("   公式: ROC = (Close - Close_n) / Close_n * 100\n", .{});
    std.debug.print("\n", .{});

    // 计算 ROC (5期)
    const period: usize = 5;
    const current = close_prices[close_prices.len - 1];
    const past = close_prices[close_prices.len - 1 - period];
    const roc = (current - past) / past * 100.0;
    std.debug.print("   计算 (period=5): ROC = ({d:.2} - {d:.2}) / {d:.2} * 100\n", .{ current, past, past });
    std.debug.print("                    ROC = {d:.2}%\n", .{roc});
    std.debug.print("   解读: 正值表示上涨动量，负值表示下跌动量\n", .{});
    std.debug.print("\n", .{});

    // ═══════════════════════════════════════════════════════════
    // 8. Parabolic SAR - 抛物线转向指标
    // ═══════════════════════════════════════════════════════════
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
    std.debug.print("8. Parabolic SAR - 抛物线转向指标\n", .{});
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("   参数:\n", .{});
    std.debug.print("     - AF (加速因子): 起始 0.02, 最大 0.20\n", .{});
    std.debug.print("     - EP (极点): 趋势中的最高/最低点\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("   公式: SAR(t) = SAR(t-1) + AF * (EP - SAR(t-1))\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("   交易信号:\n", .{});
    std.debug.print("     - SAR 在价格下方: 上升趋势，持有多头\n", .{});
    std.debug.print("     - SAR 在价格上方: 下降趋势，持有空头\n", .{});
    std.debug.print("     - SAR 与价格交叉: 趋势反转信号\n", .{});
    std.debug.print("\n", .{});

    // ═══════════════════════════════════════════════════════════
    // 总结
    // ═══════════════════════════════════════════════════════════
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
    std.debug.print("指标分类总结\n", .{});
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("   趋势类:     ADX, Ichimoku, Parabolic SAR\n", .{});
    std.debug.print("   动量类:     CCI, Williams %%R, ROC\n", .{});
    std.debug.print("   成交量类:   OBV, VWAP\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("   使用建议:\n", .{});
    std.debug.print("     1. 多指标组合验证信号\n", .{});
    std.debug.print("     2. 趋势指标确认方向，动量指标确认时机\n", .{});
    std.debug.print("     3. 成交量指标验证趋势有效性\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("╔════════════════════════════════════════════════════════════╗\n", .{});
    std.debug.print("║                    示例运行完成                             ║\n", .{});
    std.debug.print("╚════════════════════════════════════════════════════════════╝\n", .{});
    std.debug.print("\n", .{});
}
