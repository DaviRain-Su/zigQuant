# v0.6.0 Overview - 混合计算模式

**版本**: v0.6.0
**状态**: 规划中
**开始时间**: 待定
**前置版本**: v0.5.0 (已完成)
**预计时间**: 3-4 周

---

## 目标

实现向量化回测与事件驱动实盘的混合计算模式，通过交易所适配器将 v0.5.0 的事件驱动架构连接到真实交易环境，并提供 Paper Trading 模式进行策略验证。

## 核心理念

```
┌─────────────────────────────────────────────────────────────┐
│                   zigQuant v0.6.0                           │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │              混合计算模式 (Hybrid Mode)               │   │
│  │  ┌─────────────────┐    ┌─────────────────┐         │   │
│  │  │  向量化回测      │    │  事件驱动实盘    │         │   │
│  │  │  (SIMD优化)     │    │  (v0.5.0架构)   │         │   │
│  │  └─────────────────┘    └─────────────────┘         │   │
│  └──────────────────────────────────────────────────────┘   │
│                         ↓                                    │
│  ┌──────────────────────────────────────────────────────┐   │
│  │                 交易所适配器层                         │   │
│  │  ┌─────────────────┐    ┌─────────────────┐         │   │
│  │  │ DataProvider    │    │ ExecutionClient │         │   │
│  │  │ (IDataProvider) │    │(IExecutionClient)│         │   │
│  │  └─────────────────┘    └─────────────────┘         │   │
│  └──────────────────────────────────────────────────────┘   │
│                         ↓                                    │
│  ┌──────────────────────────────────────────────────────┐   │
│  │                    Hyperliquid DEX                    │   │
│  │           WebSocket + REST API + 订单执行             │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## Stories 规划

| Story | 名称 | 描述 | 优先级 | 预计时间 |
|-------|------|------|--------|----------|
| **028** | 向量化回测引擎 | SIMD 优化批量计算 | P0 | 5-7 天 |
| **029** | HyperliquidDataProvider | 实现 IDataProvider 接口 | P0 | 4-5 天 |
| **030** | HyperliquidExecutionClient | 实现 IExecutionClient 接口 | P0 | 4-5 天 |
| **031** | Paper Trading | 模拟交易模式 | P1 | 3-4 天 |
| **032** | 策略热重载 | 运行时参数更新 | P2 | 2-3 天 |

---

## Story 028: 向量化回测引擎

### 目标
实现高性能向量化回测，利用 SIMD 指令加速批量计算，达到 100,000+ bars/s 的回测速度。

### 核心功能

```zig
pub const VectorizedBacktester = struct {
    allocator: Allocator,

    /// SIMD 批量指标计算
    pub fn computeIndicatorsBatch(
        self: *VectorizedBacktester,
        candles: []const Candle,
    ) !IndicatorResults {
        // 使用 @Vector 进行 SIMD 加速
        const Vec4 = @Vector(4, f64);
        // 批量计算 SMA, EMA, RSI 等
    }

    /// 批量信号生成
    pub fn generateSignalsBatch(
        self: *VectorizedBacktester,
        indicators: IndicatorResults,
    ) ![]Signal {
        // 向量化信号计算
    }

    /// 内存映射数据加载
    pub fn loadDataMmap(
        self: *VectorizedBacktester,
        file_path: []const u8,
    ) ![]Candle {
        // mmap 大文件加载
    }
};
```

### 性能目标
- 回测速度: > 100,000 bars/s
- 内存效率: 使用 mmap 避免大文件完全加载
- 并行支持: 多策略并行回测

### 详细文档
- [STORY_028_VECTORIZED_BACKTESTER.md](./STORY_028_VECTORIZED_BACKTESTER.md)

---

## Story 029: HyperliquidDataProvider

### 目标
实现 IDataProvider 接口，将 Hyperliquid WebSocket 数据流接入事件驱动架构。

### 核心功能

```zig
pub const HyperliquidDataProvider = struct {
    allocator: Allocator,
    ws_client: *WebSocketClient,
    message_bus: *MessageBus,
    cache: *Cache,

    // IDataProvider VTable 实现
    pub const vtable = IDataProvider.VTable{
        .start = start,
        .stop = stop,
        .subscribe = subscribe,
        .unsubscribe = unsubscribe,
    };

    /// 启动数据流
    pub fn start(ctx: *anyopaque) !void {
        const self = @ptrCast(*HyperliquidDataProvider, ctx);
        try self.ws_client.connect();
        // 订阅 allMids, l2Book, trades
    }

    /// 订阅交易对
    pub fn subscribe(ctx: *anyopaque, symbol: []const u8) !void {
        const self = @ptrCast(*HyperliquidDataProvider, ctx);
        try self.ws_client.subscribe(.{
            .channel = "l2Book",
            .coin = symbol,
        });
    }

    /// WebSocket 消息处理
    fn onMessage(self: *HyperliquidDataProvider, msg: []const u8) void {
        // 解析消息
        // 更新 Cache
        // 发布事件到 MessageBus
        self.message_bus.publish("market_data.quote", .{
            .market_data = parsed_data,
        });
    }
};
```

### 数据流
```
Hyperliquid WS → HyperliquidDataProvider → Cache + MessageBus → Strategy
```

### 详细文档
- [STORY_029_HYPERLIQUID_DATA_PROVIDER.md](./STORY_029_HYPERLIQUID_DATA_PROVIDER.md)

---

## Story 030: HyperliquidExecutionClient

### 目标
实现 IExecutionClient 接口，将订单执行连接到 Hyperliquid DEX。

### 核心功能

```zig
pub const HyperliquidExecutionClient = struct {
    allocator: Allocator,
    http_client: *HttpClient,
    ws_client: *WebSocketClient,
    message_bus: *MessageBus,
    wallet: *Wallet,

    // IExecutionClient VTable 实现
    pub const vtable = IExecutionClient.VTable{
        .submitOrder = submitOrder,
        .cancelOrder = cancelOrder,
        .getOrderStatus = getOrderStatus,
        .getPosition = getPosition,
    };

    /// 提交订单
    pub fn submitOrder(ctx: *anyopaque, order: Order) !OrderResult {
        const self = @ptrCast(*HyperliquidExecutionClient, ctx);

        // 1. 签名订单
        const signed = try self.wallet.signOrder(order);

        // 2. 提交到交易所
        const result = try self.http_client.post("/exchange", signed);

        // 3. 发布事件
        self.message_bus.publish("order.submitted", .{
            .order_submitted = .{
                .order_id = result.order_id,
                .status = .submitted,
            },
        });

        return result;
    }

    /// 订单状态更新 (WebSocket)
    fn onOrderUpdate(self: *HyperliquidExecutionClient, update: OrderUpdate) void {
        self.message_bus.publish("order.updated", .{
            .order_updated = update,
        });
    }
};
```

### 订单流
```
Strategy → ExecutionEngine → HyperliquidExecutionClient → Hyperliquid DEX
                                        ↓
                                   WebSocket 更新
                                        ↓
                                   MessageBus 事件
