# Story 037: Cross-Exchange Arbitrage 跨交易所套利

**版本**: v0.7.0
**状态**: 待开发
**优先级**: P2
**预计时间**: 3-4 天
**依赖**: Story 033 (Clock-Driven), Story 036 (SQLite)

---

## 概述

实现跨交易所套利策略，监测不同交易所之间的价格差异，在有利可图时执行同时买卖操作获取无风险利润。

---

## 背景

### 套利原理

```
┌─────────────────────────────────────────────────────────────────┐
│                     跨交易所套利原理                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│    Exchange A                    Exchange B                     │
│  ┌─────────────┐              ┌─────────────┐                  │
│  │ ETH/USDT    │              │ ETH/USDT    │                  │
│  │             │              │             │                  │
│  │ Bid: 1995   │              │ Bid: 2005   │ ← 更高           │
│  │ Ask: 2000   │ ← 更低       │ Ask: 2010   │                  │
│  └─────────────┘              └─────────────┘                  │
│                                                                  │
│  套利机会:                                                      │
│  ────────────────────────────────────────────                  │
│  在 A 买入 @ 2000                                               │
│  在 B 卖出 @ 2005                                               │
│  利润 = 2005 - 2000 = 5 USDT (0.25%)                           │
│                                                                  │
│  扣除费用后:                                                    │
│  - A 买入费用: 2000 * 0.1% = 2 USDT                            │
│  - B 卖出费用: 2005 * 0.1% = 2 USDT                            │
│  - 净利润: 5 - 4 = 1 USDT (0.05%)                              │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 套利类型

```
┌─────────────────────────────────────────────────────────────────┐
│                       套利策略类型                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  1. 空间套利 (Spatial Arbitrage)                               │
│     不同交易所之间的价差                                        │
│     A: Buy ETH @ 2000 → B: Sell ETH @ 2010                     │
│                                                                  │
│  2. 三角套利 (Triangular Arbitrage)                            │
│     同一交易所的三个交易对                                      │
│     ETH/USDT → ETH/BTC → BTC/USDT                              │
│                                                                  │
│  3. 统计套利 (Statistical Arbitrage)                           │
│     基于价格回归的配对交易                                      │
│     Long ETH + Short BTC (历史相关性)                          │
│                                                                  │
│  本 Story 实现: 空间套利 (最基础)                              │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 技术设计

### 核心组件

```
┌─────────────────────────────────────────────────────────────────┐
│                   Cross-Exchange Arbitrage 架构                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │               CrossExchangeArbitrage                      │  │
│  │                                                            │  │
│  │  ┌────────────────┐     ┌────────────────┐               │  │
│  │  │   Exchange A   │     │   Exchange B   │               │  │
│  │  │  DataProvider  │     │  DataProvider  │               │  │
│  │  │  ExecutionCli  │     │  ExecutionCli  │               │  │
│  │  └────────────────┘     └────────────────┘               │  │
│  │           ↓                      ↓                        │  │
│  │  ┌────────────────────────────────────────────────────┐  │  │
│  │  │            Opportunity Detector                     │  │  │
│  │  │  • 监测双边报价                                     │  │  │
│  │  │  • 计算价差                                         │  │  │
│  │  │  • 评估利润 (扣除费用)                              │  │  │
│  │  └────────────────────────────────────────────────────┘  │  │
│  │           ↓                                               │  │
│  │  ┌────────────────────────────────────────────────────┐  │  │
│  │  │            Execution Engine                         │  │  │
│  │  │  • 同步下单                                         │  │  │
│  │  │  • 订单追踪                                         │  │  │
│  │  │  • 风险控制                                         │  │  │
│  │  └────────────────────────────────────────────────────┘  │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 配置结构

```zig
/// 套利配置
pub const ArbitrageConfig = struct {
    /// 交易对
    symbol: []const u8,

    /// 最小利润阈值 (basis points)
    /// 扣除费用后的净利润
    min_profit_bps: u32 = 10,  // 0.1%

    /// 交易数量
    trade_amount: Decimal,

    /// 最大滑点容忍度 (bps)
    max_slippage_bps: u32 = 5,

    /// 双边费率 (bps)
    fee_bps_a: u32 = 10,  // 0.1%
    fee_bps_b: u32 = 10,  // 0.1%

    /// 最大单边仓位
    max_position: Decimal,

    /// 订单超时 (ms)
    order_timeout_ms: u32 = 5000,

    /// 冷却时间 (ms) - 执行套利后等待
    cooldown_ms: u32 = 1000,
};
```

### 核心实现

```zig
const std = @import("std");
const Allocator = std.mem.Allocator;
const Decimal = @import("../core/decimal.zig").Decimal;

