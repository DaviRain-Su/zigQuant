//! Position - 仓位数据结构
//!
//! 提供完整的仓位追踪功能，基于 Hyperliquid API 规范：
//! - szi: 有符号仓位大小（正数=多头，负数=空头）
//! - 杠杆和保证金管理
//! - 盈亏计算（已实现/未实现）
//! - 资金费率追踪
//!
//! 参考: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/info-endpoint

const std = @import("std");
const Decimal = @import("../core/decimal.zig").Decimal;
const Timestamp = @import("../core/time.zig").Timestamp;
const Side = @import("../exchange/types.zig").Side;

// ============================================================================
// Position
// ============================================================================

pub const Position = struct {
    allocator: std.mem.Allocator,
    
    // 基础信息
    coin: []const u8,                    // 币种名称 (e.g. "ETH")
    
    // 仓位大小 (基于真实 API: szi 字段)
    szi: Decimal,                        // 有符号仓位大小（正=多头，负=空头）
    side: Side,                          // 方向（从 szi 推断）
    
    // 价格信息
    entry_px: Decimal,                   // 开仓均价 (entryPx)
    mark_price: ?Decimal,                // 标记价格（用于计算未实现盈亏）
    liquidation_px: ?Decimal,            // 清算价格 (liquidationPx)
    
    // 杠杆 (基于真实 API: leverage {type, value, rawUsd})
    leverage: Leverage,
    max_leverage: u32,                   // 最大杠杆 (maxLeverage)
    
    // 盈亏
    unrealized_pnl: Decimal,             // 未实现盈亏 (unrealizedPnl)
    realized_pnl: Decimal,               // 已实现盈亏（累计）
    
    // 保证金
    margin_used: Decimal,                // 已用保证金 (marginUsed)
    position_value: Decimal,             // 仓位价值 (positionValue)
    
    // ROE (基于真实 API: returnOnEquity)
    return_on_equity: Decimal,           // 权益回报率
    
    // 资金费率 (基于真实 API: cumFunding)
    cum_funding: CumFunding,
    
    // 时间戳
    opened_at: Timestamp,
    updated_at: Timestamp,

    /// 杠杆结构 (基于真实 API)
    pub const Leverage = struct {
        type_: []const u8,               // "cross" 或 "isolated"
        value: u32,                      // 杠杆倍数
        raw_usd: Decimal,                // 原始 USD 价值
    };

    /// 累计资金费率 (基于真实 API)
    pub const CumFunding = struct {
        all_time: Decimal,               // 累计总额
        since_change: Decimal,           // 自上次变动
        since_open: Decimal,             // 自开仓
    };

    /// 初始化仓位
    pub fn init(
        allocator: std.mem.Allocator,
        coin: []const u8,
        szi: Decimal,
    ) !Position {
        return .{
            .allocator = allocator,
            .coin = try allocator.dupe(u8, coin),
            .szi = szi,
            .side = if (szi.cmp(Decimal.ZERO) == .gt) .buy else .sell,
            .entry_px = Decimal.ZERO,
            .mark_price = null,
            .liquidation_px = null,
            .leverage = .{
                .type_ = "cross",
                .value = 1,
                .raw_usd = Decimal.ZERO,
            },
            .max_leverage = 50,
            .unrealized_pnl = Decimal.ZERO,
            .realized_pnl = Decimal.ZERO,
            .margin_used = Decimal.ZERO,
            .position_value = Decimal.ZERO,
            .return_on_equity = Decimal.ZERO,
            .cum_funding = .{
                .all_time = Decimal.ZERO,
                .since_change = Decimal.ZERO,
                .since_open = Decimal.ZERO,
            },
            .opened_at = Timestamp.now(),
            .updated_at = Timestamp.now(),
        };
    }

    /// 清理资源
    pub fn deinit(self: *Position) void {
        self.allocator.free(self.coin);
    }

    /// 更新标记价格和未实现盈亏 (基于真实 API)
    pub fn updateMarkPrice(self: *Position, mark_price: Decimal) !void {
        self.mark_price = mark_price;
        self.unrealized_pnl = self.calculateUnrealizedPnl(mark_price);
        self.position_value = self.szi.abs().mul(mark_price); // positionValue

        // 更新 ROE (基于真实 API: returnOnEquity)
        if (self.margin_used.cmp(Decimal.ZERO) != .eq) {
            self.return_on_equity = try self.unrealized_pnl.div(self.margin_used);
        }

        self.updated_at = Timestamp.now();
    }

    /// 计算未实现盈亏 (基于真实 API: 使用 szi)
    fn calculateUnrealizedPnl(self: *const Position, current_price: Decimal) Decimal {
        if (self.szi.isZero()) return Decimal.ZERO;

        // 基于真实 API: szi 为正表示多头，为负表示空头
        // PnL = szi * (current_price - entry_px)
        const price_diff = current_price.sub(self.entry_px);
        return price_diff.mul(self.szi);
    }

    /// 增加仓位（开仓或加仓）
    pub fn increase(
        self: *Position,
        quantity: Decimal,
        price: Decimal,
    ) !void {
        const abs_szi = self.szi.abs();
        
        if (abs_szi.isZero()) {
            // 首次开仓
            self.entry_px = price;
            self.opened_at = Timestamp.now();
        } else {
            // 加仓：计算新的平均价格
            const current_value = abs_szi.mul(self.entry_px);
            const new_value = quantity.mul(price);
            const total_size = abs_szi.add(quantity);

            self.entry_px = try current_value.add(new_value).div(total_size);
        }

        // 更新 szi（保持方向）
        if (self.side == .buy) {
            self.szi = abs_szi.add(quantity);
        } else {
            self.szi = abs_szi.add(quantity).negate();
        }

        self.updated_at = Timestamp.now();
    }

    /// 减少仓位（减仓或平仓）
    pub fn decrease(
        self: *Position,
        quantity: Decimal,
        price: Decimal,
    ) !Decimal {
        const abs_szi = self.szi.abs();
        
        if (quantity.cmp(abs_szi) == .gt) {
            return error.InvalidQuantity;
        }

        // 计算此次平仓的已实现盈亏
        const close_pnl = self.calculateClosePnl(quantity, price);
        self.realized_pnl = self.realized_pnl.add(close_pnl);

        // 减少仓位大小
        const new_abs_szi = abs_szi.sub(quantity);
        if (self.side == .buy) {
            self.szi = new_abs_szi;
        } else {
            self.szi = new_abs_szi.negate();
        }

        // 如果完全平仓，重置数据
        if (self.szi.isZero()) {
            self.entry_px = Decimal.ZERO;
            self.unrealized_pnl = Decimal.ZERO;
            self.position_value = Decimal.ZERO;
        }

        self.updated_at = Timestamp.now();

        return close_pnl;
    }

    /// 计算平仓盈亏
    fn calculateClosePnl(self: *const Position, quantity: Decimal, close_price: Decimal) Decimal {
        const price_diff = close_price.sub(self.entry_px);
        const pnl = price_diff.mul(quantity);

        return switch (self.side) {
            .buy => pnl,
            .sell => pnl.negate(),
        };
    }

    /// 是否为空仓
    pub fn isEmpty(self: *const Position) bool {
        return self.szi.isZero();
    }

    /// 获取总盈亏
    pub fn getTotalPnl(self: *const Position) Decimal {
        return self.realized_pnl.add(self.unrealized_pnl);
    }

    /// 获取绝对仓位大小
    pub fn getAbsSize(self: *const Position) Decimal {
        return self.szi.abs();
    }
};