```

### 详细文档
- [STORY_030_HYPERLIQUID_EXECUTION_CLIENT.md](./STORY_030_HYPERLIQUID_EXECUTION_CLIENT.md)

---

## Story 031: Paper Trading

### 目标
实现模拟交易模式，使用真实市场数据但不实际执行订单。

### 核心功能

```zig
pub const PaperTradingEngine = struct {
    allocator: Allocator,
    data_provider: IDataProvider,  // 真实数据
    simulated_executor: SimulatedExecutor,  // 模拟执行
    account: SimulatedAccount,
    message_bus: *MessageBus,

    pub fn init(allocator: Allocator, config: Config) !PaperTradingEngine {
        return .{
            .allocator = allocator,
            .data_provider = try HyperliquidDataProvider.init(allocator),
            .simulated_executor = SimulatedExecutor.init(allocator),
            .account = SimulatedAccount.init(config.initial_balance),
            .message_bus = MessageBus.init(allocator),
        };
    }

    /// 模拟订单执行
    pub fn executeOrder(self: *PaperTradingEngine, order: Order) !void {
        // 获取当前市场价格
        const quote = self.cache.getQuote(order.symbol) orelse return error.NoQuote;

        // 模拟成交
        const fill_price = if (order.side == .buy) quote.ask else quote.bid;
        const fill = OrderFill{
            .order_id = order.order_id,
            .fill_price = fill_price,
            .fill_quantity = order.quantity,
            .timestamp = Timestamp.now(),
        };

        // 更新模拟账户
        try self.account.applyFill(fill);

        // 发布事件
        self.message_bus.publish("order.filled", .{ .order_filled = fill });
    }
};
```

### CLI 命令
```bash
# Paper Trading 模式
zigquant run-strategy --strategy dual_ma --paper

