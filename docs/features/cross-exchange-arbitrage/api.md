# Cross-Exchange Arbitrage API 参考

> 跨交易所套利模块的完整 API 文档

**版本**: v0.7.0
**状态**: 📋 待开发
**最后更新**: 2025-12-27

---

## 目录

1. [核心类型](#核心类型)
2. [CrossExchangeArbitrage](#crossexchangearbitrage)
3. [辅助结构](#辅助结构)
4. [使用示例](#使用示例)

---

## 核心类型

### ArbitrageConfig

套利策略配置。

```zig
pub const ArbitrageConfig = struct {
    /// 交易对符号
    symbol: []const u8,

    /// 最小净利润 (bps)
    min_profit_bps: u32 = 10,

    /// 每次交易数量
    trade_amount: Decimal,

    /// 最大滑点 (bps)
    max_slippage_bps: u32 = 5,

    /// 交易所 A 费率 (bps)
    fee_bps_a: u32 = 10,

    /// 交易所 B 费率 (bps)
    fee_bps_b: u32 = 10,

    /// 最大仓位
    max_position: Decimal,

    /// 订单超时 (ms)
    order_timeout_ms: u32 = 5000,

    /// 套利冷却时间 (ms)
    cooldown_ms: u32 = 1000,

    /// 是否启用同步执行
    sync_execution: bool = true,

    /// 验证配置
    pub fn validate(self: ArbitrageConfig) !void;
};
```

### ExchangeId

交易所标识。

```zig
pub const ExchangeId = enum {
    exchange_a,
    exchange_b,

    pub fn toString(self: ExchangeId) []const u8 {
        return switch (self) {
            .exchange_a => "Exchange A",
            .exchange_b => "Exchange B",
        };
    }
};
```

### ArbitrageOpportunity

套利机会结构。

```zig
pub const ArbitrageOpportunity = struct {
    /// 买入交易所
    buy_exchange: ExchangeId,

    /// 卖出交易所
    sell_exchange: ExchangeId,

    /// 买入价格
    buy_price: Decimal,

    /// 卖出价格
    sell_price: Decimal,

    /// 毛利润 (bps)
    gross_profit_bps: u32,

    /// 净利润 (bps，扣除费用)
    net_profit_bps: u32,

    /// 交易数量
    amount: Decimal,

    /// 预期利润金额
    expected_profit: Decimal,

    /// 发现时间
    detected_at: i64,

    /// 检查机会是否仍然有效
    pub fn isValid(self: ArbitrageOpportunity, max_age_ms: u32) bool;
};
```

### ArbitrageStats

套利统计结构。

```zig
pub const ArbitrageStats = struct {
    /// 检测到的机会数
    opportunities_detected: u64,

    /// 执行的套利次数
    executions: u64,

    /// 成功的套利次数
    successful: u64,

    /// 失败的套利次数
    failed: u64,

    /// 总利润
    total_profit: Decimal,

    /// 平均利润 (bps)
    avg_profit_bps: f64,

    /// 平均执行时间 (ms)
    avg_execution_time_ms: f64,

    /// 成功率
    pub fn successRate(self: ArbitrageStats) f64 {
        if (self.executions == 0) return 0;
        return @as(f64, @floatFromInt(self.successful)) /
               @as(f64, @floatFromInt(self.executions));
    }
};
```

---

## CrossExchangeArbitrage

跨交易所套利策略主结构。

### init

```zig
pub fn init(
    allocator: Allocator,
    config: ArbitrageConfig,
    provider_a: *MarketDataProvider,
    executor_a: *OrderExecutor,
    provider_b: *MarketDataProvider,
    executor_b: *OrderExecutor,
) CrossExchangeArbitrage
```

创建套利策略实例。

**参数**:
- `allocator`: 内存分配器
- `config`: 套利配置
- `provider_a/b`: 两个交易所的行情数据源
- `executor_a/b`: 两个交易所的订单执行器

**示例**:
```zig
var arb = CrossExchangeArbitrage.init(
    allocator,
    .{
        .symbol = "ETH-USD",
        .min_profit_bps = 10,
        .trade_amount = Decimal.fromFloat(0.1),
        .fee_bps_a = 10,
        .fee_bps_b = 10,
    },
    &binance_provider, &binance_executor,
    &okx_provider, &okx_executor,
);
defer arb.deinit();
```

### deinit

```zig
pub fn deinit(self: *CrossExchangeArbitrage) void
```

释放资源。

### detectOpportunity

```zig
pub fn detectOpportunity(self: *CrossExchangeArbitrage) ?ArbitrageOpportunity
```

检测当前是否存在套利机会。

**返回**: 套利机会，或 null 如果没有机会

**逻辑**:
1. 获取两个交易所的最优报价
2. 检查 A.ask < B.bid 或 B.ask < A.bid
3. 计算扣除费用后的净利润
4. 如果净利润 >= min_profit_bps，返回机会

**示例**:
```zig
if (arb.detectOpportunity()) |opportunity| {
    std.debug.print("发现套利机会! 净利润: {} bps\n", .{opportunity.net_profit_bps});
    try arb.executeArbitrage(opportunity);
}
```

### calculateNetProfit

```zig
pub fn calculateNetProfit(
    self: *CrossExchangeArbitrage,
    buy_price: Decimal,
    sell_price: Decimal,
) struct { gross_bps: u32, net_bps: u32, profit: Decimal }
```

计算套利利润（扣除费用）。

**参数**:
- `buy_price`: 买入价格
- `sell_price`: 卖出价格

**返回**: 包含毛利润、净利润和预期利润金额

**示例**:
```zig
const result = arb.calculateNetProfit(
    Decimal.fromFloat(2000.0),  // buy
    Decimal.fromFloat(2010.0),  // sell
);
std.debug.print("毛利润: {} bps, 净利润: {} bps\n", .{
    result.gross_bps,
    result.net_bps,
});
```

### executeArbitrage

```zig
pub fn executeArbitrage(
    self: *CrossExchangeArbitrage,
    opportunity: ArbitrageOpportunity,
) !ExecutionResult
```

执行套利交易。

**参数**:
- `opportunity`: 套利机会

**返回**: 执行结果

**错误**:
- `error.OpportunityExpired`: 机会已过期
- `error.ExecutionFailed`: 订单执行失败
- `error.PartialFill`: 部分成交
- `error.Cooldown`: 冷却时间未结束

**示例**:
```zig
const result = try arb.executeArbitrage(opportunity);
std.debug.print("套利执行完成: 实际利润 = {}\n", .{result.actual_profit});
```

### cancelPendingOrders

```zig
pub fn cancelPendingOrders(self: *CrossExchangeArbitrage) !void
```

取消所有待处理订单。

### getStats

```zig
pub fn getStats(self: *CrossExchangeArbitrage) ArbitrageStats
```

获取套利统计。

### asClockStrategy

```zig
pub fn asClockStrategy(self: *CrossExchangeArbitrage) IClockStrategy
```

转换为 Clock 策略接口。

---

## 辅助结构

### ExecutionResult

执行结果结构。

```zig
pub const ExecutionResult = struct {
    /// 是否成功
    success: bool,

    /// 买入成交信息
    buy_fill: ?OrderFill,

    /// 卖出成交信息
    sell_fill: ?OrderFill,

    /// 实际利润
    actual_profit: Decimal,

    /// 执行时间 (ms)
    execution_time_ms: u32,

    /// 错误信息 (如果失败)
    error_message: ?[]const u8,
};
```

### OrderFill

订单成交信息。

```zig
pub const OrderFill = struct {
    exchange: ExchangeId,
    order_id: []const u8,
    price: Decimal,
    quantity: Decimal,
    fee: Decimal,
    timestamp: i64,
};
```

### QuotePair

报价对结构。

```zig
pub const QuotePair = struct {
    /// 交易所 A 报价
    quote_a: Quote,

    /// 交易所 B 报价
    quote_b: Quote,

    /// 时间戳
    timestamp: i64,

    pub const Quote = struct {
        bid: Decimal,
        bid_size: Decimal,
        ask: Decimal,
        ask_size: Decimal,
    };
};
```

---

## 使用示例

### 基本使用

```zig
const std = @import("std");
const CrossExchangeArbitrage = @import("arbitrage/cross_exchange.zig").CrossExchangeArbitrage;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 初始化交易所连接
    var binance = try ExchangeClient.init(allocator, "binance", api_key_1);
    defer binance.deinit();

    var okx = try ExchangeClient.init(allocator, "okx", api_key_2);
    defer okx.deinit();

    // 创建套利策略
    var arb = CrossExchangeArbitrage.init(
        allocator,
        .{
            .symbol = "ETH-USDT",
            .min_profit_bps = 10,
            .trade_amount = Decimal.fromFloat(0.1),
            .fee_bps_a = 10,
            .fee_bps_b = 8,
            .max_position = Decimal.fromFloat(1.0),
        },
        &binance.provider, &binance.executor,
        &okx.provider, &okx.executor,
    );
    defer arb.deinit();

    // 主循环
    while (true) {
        if (arb.detectOpportunity()) |opp| {
            std.debug.print("套利机会: 买 {} @ {}, 卖 {} @ {}, 净利润: {} bps\n", .{
                opp.buy_exchange.toString(),
                opp.buy_price,
                opp.sell_exchange.toString(),
                opp.sell_price,
                opp.net_profit_bps,
            });

            const result = arb.executeArbitrage(opp) catch |err| {
                std.debug.print("执行失败: {}\n", .{err});
                continue;
            };

            if (result.success) {
                std.debug.print("套利成功! 利润: {}\n", .{result.actual_profit});
            }
        }

        std.time.sleep(100_000_000); // 100ms
    }
}
```

### 与 Clock 集成

```zig
pub fn setupArbitrageWithClock(clock: *Clock) !void {
    var arb = CrossExchangeArbitrage.init(...);

    // 注册到 Clock
    try clock.addStrategy(arb.asClockStrategy());

    // Clock 会定期调用 arb.onTick()
    try clock.start();
}
```

### 多交易对套利

```zig
pub fn multiPairArbitrage(allocator: Allocator) !void {
    const symbols = [_][]const u8{ "ETH-USDT", "BTC-USDT", "SOL-USDT" };

    var strategies = std.ArrayList(CrossExchangeArbitrage).init(allocator);
    defer strategies.deinit();

    for (symbols) |symbol| {
        const arb = CrossExchangeArbitrage.init(
            allocator,
            .{ .symbol = symbol, ... },
            ...
        );
        try strategies.append(arb);
    }

    // 并行检测所有交易对
    for (strategies.items) |*arb| {
        if (arb.detectOpportunity()) |opp| {
            try arb.executeArbitrage(opp);
        }
    }
}
```

---

## 错误处理

```zig
pub const ArbitrageError = error{
    /// 机会已过期
    OpportunityExpired,

    /// 订单执行失败
    ExecutionFailed,

    /// 部分成交
    PartialFill,

    /// 冷却时间未结束
    Cooldown,

    /// 仓位超限
    PositionExceeded,

    /// 连接失败
    ConnectionFailed,

    /// 超时
    Timeout,

    /// 配置无效
    InvalidConfig,
};
```

---

## 性能说明

| 操作 | 预期延迟 | 说明 |
|------|----------|------|
| detectOpportunity | < 1ms | 本地计算 |
| executeArbitrage | < 100ms | 取决于网络 |
| calculateNetProfit | < 100ns | 纯计算 |

---

*Last updated: 2025-12-27*