// ============================================================================
// Tests
// ============================================================================

test "Position: init and deinit" {
    const allocator = std.testing.allocator;

    var pos = try Position.init(allocator, "ETH", Decimal.fromInt(1));
    defer pos.deinit();

    try std.testing.expect(std.mem.eql(u8, pos.coin, "ETH"));
    try std.testing.expect(pos.side == .buy); // szi > 0 means long
}

test "Position: increase (open and add)" {
    const allocator = std.testing.allocator;

    var pos = try Position.init(allocator, "ETH", Decimal.ZERO);
    defer pos.deinit();
    pos.side = .buy;

    // 开仓
    try pos.increase(try Decimal.fromString("1.0"), try Decimal.fromString("2000.0"));
    try std.testing.expect(pos.getAbsSize().eql(Decimal.fromInt(1)));
    try std.testing.expect(pos.entry_px.eql(Decimal.fromInt(2000)));

    // 加仓
    try pos.increase(try Decimal.fromString("1.0"), try Decimal.fromString("2100.0"));
    try std.testing.expect(pos.getAbsSize().eql(Decimal.fromInt(2)));
    // 平均价格应该是 (2000 + 2100) / 2 = 2050
    try std.testing.expect(pos.entry_px.eql(Decimal.fromInt(2050)));
}

test "Position: decrease (close)" {
    const allocator = std.testing.allocator;

    var pos = try Position.init(allocator, "ETH", Decimal.fromInt(2));
    defer pos.deinit();
    pos.side = .buy;
    pos.entry_px = Decimal.fromInt(2000);

    // 部分平仓
    const pnl = try pos.decrease(try Decimal.fromString("1.0"), try Decimal.fromString("2100.0"));
    try std.testing.expect(pnl.eql(Decimal.fromInt(100))); // (2100 - 2000) * 1.0
    try std.testing.expect(pos.getAbsSize().eql(Decimal.fromInt(1)));

    // 完全平仓
    _ = try pos.decrease(try Decimal.fromString("1.0"), try Decimal.fromString("2100.0"));
    try std.testing.expect(pos.isEmpty());
}

test "Position: unrealized PnL" {
    const allocator = std.testing.allocator;

    var pos = try Position.init(allocator, "ETH", Decimal.fromInt(1));
    defer pos.deinit();
    pos.side = .buy;
    pos.entry_px = Decimal.fromInt(2000);

    try pos.updateMarkPrice(Decimal.fromInt(2100));

    try std.testing.expect(pos.unrealized_pnl.eql(Decimal.fromInt(100)));
}