/// 跨交易所套利策略
pub const CrossExchangeArbitrage = struct {
    allocator: Allocator,
    config: ArbitrageConfig,

    // 交易所连接
    exchange_a: ExchangeConnection,
    exchange_b: ExchangeConnection,

    // 状态
    position_a: Decimal,
    position_b: Decimal,
    total_profit: Decimal,
    trade_count: u32,
    last_trade_time: i64,

    // 统计
    opportunities_detected: u32,
    opportunities_executed: u32,
    opportunities_missed: u32,

    const Self = @This();

    pub fn init(
        allocator: Allocator,
        config: ArbitrageConfig,
        exchange_a: ExchangeConnection,
        exchange_b: ExchangeConnection,
    ) Self {
        return .{
            .allocator = allocator,
            .config = config,
            .exchange_a = exchange_a,
            .exchange_b = exchange_b,
            .position_a = Decimal.zero,
            .position_b = Decimal.zero,
            .total_profit = Decimal.zero,
            .trade_count = 0,
            .last_trade_time = 0,
            .opportunities_detected = 0,
            .opportunities_executed = 0,
            .opportunities_missed = 0,
        };
    }

    /// IClockStrategy 实现
    const vtable = IClockStrategy.VTable{
        .onTick = onTickImpl,
        .onStart = onStartImpl,
        .onStop = onStopImpl,
    };

    pub fn asClockStrategy(self: *Self) IClockStrategy {
        return .{
            .ptr = self,
            .vtable = &vtable,
        };
    }

    fn onTickImpl(ptr: *anyopaque, tick: u64, timestamp: i128) anyerror!void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        _ = tick;

        // 检查冷却时间
        const now: i64 = @intCast(@divFloor(timestamp, 1_000_000));
        if (now - self.last_trade_time < self.config.cooldown_ms) {
            return;
        }

        // 检测套利机会
        const opportunity = self.detectOpportunity() orelse return;
        self.opportunities_detected += 1;

        // 验证利润
        if (opportunity.net_profit_bps < self.config.min_profit_bps) {
            return;
        }

        // 检查仓位限制
        if (!self.canExecute(opportunity)) {
            self.opportunities_missed += 1;
            return;
        }

        // 执行套利
        self.executeArbitrage(opportunity) catch |err| {
            std.log.err("[Arb] Execution failed: {}", .{err});
            return;
        };

        self.opportunities_executed += 1;
        self.last_trade_time = now;
    }

    fn onStartImpl(ptr: *anyopaque) anyerror!void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        std.log.info("[Arb] Starting arbitrage for {s}", .{self.config.symbol});
    }

    fn onStopImpl(ptr: *anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        std.log.info("[Arb] Stopping. Stats: detected={}, executed={}, profit={}",
            .{ self.opportunities_detected, self.opportunities_executed, self.total_profit });
    }

    /// 检测套利机会
    pub fn detectOpportunity(self: *Self) ?ArbitrageOpportunity {
        // 获取双边报价
        const quote_a = self.exchange_a.data_provider.getQuote(self.config.symbol) orelse return null;
        const quote_b = self.exchange_b.data_provider.getQuote(self.config.symbol) orelse return null;

        // 机会 1: 在 A 买入, 在 B 卖出
        const profit_a_to_b = self.calculateProfit(
            quote_a.ask,  // A 的卖价 (我的买入价)
            quote_b.bid,  // B 的买价 (我的卖出价)
            .a_to_b,
        );

        // 机会 2: 在 B 买入, 在 A 卖出
        const profit_b_to_a = self.calculateProfit(
            quote_b.ask,  // B 的卖价
            quote_a.bid,  // A 的买价
            .b_to_a,
        );

        // 选择更优的机会
        if (profit_a_to_b.net_profit_bps > profit_b_to_a.net_profit_bps and
            profit_a_to_b.net_profit_bps >= self.config.min_profit_bps)
        {
            return .{
                .direction = .a_to_b,
                .buy_price = quote_a.ask,
                .sell_price = quote_b.bid,
                .gross_profit_bps = profit_a_to_b.gross_profit_bps,
                .fee_bps = profit_a_to_b.fee_bps,
                .net_profit_bps = profit_a_to_b.net_profit_bps,
                .amount = self.config.trade_amount,
                .timestamp = std.time.milliTimestamp(),
            };
        }

        if (profit_b_to_a.net_profit_bps >= self.config.min_profit_bps) {
            return .{
                .direction = .b_to_a,
                .buy_price = quote_b.ask,
                .sell_price = quote_a.bid,
                .gross_profit_bps = profit_b_to_a.gross_profit_bps,
                .fee_bps = profit_b_to_a.fee_bps,
                .net_profit_bps = profit_b_to_a.net_profit_bps,
                .amount = self.config.trade_amount,
                .timestamp = std.time.milliTimestamp(),
            };
        }

        return null;
    }

    /// 计算利润
    fn calculateProfit(
        self: *Self,
        buy_price: Decimal,
        sell_price: Decimal,
        direction: Direction,
    ) ProfitCalc {
        // 毛利润 (bps)
        const spread = sell_price.sub(buy_price);
        const gross_bps = spread.div(buy_price).mul(Decimal.fromInt(10000)).toFloat();

        // 费用
        const fee_bps: f64 = switch (direction) {
            .a_to_b => @as(f64, @floatFromInt(self.config.fee_bps_a + self.config.fee_bps_b)),
            .b_to_a => @as(f64, @floatFromInt(self.config.fee_bps_a + self.config.fee_bps_b)),
        };

        return .{
            .gross_profit_bps = @intFromFloat(@max(0, gross_bps)),
            .fee_bps = @intFromFloat(fee_bps),
            .net_profit_bps = @intFromFloat(@max(0, gross_bps - fee_bps)),
        };
    }

    /// 检查是否可以执行
    fn canExecute(self: *Self, opp: ArbitrageOpportunity) bool {
        const new_position = switch (opp.direction) {
            .a_to_b => self.position_a.add(opp.amount),
            .b_to_a => self.position_b.add(opp.amount),
        };

        return new_position.abs().compare(self.config.max_position) != .gt;
    }

    /// 执行套利
    fn executeArbitrage(self: *Self, opp: ArbitrageOpportunity) !void {
        std.log.info("[Arb] Executing: {} @ {} → {}, profit={}bps", .{
            opp.direction,
            opp.buy_price,
            opp.sell_price,
            opp.net_profit_bps,
        });

        const buy_exchange = switch (opp.direction) {
            .a_to_b => &self.exchange_a,
            .b_to_a => &self.exchange_b,
        };

        const sell_exchange = switch (opp.direction) {
            .a_to_b => &self.exchange_b,
            .b_to_a => &self.exchange_a,
        };

        // 同时下单 (尽量原子)
        const buy_order = try buy_exchange.executor.submitOrder(.{
            .symbol = self.config.symbol,
            .side = .buy,
            .order_type = .limit,
            .quantity = opp.amount,
            .price = opp.buy_price,
        });

        const sell_order = try sell_exchange.executor.submitOrder(.{
            .symbol = self.config.symbol,
            .side = .sell,
            .order_type = .limit,
            .quantity = opp.amount,
            .price = opp.sell_price,
        });

        // 等待成交或超时
        const buy_result = try self.waitForFill(buy_exchange, buy_order.id);
        const sell_result = try self.waitForFill(sell_exchange, sell_order.id);

        // 更新状态
        if (buy_result.filled and sell_result.filled) {
            const profit = sell_result.fill_price.sub(buy_result.fill_price)
                .mul(opp.amount);
            self.total_profit = self.total_profit.add(profit);
            self.trade_count += 1;

            std.log.info("[Arb] Success! Profit: {}", .{profit});
        } else {
            // 处理部分成交
            std.log.warn("[Arb] Partial fill: buy={}, sell={}", .{
                buy_result.filled,
                sell_result.filled,
            });
        }

        // 更新仓位
        switch (opp.direction) {
            .a_to_b => {
                self.position_a = self.position_a.add(opp.amount);
                self.position_b = self.position_b.sub(opp.amount);
            },
            .b_to_a => {
                self.position_b = self.position_b.add(opp.amount);
                self.position_a = self.position_a.sub(opp.amount);
            },
        }
    }

    fn waitForFill(
        self: *Self,
        exchange: *ExchangeConnection,
        order_id: u64,
    ) !FillResult {
        _ = self;
        const start = std.time.milliTimestamp();
        const timeout = self.config.order_timeout_ms;

        while (std.time.milliTimestamp() - start < timeout) {
            const status = try exchange.executor.getOrderStatus(order_id);
            if (status.status == .filled) {
                return .{
                    .filled = true,
                    .fill_price = status.avg_fill_price,
                    .fill_amount = status.filled_amount,
                };
            }
            if (status.status == .canceled or status.status == .rejected) {
                return .{ .filled = false, .fill_price = Decimal.zero, .fill_amount = Decimal.zero };
            }
            std.time.sleep(10_000_000);  // 10ms
        }

        // 超时，尝试取消
        exchange.executor.cancelOrder(order_id) catch {};
        return .{ .filled = false, .fill_price = Decimal.zero, .fill_amount = Decimal.zero };
    }

    /// 获取统计
    pub fn getStats(self: *Self) ArbStats {
        return .{
            .opportunities_detected = self.opportunities_detected,
            .opportunities_executed = self.opportunities_executed,
            .opportunities_missed = self.opportunities_missed,
            .trade_count = self.trade_count,
            .total_profit = self.total_profit,
            .position_a = self.position_a,
            .position_b = self.position_b,
            .success_rate = if (self.opportunities_detected > 0)
                @as(f64, @floatFromInt(self.opportunities_executed)) /
                    @as(f64, @floatFromInt(self.opportunities_detected))
            else 0,
        };
    }
};

