# Story 034: Pure Market Making 策略

**版本**: v0.7.0
**状态**: 待开发
**优先级**: P0
**预计时间**: 3-4 天
**依赖**: Story 033 (Clock-Driven)

---

## 概述

实现 Pure Market Making 策略，在 mid price 两侧放置买卖订单，通过买卖价差获取利润。这是最基础的做市策略，为后续高级策略奠定基础。

---

## 背景

### 什么是做市 (Market Making)?

```
┌─────────────────────────────────────────────────────────────────┐
│                      做市策略原理                                │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│                    Order Book                                    │
│                                                                  │
│  卖单 (Asks)                                                    │
│  ├── 2010.00  (我的卖单)  ←── Ask                               │
│  ├── 2009.50                                                    │
│  ├── 2009.00                                                    │
│  │                                                              │
│  │   2005.00  ←── Mid Price (中间价)                            │
│  │                                                              │
│  ├── 2001.00                                                    │
│  ├── 2000.50                                                    │
│  └── 2000.00  (我的买单)  ←── Bid                               │
│  买单 (Bids)                                                    │
│                                                                  │
│  价差 (Spread) = Ask - Bid = 2010 - 2000 = 10 (0.5%)            │
│  利润来源: 低买高卖 (买入 2000, 卖出 2010)                      │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 策略风险

1. **库存风险**: 单边成交导致仓位累积
2. **逆向选择**: 知情交易者利用信息优势
3. **市场风险**: 价格剧烈波动
4. **执行风险**: 订单延迟或部分成交

---

## 技术设计

### 核心组件

```
┌─────────────────────────────────────────────────────────────────┐
│                   Pure Market Making 架构                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │                  PureMarketMaking                         │  │
│  │                                                            │  │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐       │  │
│  │  │   Config    │  │   State     │  │  Executor   │       │  │
│  │  │ - spread    │  │ - position  │  │ - submit    │       │  │
│  │  │ - amount    │  │ - orders    │  │ - cancel    │       │  │
│  │  │ - levels    │  │ - pnl       │  │ - modify    │       │  │
│  │  └─────────────┘  └─────────────┘  └─────────────┘       │  │
│  │                                                            │  │
│  │  implements IClockStrategy                                │  │
│  └──────────────────────────────────────────────────────────┘  │
│                           ↓                                     │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │                    onTick() 流程                          │  │
│  │                                                            │  │
│  │  1. 获取 mid price                                        │  │
│  │  2. 检查是否需要更新报价                                  │  │
│  │  3. 取消旧订单                                            │  │
│  │  4. 计算新报价                                            │  │
│  │  5. 下新订单                                              │  │
│  │  6. 更新状态                                              │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 策略配置

```zig
/// Pure Market Making 配置
pub const PureMMConfig = struct {
    /// 交易对
    symbol: []const u8,

    /// 价差 (basis points, 1 bp = 0.01%)
    /// 例: 10 bps = 0.1% spread
    spread_bps: u32 = 10,

    /// 单边订单数量
    order_amount: Decimal,

    /// 价格层级数 (每边)
    order_levels: u32 = 1,

    /// 层级间价差 (basis points)
    level_spread_bps: u32 = 5,

    /// 最小报价更新阈值 (mid price 变化)
    min_refresh_bps: u32 = 2,

    /// 订单有效时间 (ticks)
    order_ttl_ticks: u32 = 60,

    /// 最大仓位
    max_position: Decimal,

    /// 是否启用两侧报价
    dual_side: bool = true,
};
```

### 策略实现