# 指定初始资金
zigquant run-strategy --strategy dual_ma --paper --balance 10000

# 指定交易对
zigquant run-strategy --strategy dual_ma --paper --symbol BTC-USDT
```

### 详细文档
- [STORY_031_PAPER_TRADING.md](./STORY_031_PAPER_TRADING.md)

---

## Story 032: 策略热重载

### 目标
支持运行时策略参数更新，无需重启即可调整策略行为。

### 核心功能

```zig
pub const HotReloadManager = struct {
    config_path: []const u8,
    last_modified: i64,
    strategy: *IStrategy,

    /// 检查配置文件变化
    pub fn checkForUpdates(self: *HotReloadManager) !bool {
        const stat = try std.fs.cwd().statFile(self.config_path);
        if (stat.mtime > self.last_modified) {
            self.last_modified = stat.mtime;
            return true;
        }
        return false;
    }

    /// 重载策略参数
    pub fn reload(self: *HotReloadManager) !void {
        const config = try loadConfig(self.config_path);
        try self.strategy.updateParams(config.params);

        log.info("Strategy parameters reloaded", .{});
    }
};
```

### 使用场景
- 调整移动平均周期
- 修改止损止盈比例
- 更新仓位大小限制
- 切换交易对

### 详细文档
- [STORY_032_HOT_RELOAD.md](./STORY_032_HOT_RELOAD.md)

---

## 验收标准

### 功能验收

- [ ] 向量化回测引擎实现，速度 > 100,000 bars/s
- [ ] HyperliquidDataProvider 实现 IDataProvider 接口
- [ ] HyperliquidExecutionClient 实现 IExecutionClient 接口
- [ ] Paper Trading 模式完整可用
- [ ] CLI 命令 `zigquant run-strategy --paper` 实现

### 性能验收

| 指标 | 目标 | 状态 |
|------|------|------|
| 向量化回测速度 | > 100,000 bars/s | ⏳ |
| 实盘数据延迟 | < 10ms | ⏳ |
| 订单执行延迟 | < 100ms | ⏳ |
| 内存占用 | < 100MB | ⏳ |

### 代码验收

- [ ] 所有测试通过 (目标: 550+)
- [ ] 零内存泄漏
- [ ] 代码文档完整
- [ ] 示例程序更新

---

## 依赖关系

```
Story 028 (向量化回测)
    ↓
Story 029 (DataProvider) ──→ Story 031 (Paper Trading)
    ↓                              ↓
Story 030 (ExecutionClient)        Story 032 (热重载)
```

---

## 技术要点

### SIMD 向量化 (Story 028)

```zig
// Zig SIMD 向量类型
const Vec4f64 = @Vector(4, f64);

fn computeSMA_SIMD(prices: []const f64, period: usize) []f64 {
    // 使用 SIMD 加速滑动窗口计算
    var i: usize = 0;
    while (i + 4 <= prices.len) : (i += 4) {
        const v: Vec4f64 = prices[i..][0..4].*;
        // 向量化操作
    }
}
```

### VTable 接口适配 (Story 029/030)

```zig
// 将具体实现适配到 VTable 接口
pub fn asDataProvider(self: *HyperliquidDataProvider) IDataProvider {
    return .{
        .ptr = self,
        .vtable = &vtable,
    };
}
```

### 配置文件监控 (Story 032)

```zig
// 使用 inotify (Linux) 或 kqueue (macOS) 监控文件变化
const watcher = try std.fs.Watch.init();
try watcher.addWatch(config_path, .{ .modify = true });
```

---

## 相关文档

- [v0.5.0 事件驱动架构](../v0.5.0/OVERVIEW.md)
- [竞争分析 - Freqtrade 向量化](../../architecture/COMPETITIVE_ANALYSIS.md)
- [IDataProvider 接口定义](../../api/data_provider.md)
- [IExecutionClient 接口定义](../../api/execution_client.md)

---

**版本**: v0.6.0
**状态**: 规划中
**创建时间**: 2025-12-27
