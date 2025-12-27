//! Market Making 共享类型
//!
//! 定义做市策略模块使用的共享类型。

const std = @import("std");
const Decimal = @import("../core/decimal.zig").Decimal;
const Side = @import("../exchange/types.zig").Side;

// ============================================================================
// 订单信息
// ============================================================================

/// 活跃订单信息
pub const OrderInfo = struct {
    /// 订单 ID
    order_id: []const u8,
    /// 订单价格
    price: Decimal,
    /// 订单数量
    amount: Decimal,
    /// 买卖方向
    side: Side,
    /// 创建时的 tick
    created_tick: u64,
};

// ============================================================================
// 成交信息
// ============================================================================

/// 订单成交信息
pub const OrderFill = struct {
    /// 订单 ID
    order_id: []const u8,
    /// 交易对
    symbol: []const u8,
    /// 买卖方向
    side: Side,
    /// 成交数量
    quantity: Decimal,
    /// 成交价格
    price: Decimal,
    /// 手续费
    fee: Decimal,
    /// 成交时间
    timestamp: i128,
};

// ============================================================================
// 做市统计
// ============================================================================

/// 做市策略统计信息
pub const MMStats = struct {
    /// 总成交笔数
    total_trades: u64,
    /// 总成交量 (base currency)
    total_volume: Decimal,
    /// 总成交额 (quote currency)
    total_notional: Decimal,
    /// 当前持仓
    current_position: Decimal,
    /// 已实现盈亏
    realized_pnl: Decimal,
    /// 活跃买单数
    active_bids: usize,
    /// 活跃卖单数
    active_asks: usize,
    /// 总手续费
    total_fees: Decimal,

    /// 创建默认统计
    pub fn init() MMStats {
        return .{
            .total_trades = 0,
            .total_volume = Decimal.ZERO,
            .total_notional = Decimal.ZERO,
            .current_position = Decimal.ZERO,
            .realized_pnl = Decimal.ZERO,
            .active_bids = 0,
            .active_asks = 0,
            .total_fees = Decimal.ZERO,
        };
    }
};

// ============================================================================
// 报价信息
// ============================================================================

/// 报价更新
pub const QuoteUpdate = struct {
    /// 买价
    bid_price: Decimal,
    /// 卖价
    ask_price: Decimal,
    /// 买量
    bid_amount: Decimal,
    /// 卖量
    ask_amount: Decimal,
    /// 层级 (0 = 最优)
    level: u32,
};

// ============================================================================
// Tests
// ============================================================================

test "OrderInfo: basic" {
    const info = OrderInfo{
        .order_id = "order123",
        .price = Decimal.fromInt(2000),
        .amount = Decimal.fromFloat(0.1),
        .side = .buy,
        .created_tick = 100,
    };

    try std.testing.expectEqualStrings("order123", info.order_id);
    try std.testing.expect(info.side == .buy);
}

test "MMStats: init" {
    const stats = MMStats.init();

    try std.testing.expectEqual(@as(u64, 0), stats.total_trades);
    try std.testing.expectEqual(@as(usize, 0), stats.active_bids);
}