```zig
const std = @import("std");
const Allocator = std.mem.Allocator;
const Decimal = @import("../core/decimal.zig").Decimal;

/// Pure Market Making 策略
pub const PureMarketMaking = struct {
    allocator: Allocator,
    config: PureMMConfig,

    // 状态
    current_position: Decimal,
    active_bids: std.ArrayList(OrderInfo),
    active_asks: std.ArrayList(OrderInfo),
    last_mid_price: ?Decimal,
    last_update_tick: u64,

    // 统计
    total_trades: u64,
    total_volume: Decimal,
    realized_pnl: Decimal,

    // 依赖
    data_provider: *IDataProvider,
    executor: *IExecutionClient,

    const Self = @This();

    pub fn init(
        allocator: Allocator,
        config: PureMMConfig,
        data_provider: *IDataProvider,
        executor: *IExecutionClient,
    ) Self {
        return .{
            .allocator = allocator,
            .config = config,
            .current_position = Decimal.zero,
            .active_bids = std.ArrayList(OrderInfo).init(allocator),
            .active_asks = std.ArrayList(OrderInfo).init(allocator),
            .last_mid_price = null,
            .last_update_tick = 0,
            .total_trades = 0,
            .total_volume = Decimal.zero,
            .realized_pnl = Decimal.zero,
            .data_provider = data_provider,
            .executor = executor,
        };
    }

    pub fn deinit(self: *Self) void {
        self.active_bids.deinit();
        self.active_asks.deinit();
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
        _ = timestamp;

        // 1. 获取当前 mid price
        const mid = self.getMidPrice() orelse return;

        // 2. 检查是否需要更新报价
        if (self.shouldRefreshQuotes(mid)) {
            // 3. 取消所有现有订单
            try self.cancelAllOrders();

            // 4. 下新订单
            try self.placeQuotes(mid);

            self.last_mid_price = mid;
            self.last_update_tick = tick;
        }
    }

    fn onStartImpl(ptr: *anyopaque) anyerror!void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        std.log.info("[PureMM] Starting for {s}", .{self.config.symbol});
    }

    fn onStopImpl(ptr: *anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        std.log.info("[PureMM] Stopping, canceling all orders", .{});
        self.cancelAllOrders() catch {};
    }

    /// 获取中间价
    fn getMidPrice(self: *Self) ?Decimal {
        const quote = self.data_provider.getQuote(self.config.symbol) orelse return null;
        return quote.bid.add(quote.ask).div(Decimal.fromInt(2));
    }

    /// 检查是否需要刷新报价
    fn shouldRefreshQuotes(self: *Self, current_mid: Decimal) bool {
        const last_mid = self.last_mid_price orelse return true;

        // 计算变化幅度 (basis points)
        const change = current_mid.sub(last_mid).abs();
        const change_bps = change.div(last_mid).mul(Decimal.fromInt(10000));

        return change_bps.toFloat() >= @as(f64, @floatFromInt(self.config.min_refresh_bps));
    }

    /// 下报价单
    fn placeQuotes(self: *Self, mid: Decimal) !void {
        // 检查仓位限制
        if (self.current_position.abs().compare(self.config.max_position) == .gt) {
            std.log.warn("[PureMM] Max position reached, skipping quotes", .{});
            return;
        }

        const half_spread = mid.mul(
            Decimal.fromFloat(@as(f64, @floatFromInt(self.config.spread_bps)) / 20000.0)
        );

        // 多层级报价
        for (0..self.config.order_levels) |i| {
            const level_offset = if (i == 0)
                Decimal.zero
            else
                mid.mul(Decimal.fromFloat(
                    @as(f64, @floatFromInt(i * self.config.level_spread_bps)) / 10000.0
                ));

            // 买单
            if (self.config.dual_side or self.current_position.toFloat() < 0) {
                const bid_price = mid.sub(half_spread).sub(level_offset);
                try self.placeBid(bid_price, self.config.order_amount);
            }

            // 卖单
            if (self.config.dual_side or self.current_position.toFloat() > 0) {
                const ask_price = mid.add(half_spread).add(level_offset);
                try self.placeAsk(ask_price, self.config.order_amount);
            }
        }
    }

    fn placeBid(self: *Self, price: Decimal, amount: Decimal) !void {
        const order = try self.executor.submitOrder(.{
            .symbol = self.config.symbol,
            .side = .buy,
            .order_type = .limit,
            .quantity = amount,
            .price = price,
        });

        try self.active_bids.append(.{
            .order_id = order.id,
            .price = price,
            .amount = amount,
        });
    }

    fn placeAsk(self: *Self, price: Decimal, amount: Decimal) !void {
        const order = try self.executor.submitOrder(.{
            .symbol = self.config.symbol,
            .side = .sell,
            .order_type = .limit,
            .quantity = amount,
            .price = price,
        });

        try self.active_asks.append(.{
            .order_id = order.id,
            .price = price,
            .amount = amount,
        });
    }

    fn cancelAllOrders(self: *Self) !void {
        for (self.active_bids.items) |order| {
            self.executor.cancelOrder(order.order_id) catch {};
        }
        self.active_bids.clearRetainingCapacity();

        for (self.active_asks.items) |order| {
            self.executor.cancelOrder(order.order_id) catch {};
        }
        self.active_asks.clearRetainingCapacity();
    }

    /// 处理成交回报
    pub fn onFill(self: *Self, fill: OrderFill) void {
        if (fill.side == .buy) {
            self.current_position = self.current_position.add(fill.quantity);
        } else {
            self.current_position = self.current_position.sub(fill.quantity);
        }

        self.total_trades += 1;
        self.total_volume = self.total_volume.add(fill.quantity.mul(fill.price));

        std.log.info("[PureMM] Fill: {} {s} @ {}, position: {}", .{
            fill.quantity,
            if (fill.side == .buy) "BUY" else "SELL",
            fill.price,
            self.current_position,
        });
    }

    /// 获取统计信息
    pub fn getStats(self: *Self) MMStats {
        return .{
            .total_trades = self.total_trades,
            .total_volume = self.total_volume,
            .current_position = self.current_position,
            .realized_pnl = self.realized_pnl,
            .active_bids = self.active_bids.items.len,
            .active_asks = self.active_asks.items.len,
        };
    }
};

pub const OrderInfo = struct {
    order_id: u64,
    price: Decimal,
    amount: Decimal,
};

pub const MMStats = struct {
    total_trades: u64,
    total_volume: Decimal,
    current_position: Decimal,
    realized_pnl: Decimal,
    active_bids: usize,
    active_asks: usize,
};
```