pub const Direction = enum { a_to_b, b_to_a };

pub const ArbitrageOpportunity = struct {
    direction: Direction,
    buy_price: Decimal,
    sell_price: Decimal,
    gross_profit_bps: u32,
    fee_bps: u32,
    net_profit_bps: u32,
    amount: Decimal,
    timestamp: i64,
};

pub const ProfitCalc = struct {
    gross_profit_bps: u32,
    fee_bps: u32,
    net_profit_bps: u32,
};

pub const FillResult = struct {
    filled: bool,
    fill_price: Decimal,
    fill_amount: Decimal,
};

pub const ExchangeConnection = struct {
    name: []const u8,
    data_provider: *IDataProvider,
    executor: *IExecutionClient,
};

pub const ArbStats = struct {
    opportunities_detected: u32,
    opportunities_executed: u32,
    opportunities_missed: u32,
    trade_count: u32,
    total_profit: Decimal,
    position_a: Decimal,
    position_b: Decimal,
    success_rate: f64,
};
```

---

## 实现任务

### Task 1: 机会检测 (Day 1)

- [ ] 创建 `src/market_making/arbitrage.zig`
- [ ] 实现 detectOpportunity
- [ ] 实现利润计算 (含费用)
- [ ] 添加基础测试

### Task 2: 执行引擎 (Day 2)

- [ ] 实现 executeArbitrage
- [ ] 实现同步下单
- [ ] 实现订单等待
- [ ] 处理部分成交

### Task 3: 风险控制 (Day 2-3)

- [ ] 仓位限制
- [ ] 冷却时间
- [ ] 最大滑点检查
- [ ] 紧急停止

### Task 4: 集成测试 (Day 3-4)

- [ ] Paper Trading 测试
- [ ] 双交易所模拟
- [ ] 性能测试
- [ ] 统计报告

---

## 测试计划

### 单元测试

```zig
test "Arbitrage profit calculation" {
    var arb = CrossExchangeArbitrage.init(testing.allocator, .{
        .symbol = "ETH",
        .min_profit_bps = 10,
        .trade_amount = Decimal.fromFloat(0.1),
        .fee_bps_a = 10,
        .fee_bps_b = 10,
        .max_position = Decimal.fromFloat(1.0),
    }, exchange_a, exchange_b);

    // 模拟报价: A ask=2000, B bid=2010
    const calc = arb.calculateProfit(
        Decimal.fromInt(2000),
        Decimal.fromInt(2010),
        .a_to_b,
    );

    // 毛利润: (2010-2000)/2000 = 50 bps
    try testing.expect(calc.gross_profit_bps == 50);
    // 费用: 20 bps
    try testing.expect(calc.fee_bps == 20);
    // 净利润: 30 bps
    try testing.expect(calc.net_profit_bps == 30);
}

