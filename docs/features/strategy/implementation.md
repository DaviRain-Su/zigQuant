# Strategy Framework 实现细节

**版本**: v0.3.0
**更新时间**: 2025-12-25

---

## 📋 目录

1. [文件组织](#文件组织)
2. [VTable 实现](#vtable-实现)
3. [策略生命周期](#策略生命周期)
4. [指标管理](#指标管理)
5. [信号生成](#信号生成)
6. [风险管理](#风险管理)
7. [内存管理](#内存管理)
8. [性能优化](#性能优化)

---

## 📂 文件组织

### 目录结构

```
src/strategy/
├── interface.zig           # IStrategy 接口定义
├── context.zig             # StrategyContext 实现
├── executor.zig            # OrderExecutor 实现
├── signal.zig              # Signal 相关类型
├── risk.zig                # RiskManager 实现
├── types.zig               # 公共类型定义
├── candles.zig             # Candles 数据结构
│
├── indicators/             # 技术指标库
│   ├── interface.zig       # IIndicator 接口
│   ├── manager.zig         # IndicatorManager
│   ├── sma.zig             # 简单移动平均
│   ├── ema.zig             # 指数移动平均
│   ├── rsi.zig             # 相对强弱指标
│   ├── macd.zig            # MACD
│   ├── bollinger.zig       # 布林带
│   └── utils.zig           # 工具函数
│
└── builtin/                # 内置策略
    ├── dual_ma.zig         # 双均线策略
    ├── mean_reversion.zig  # 均值回归策略
    └── breakout.zig        # 突破策略
```

### 模块导出

**src/root.zig**:
```zig
// Strategy framework
pub const strategy = @import("strategy/interface.zig");
pub const IStrategy = strategy.IStrategy;
pub const StrategyContext = @import("strategy/context.zig").StrategyContext;
pub const Signal = @import("strategy/signal.zig").Signal;
pub const SignalType = @import("strategy/signal.zig").SignalType;

// Indicators
pub const indicators = @import("strategy/indicators/interface.zig");
pub const SMA = @import("strategy/indicators/sma.zig").SMA;
pub const EMA = @import("strategy/indicators/ema.zig").EMA;
pub const RSI = @import("strategy/indicators/rsi.zig").RSI;
pub const MACD = @import("strategy/indicators/macd.zig").MACD;
pub const BollingerBands = @import("strategy/indicators/bollinger.zig").BollingerBands;

// Built-in strategies
pub const DualMAStrategy = @import("strategy/builtin/dual_ma.zig").DualMAStrategy;
pub const RSIMeanReversionStrategy = @import("strategy/builtin/mean_reversion.zig").RSIMeanReversionStrategy;
pub const BollingerBreakoutStrategy = @import("strategy/builtin/breakout.zig").BollingerBreakoutStrategy;
```

---

## 🔧 VTable 实现

### VTable 模式

参考 Exchange Router 的设计，使用 anyopaque + vtable 模式：

```zig
// src/strategy/interface.zig
pub const IStrategy = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        init: *const fn (*anyopaque, StrategyContext) anyerror!void,
        deinit: *const fn (*anyopaque) void,
        populateIndicators: *const fn (*anyopaque, *Candles) anyerror!void,
        generateEntrySignal: *const fn (*anyopaque, *Candles, usize) anyerror!?Signal,
        generateExitSignal: *const fn (*anyopaque, *Candles, Position) anyerror!?Signal,
        calculatePositionSize: *const fn (*anyopaque, Signal, Account) anyerror!Decimal,
        getParameters: *const fn (*anyopaque) []StrategyParameter,
        getMetadata: *const fn (*anyopaque) StrategyMetadata,
    };

    // 代理方法
    pub fn init(self: IStrategy, ctx: StrategyContext) !void {
        return self.vtable.init(self.ptr, ctx);
    }

    pub fn deinit(self: IStrategy) void {
        return self.vtable.deinit(self.ptr);
    }

    pub fn populateIndicators(self: IStrategy, candles: *Candles) !void {
        return self.vtable.populateIndicators(self.ptr, candles);
    }

    pub fn generateEntrySignal(self: IStrategy, candles: *Candles, index: usize) !?Signal {
        return self.vtable.generateEntrySignal(self.ptr, candles, index);
    }

    pub fn generateExitSignal(self: IStrategy, candles: *Candles, pos: Position) !?Signal {
        return self.vtable.generateExitSignal(self.ptr, candles, pos);
    }

    pub fn calculatePositionSize(self: IStrategy, signal: Signal, account: Account) !Decimal {
        return self.vtable.calculatePositionSize(self.ptr, signal, account);
    }

    pub fn getParameters(self: IStrategy) []StrategyParameter {
        return self.vtable.getParameters(self.ptr);
    }

    pub fn getMetadata(self: IStrategy) StrategyMetadata {
        return self.vtable.getMetadata(self.ptr);
    }
};
```

### 策略实现示例

```zig
// src/strategy/builtin/dual_ma.zig
pub const DualMAStrategy = struct {
    allocator: std.mem.Allocator,
    ctx: StrategyContext,

    // 策略参数
    fast_period: u32,
    slow_period: u32,

    pub fn create(allocator: std.mem.Allocator, fast: u32, slow: u32) !IStrategy {
        const self = try allocator.create(DualMAStrategy);
        self.* = .{
            .allocator = allocator,
            .ctx = undefined,
            .fast_period = fast,
            .slow_period = slow,
        };

        return IStrategy{
            .ptr = self,
            .vtable = &vtable,
        };
    }

    // VTable 实现
    fn initImpl(ptr: *anyopaque, ctx: StrategyContext) !void {
        const self: *DualMAStrategy = @ptrCast(@alignCast(ptr));
        self.ctx = ctx;
    }

    fn deinitImpl(ptr: *anyopaque) void {
        const self: *DualMAStrategy = @ptrCast(@alignCast(ptr));
        self.allocator.destroy(self);
    }

    fn populateIndicatorsImpl(ptr: *anyopaque, candles: *Candles) !void {
        const self: *DualMAStrategy = @ptrCast(@alignCast(ptr));

        const fast_ma = try SMA.init(self.allocator, self.fast_period).calculate(candles.data);
        try candles.addIndicator("ma_fast", fast_ma);

        const slow_ma = try SMA.init(self.allocator, self.slow_period).calculate(candles.data);
        try candles.addIndicator("ma_slow", slow_ma);
    }

    // ... 其他 vtable 方法

    const vtable = IStrategy.VTable{
        .init = initImpl,
        .deinit = deinitImpl,
        .populateIndicators = populateIndicatorsImpl,
        .generateEntrySignal = generateEntrySignalImpl,
        .generateExitSignal = generateExitSignalImpl,
        .calculatePositionSize = calculatePositionSizeImpl,
        .getParameters = getParametersImpl,
        .getMetadata = getMetadataImpl,
    };
};
```

---

## 🔄 策略生命周期

### 回测模式生命周期

```
1. 创建策略
   │
   ├─> strategy = DualMAStrategy.create(allocator, 10, 20)
   │
2. 初始化
   │
   ├─> strategy.init(ctx)
   │
3. 计算指标（一次性）
   │
   ├─> strategy.populateIndicators(candles)
   │   │
   │   └─> 计算所有蜡烛的指标值
   │       - SMA(10)
   │       - SMA(20)
   │
4. 遍历蜡烛
   │
   ├─> for (candles, 0..) |candle, i| {
   │       │
   │       ├─> 生成入场信号
   │       │   signal = strategy.generateEntrySignal(candles, i)
   │       │
   │       ├─> 如果有信号且无持仓
   │       │   │
   │       │   ├─> 计算仓位大小
   │       │   │   size = strategy.calculatePositionSize(signal, account)
   │       │   │
   │       │   └─> 开仓
   │       │       position = openPosition(signal, size)
   │       │
   │       ├─> 如果有持仓
   │       │   │
   │       │   ├─> 检查主动出场信号
   │       │   │   exit_signal = strategy.generateExitSignal(candles, position)
   │       │   │
   │       │   ├─> 检查被动止盈止损
   │       │   │   risk_manager.checkStopLoss(position, current_price)
   │       │   │   risk_manager.checkTakeProfit(position, current_price)
   │       │   │
   │       │   └─> 如果需要平仓
   │       │       closePosition(position)
   │       │
   │   }
   │
5. 清理资源
   │
   └─> strategy.deinit()
```

### 实时模式生命周期

```
1. 创建和初始化
   │
   ├─> strategy = DualMAStrategy.create(allocator, 10, 20)
   ├─> strategy.init(ctx)
   │
2. 实时循环
   │
   └─> loop {
       │
       ├─> 等待新蜡烛
       │   candle = await market_data.waitForCandle()
       │
       ├─> 更新蜡烛数据
       │   candles.append(candle)
       │
       ├─> 重新计算指标
       │   strategy.populateIndicators(candles)
       │
       ├─> 生成信号
       │   signal = strategy.generateEntrySignal(candles, candles.len - 1)
       │
       ├─> 执行交易逻辑
       │   if (signal) |sig| {
       │       executor.executeSignal(sig)
       │   }
       │
       └─> 检查现有持仓
           for (positions) |pos| {
               exit_signal = strategy.generateExitSignal(candles, pos)
               if (exit_signal) |exit| {
                   executor.executeSignal(exit)
               }
           }
   }
```

---

## 📊 指标管理

### IndicatorManager 实现

```zig
// src/strategy/indicators/manager.zig
pub const IndicatorManager = struct {
    allocator: std.mem.Allocator,
    cache: std.StringHashMap(CachedIndicator),

    const CachedIndicator = struct {
        values: []Decimal,
        last_candle_count: usize,
        hash: u64,  // 参数哈希
    };

    pub fn init(allocator: std.mem.Allocator) IndicatorManager {
        return .{
            .allocator = allocator,
            .cache = std.StringHashMap(CachedIndicator).init(allocator),
        };
    }

    pub fn deinit(self: *IndicatorManager) void {
        var it = self.cache.valueIterator();
        while (it.next()) |cached| {
            self.allocator.free(cached.values);
        }
        self.cache.deinit();
    }

    /// 获取指标（带缓存）
    pub fn getIndicator(
        self: *IndicatorManager,
        name: []const u8,
        candles: []Candle,
        params_hash: u64,
        calculate_fn: *const fn ([]Candle) anyerror![]Decimal,
    ) ![]Decimal {
        // 检查缓存
        if (self.cache.get(name)) |cached| {
            // 验证缓存有效性
            if (cached.last_candle_count == candles.len and cached.hash == params_hash) {
                return cached.values;
            }

            // 缓存失效，释放旧数据
            self.allocator.free(cached.values);
            _ = self.cache.remove(name);
        }

        // 计算新值
        const values = try calculate_fn(candles);

        // 存入缓存
        try self.cache.put(name, CachedIndicator{
            .values = values,
            .last_candle_count = candles.len,
            .hash = params_hash,
        });

        return values;
    }

    /// 清除缓存（蜡烛数据变化时）
    pub fn clearCache(self: *IndicatorManager) void {
        var it = self.cache.valueIterator();
        while (it.next()) |cached| {
            self.allocator.free(cached.values);
        }
        self.cache.clearRetainingCapacity();
    }
};
```

### Candles 数据结构

```zig
// src/strategy/candles.zig
pub const Candles = struct {
    allocator: std.mem.Allocator,
    data: []Candle,
    indicators: std.StringHashMap([]Decimal),

    pub fn init(allocator: std.mem.Allocator, data: []Candle) Candles {
        return .{
            .allocator = allocator,
            .data = data,
            .indicators = std.StringHashMap([]Decimal).init(allocator),
        };
    }

    pub fn deinit(self: *Candles) void {
        // 释放所有指标数据
        var it = self.indicators.valueIterator();
        while (it.next()) |values| {
            self.allocator.free(values.*);
        }
        self.indicators.deinit();
    }

    /// 添加指标
    pub fn addIndicator(self: *Candles, name: []const u8, values: []Decimal) !void {
        if (values.len != self.data.len) {
            return error.IndicatorLengthMismatch;
        }

        // 如果已存在，先释放旧数据
        if (self.indicators.get(name)) |old_values| {
            self.allocator.free(old_values);
        }

        try self.indicators.put(name, values);
    }

    /// 获取指标
    pub fn getIndicator(self: *Candles, name: []const u8) ?[]Decimal {
        return self.indicators.get(name);
    }
};
```

---

## 🎯 信号生成

### 信号生成流程

```zig
// 伪代码示例
fn generateEntrySignalImpl(ptr: *anyopaque, candles: *Candles, index: usize) !?Signal {
    const self: *MyStrategy = @ptrCast(@alignCast(ptr));

    // 1. 检查数据充足性
    if (index < self.startup_candle_count) return null;

    // 2. 获取指标数据
    const ma_fast = candles.getIndicator("ma_fast") orelse return null;
    const ma_slow = candles.getIndicator("ma_slow") orelse return null;
    const rsi = candles.getIndicator("rsi") orelse return null;

    // 3. 检查信号条件
    const prev_fast = ma_fast[index - 1];
    const curr_fast = ma_fast[index];
    const prev_slow = ma_slow[index - 1];
    const curr_slow = ma_slow[index];
    const curr_rsi = rsi[index];

    // 金叉 + RSI 不超买
    if (prev_fast.lte(prev_slow) and curr_fast.gt(curr_slow) and curr_rsi.lt(try Decimal.fromInt(70))) {
        // 4. 计算信号强度
        const ma_diff = try curr_fast.sub(curr_slow);
        const ma_diff_pct = try ma_diff.div(curr_slow);
        const strength = @min(ma_diff_pct.toFloat() * 10.0, 1.0);  // 归一化到 [0, 1]

        // 5. 返回信号
        return Signal{
            .type = .entry_long,
            .pair = self.ctx.config.pair,
            .side = .buy,
            .price = candles.data[index].close,
            .strength = strength,
            .timestamp = candles.data[index].timestamp,
            .metadata = SignalMetadata{
                .reason = "Golden Cross + RSI OK",
                .indicators = &[_]IndicatorValue{
                    .{ .name = "ma_fast", .value = curr_fast },
                    .{ .name = "ma_slow", .value = curr_slow },
                    .{ .name = "rsi", .value = curr_rsi },
                },
            },
        };
    }

    return null;
}
```

---

## 🛡️ 风险管理

### RiskManager 实现

```zig
// src/strategy/risk.zig
pub const RiskManager = struct {
    allocator: std.mem.Allocator,
    logger: Logger,
    config: RiskConfig,

    pub const RiskConfig = struct {
        max_position_size: Decimal,       // 最大仓位
        max_leverage: u32,                // 最大杠杆
        max_drawdown: f64,                // 最大回撤
        max_daily_loss: Decimal,          // 每日最大亏损
    };

    /// 验证订单是否符合风控规则
    pub fn validateOrder(
        self: *RiskManager,
        order: OrderRequest,
        account: Account,
    ) !void {
        // 1. 检查仓位大小
        if (order.quantity.gt(self.config.max_position_size)) {
            try self.logger.warn("Order rejected: exceeds max position size", .{
                .requested = order.quantity,
                .max = self.config.max_position_size,
            });
            return error.ExceedsMaxPositionSize;
        }

        // 2. 检查杠杆
        if (account.leverage > self.config.max_leverage) {
            try self.logger.warn("Order rejected: exceeds max leverage", .{
                .current = account.leverage,
                .max = self.config.max_leverage,
            });
            return error.ExceedsMaxLeverage;
        }

        // 3. 检查可用余额
        const required_margin = try order.quantity.mul(order.price).div(
            try Decimal.fromInt(account.leverage)
        );
        if (required_margin.gt(account.balance.available)) {
            try self.logger.warn("Order rejected: insufficient balance", .{
                .required = required_margin,
                .available = account.balance.available,
            });
            return error.InsufficientBalance;
        }
    }

    /// 检查止损
    pub fn checkStopLoss(
        self: *RiskManager,
        pos: Position,
        current_price: Decimal,
        metadata: StrategyMetadata,
    ) !?Signal {
        const entry_price = pos.entry_price;
        const pnl_pct = blk: {
            if (pos.side == .long) {
                const diff = try current_price.sub(entry_price);
                break :blk try diff.div(entry_price);
            } else {
                const diff = try entry_price.sub(current_price);
                break :blk try diff.div(entry_price);
            }
        };

        if (pnl_pct.lte(metadata.stoploss)) {
            try self.logger.info("Stop loss triggered", .{
                .pair = pos.pair,
                .pnl_pct = pnl_pct,
                .stoploss = metadata.stoploss,
            });

            return Signal{
                .type = if (pos.side == .long) .exit_long else .exit_short,
                .pair = pos.pair,
                .side = if (pos.side == .long) .sell else .buy,
                .price = current_price,
                .strength = 1.0,
                .timestamp = Timestamp.now(),
                .metadata = null,
            };
        }

        return null;
    }

    /// 检查止盈
    pub fn checkTakeProfit(
        self: *RiskManager,
        pos: Position,
        current_price: Decimal,
        metadata: StrategyMetadata,
    ) !?Signal {
        const entry_price = pos.entry_price;
        const pnl_pct = blk: {
            if (pos.side == .long) {
                const diff = try current_price.sub(entry_price);
                break :blk try diff.div(entry_price);
            } else {
                const diff = try entry_price.sub(current_price);
                break :blk try diff.div(entry_price);
            }
        };

        const hold_time_minutes = blk: {
            const now = Timestamp.now();
            const diff_ms = try now.sub(pos.timestamp);
            break :blk @divTrunc(diff_ms, 60000);
        };

        // 检查 minimal_roi 目标
        for (metadata.minimal_roi.targets) |target| {
            if (hold_time_minutes >= target.time_minutes and pnl_pct.gte(target.profit_ratio)) {
                try self.logger.info("Take profit triggered", .{
                    .pair = pos.pair,
                    .pnl_pct = pnl_pct,
                    .target = target.profit_ratio,
                    .hold_time = hold_time_minutes,
                });

                return Signal{
                    .type = if (pos.side == .long) .exit_long else .exit_short,
                    .pair = pos.pair,
                    .side = if (pos.side == .long) .sell else .buy,
                    .price = current_price,
                    .strength = 1.0,
                    .timestamp = Timestamp.now(),
                    .metadata = null,
                };
            }
        }

        return null;
    }
};
```

---

## 💾 内存管理

### 策略内存分配

- **策略实例**: 使用 `allocator.create()` 创建，`allocator.destroy()` 销毁
- **指标数据**: 由 Candles 管理，策略不拥有
- **内部缓存**: 策略内部分配的数据必须在 `deinit()` 中释放

### 内存所有权

```
┌─────────────────────────────────────────┐
│         Backtest Engine                 │
│  (拥有 Candles)                          │
├─────────────────────────────────────────┤
│                                          │
│  ┌────────────────────┐                 │
│  │      Candles       │                 │
│  ├────────────────────┤                 │
│  │ - data: []Candle   │ (owned)         │
│  │ - indicators: Map  │ (owned)         │
│  └────────────────────┘                 │
│           │                              │
│           ▼                              │
│  ┌────────────────────┐                 │
│  │     Strategy       │                 │
│  ├────────────────────┤                 │
│  │ - ctx: Context     │ (borrowed)      │
│  │ - cache: ?Data     │ (owned)         │
│  └────────────────────┘                 │
│                                          │
└─────────────────────────────────────────┘
```

### 内存泄漏检测

使用 GeneralPurposeAllocator 自动检测：

```zig
test "strategy no memory leak" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        try std.testing.expect(leaked == .ok);
    }
    const allocator = gpa.allocator();

    // 测试逻辑
    const strategy = try DualMAStrategy.create(allocator, 10, 20);
    defer strategy.deinit();

    // ...
}
```

---

## ⚡ 性能优化

### 1. 指标缓存

避免重复计算：

```zig
// 错误: 每次都重新计算
fn populateIndicators(ptr: *anyopaque, candles: *Candles) !void {
    const sma = try SMA.calculate(candles.data);  // ❌ 每次都重新计算
    try candles.addIndicator("sma", sma);
}

// 正确: 使用 IndicatorManager 缓存
fn populateIndicators(ptr: *anyopaque, candles: *Candles) !void {
    const self: *MyStrategy = @ptrCast(@alignCast(ptr));
    const sma = try self.ctx.indicator_manager.getIndicator(
        "sma_20",
        candles.data,
        hash(self.period),
        SMA.calculate,
    );  // ✅ 自动缓存
    try candles.addIndicator("sma", sma);
}
```

### 2. 避免动态分配

在信号生成中尽量使用栈分配：

```zig
// 错误: 动态分配 metadata
fn generateEntrySignal(...) !?Signal {
    const metadata = try allocator.create(SignalMetadata);  // ❌ 每次分配
    metadata.* = .{ .reason = "...", ... };
    return Signal{ .metadata = metadata, ... };
}

// 正确: 使用栈分配或 null
fn generateEntrySignal(...) !?Signal {
    return Signal{
        .metadata = null,  // ✅ 无分配，或使用 comptime 字符串
        ...
    };
}
```

### 3. 批量计算

指标计算使用向量化：

```zig
// 未来优化: 使用 SIMD
pub fn calculate(self: SMA, candles: []const Candle) ![]Decimal {
    // 可以考虑使用 @Vector 加速
    const vec_size = 4;
    // ... SIMD 计算逻辑
}
```

### 4. 早期返回

在信号生成中尽早返回：

```zig
fn generateEntrySignal(...) !?Signal {
    // ✅ 数据不足时立即返回
    if (index < self.startup_candle_count) return null;

    // ✅ 指标缺失时立即返回
    const ma = candles.getIndicator("ma") orelse return null;

    // ✅ 条件不满足时立即返回
    if (!conditionMet()) return null;

    // 复杂计算...
}
```

---

## 🔍 调试技巧

### 1. 日志记录

```zig
fn generateEntrySignal(...) !?Signal {
    const self: *MyStrategy = @ptrCast(@alignCast(ptr));

    try self.ctx.logger.debug("Checking entry signal", .{
        .index = index,
        .price = candles.data[index].close,
    });

    // ... 信号生成逻辑

    if (signal_found) {
        try self.ctx.logger.info("Entry signal generated", .{
            .type = signal.type,
            .price = signal.price,
            .strength = signal.strength,
        });
    }

    return signal;
}
```

### 2. 断言检查

```zig
fn populateIndicators(...) !void {
    const sma = try SMA.calculate(candles.data);

    // 验证指标长度
    std.debug.assert(sma.len == candles.data.len);

    // 验证指标值有效
    for (sma) |value| {
        std.debug.assert(!value.isNaN() or value == Decimal.NaN);
    }

    try candles.addIndicator("sma", sma);
}
```

---

**版本**: v0.3.0
**状态**: 设计阶段
**更新时间**: 2025-12-25