---

## 实现任务

### Task 1: 策略配置 (Day 1)

- [ ] 创建 `src/market_making/pure_mm.zig`
- [ ] 定义 PureMMConfig 结构
- [ ] 实现配置验证
- [ ] 支持 JSON 配置加载

### Task 2: 核心逻辑 (Day 1-2)

- [ ] 实现 IClockStrategy 接口
- [ ] 实现 getMidPrice
- [ ] 实现 shouldRefreshQuotes
- [ ] 实现 placeQuotes

### Task 3: 订单管理 (Day 2)

- [ ] 实现多层级报价
- [ ] 实现订单取消
- [ ] 实现成交回调
- [ ] 实现仓位限制

### Task 4: 统计和监控 (Day 3)

- [ ] 实现 PnL 计算
- [ ] 实现交易统计
- [ ] 添加日志输出
- [ ] 实现状态查询

### Task 5: 测试和验证 (Day 3-4)

- [ ] 单元测试
- [ ] Paper Trading 测试
- [ ] 参数优化测试
- [ ] 文档编写

---

## 测试计划

### 单元测试

```zig
test "PureMM quote calculation" {
    const mid = Decimal.fromInt(2000);
    const spread_bps: u32 = 10;  // 0.1%

    // 计算预期报价
    const half_spread = mid.mul(Decimal.fromFloat(0.0005));  // 0.05%
    const expected_bid = mid.sub(half_spread);  // 1999
    const expected_ask = mid.add(half_spread);  // 2001

    try testing.expect(expected_bid.toFloat() < mid.toFloat());
    try testing.expect(expected_ask.toFloat() > mid.toFloat());
}

test "PureMM position update" {
    var mm = PureMarketMaking.init(testing.allocator, config, provider, executor);
    defer mm.deinit();

    // 模拟买入成交
    mm.onFill(.{
        .side = .buy,
        .quantity = Decimal.fromFloat(0.1),
        .price = Decimal.fromInt(2000),
    });

    try testing.expect(mm.current_position.toFloat() == 0.1);

    // 模拟卖出成交
    mm.onFill(.{
        .side = .sell,
        .quantity = Decimal.fromFloat(0.1),
        .price = Decimal.fromInt(2001),
    });

    try testing.expect(mm.current_position.toFloat() == 0.0);
}
```

### Paper Trading 测试

| 测试场景 | 验证内容 |
|----------|----------|
| 正常做市 | 双边报价，价差正确 |
| 价格变动 | 自动刷新报价 |
| 仓位累积 | 达到限制停止报价 |
| 成交回报 | 仓位正确更新 |

---

## 验收标准

### 功能验收

- [ ] 策略可在 Clock 中运行
- [ ] 双边报价正确
- [ ] 仓位跟踪准确
- [ ] 自动刷新报价

### 性能验收

- [ ] onTick 执行 < 1ms
- [ ] 内存使用稳定
- [ ] 订单延迟 < 10ms

### 代码验收

- [ ] 完整单元测试
- [ ] Paper Trading 验证
- [ ] 代码文档完整

---

## 策略参数调优

### 参数影响

| 参数 | 增大影响 | 减小影响 |
|------|----------|----------|
| spread_bps | 利润高，成交少 | 利润低，成交多 |
| order_amount | 风险大，收益大 | 风险小，收益小 |
| order_levels | 成交概率高 | 资金利用高 |
| min_refresh_bps | 更新少，稳定 | 更新多，敏感 |

### 推荐配置

```zig
// 低风险配置
const conservative = PureMMConfig{
    .spread_bps = 20,        // 0.2%
    .order_amount = Decimal.fromFloat(0.01),
    .order_levels = 1,
    .max_position = Decimal.fromFloat(0.1),
};

// 激进配置
const aggressive = PureMMConfig{
    .spread_bps = 5,         // 0.05%
    .order_amount = Decimal.fromFloat(0.1),
    .order_levels = 3,
    .max_position = Decimal.fromFloat(1.0),
};
```

---

## 文件结构

```
src/market_making/
├── mod.zig           # 模块导出
├── clock.zig         # Clock (Story 033)
├── pure_mm.zig       # Pure Market Making
└── types.zig         # 共享类型

tests/
└── pure_mm_test.zig  # 测试
```

---

**Story**: 034
**版本**: v0.7.0
**创建时间**: 2025-12-27