test "Arbitrage opportunity detection" {
    // 设置模拟报价
    mock_exchange_a.setQuote(.{ .bid = Decimal.fromInt(1995), .ask = Decimal.fromInt(2000) });
    mock_exchange_b.setQuote(.{ .bid = Decimal.fromInt(2010), .ask = Decimal.fromInt(2015) });

    var arb = CrossExchangeArbitrage.init(testing.allocator, config, mock_a, mock_b);

    const opp = arb.detectOpportunity();
    try testing.expect(opp != null);
    try testing.expect(opp.?.direction == .a_to_b);
    try testing.expect(opp.?.net_profit_bps > 0);
}
```

### 场景测试

| 场景 | A 报价 | B 报价 | 预期结果 |
|------|--------|--------|----------|
| 明显套利 | Ask=2000 | Bid=2020 | 执行 A→B |
| 费用后无利润 | Ask=2000 | Bid=2003 | 不执行 |
| 反向套利 | Bid=2020 | Ask=2000 | 执行 B→A |
| 无机会 | Ask=2000 | Bid=1998 | 不执行 |

---

## 验收标准

### 功能验收

- [ ] 正确检测套利机会
- [ ] 利润计算准确 (含费用)
- [ ] 执行同步下单
- [ ] 风险控制有效

### 性能验收

- [ ] 检测延迟 < 1ms
- [ ] 执行延迟 < 10ms
- [ ] 机会捕获率 > 80%

### 代码验收

- [ ] 完整单元测试
- [ ] Paper Trading 验证
- [ ] 文档完整

---

## 风险和注意事项

### 执行风险

1. **网络延迟**: 两个交易所的延迟不同可能导致执行时机会消失
2. **部分成交**: 一边成交另一边未成交导致仓位风险
3. **滑点**: 实际成交价与预期价格差异

### 缓解措施

1. 使用限价单而非市价单
2. 设置合理的订单超时
3. 部分成交时及时取消对手方
4. 实时监控仓位不平衡

---

## 文件结构

```
src/market_making/
├── mod.zig           # 模块导出
├── clock.zig         # Clock (Story 033)
├── pure_mm.zig       # Pure MM (Story 034)
├── inventory.zig     # 库存管理 (Story 035)
└── arbitrage.zig     # 套利策略

tests/
└── arbitrage_test.zig
```

---

**Story**: 037
**版本**: v0.7.0
**创建时间**: 2025-12-27
