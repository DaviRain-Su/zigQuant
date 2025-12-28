# Grid Trading 实现细节

> 网格交易策略的内部实现说明

**版本**: v0.10.0
**最后更新**: 2025-12-28

---

## 目录

- [架构概览](#架构概览)
- [核心组件](#核心组件)
- [文件结构](#文件结构)
- [执行流程](#执行流程)
- [风险管理集成](#风险管理集成)
- [Paper Trading 模式](#paper-trading-模式)
- [Live Trading 模式](#live-trading-模式)

---

## 架构概览

```
┌─────────────────────────────────────────────────────────────────┐
│                      Grid Trading System                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────┐ │
│  │   CLI Command   │───▶│    GridBot      │───▶│  Exchange   │ │
│  │   (grid.zig)    │    │                 │    │  Connector  │ │
│  └─────────────────┘    └────────┬────────┘    └─────────────┘ │
│                                  │                              │
│                    ┌─────────────┼─────────────┐               │
│                    ▼             ▼             ▼               │
│           ┌────────────┐ ┌────────────┐ ┌────────────┐        │
│           │ GridConfig │ │ RiskEngine │ │AlertManager│        │
│           └────────────┘ └────────────┘ └────────────┘        │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                    GridStrategy                          │   │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐    │   │
│  │  │ Level 0 │  │ Level 1 │  │ Level 2 │  │ Level N │    │   │
│  │  │  90000  │  │  92000  │  │  94000  │  │ 100000  │    │   │
│  │  └─────────┘  └─────────┘  └─────────┘  └─────────┘    │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 核心组件

### 1. GridBot (src/cli/commands/grid.zig)

CLI 网格交易机器人，负责:
- 解析命令行参数
- 加载配置文件
- 管理网格状态
- 协调风险管理
- 执行交易循环

```zig
const GridBot = struct {
    allocator: std.mem.Allocator,
    logger: *Logger,
    config: GridConfig,
    mode: TradingMode,

    // Exchange connection
    connector: ?*HyperliquidConnector = null,

    // Grid state
    grid_levels: []GridLevel,
    buy_orders: std.ArrayList(GridOrderState),
    sell_orders: std.ArrayList(GridOrderState),

    // Position tracking
    current_position: Decimal = Decimal.ZERO,
    total_bought: Decimal = Decimal.ZERO,
    total_sold: Decimal = Decimal.ZERO,
    realized_pnl: Decimal = Decimal.ZERO,
    trades_count: u32 = 0,

    // Risk Management
    risk_engine: ?*RiskEngine = null,
    alert_manager: ?*AlertManager = null,
    account: Account,
    risk_enabled: bool = true,
};
```

### 2. GridStrategy (src/strategy/builtin/grid.zig)

策略逻辑实现，实现 `IStrategy` 接口:

```zig
pub const GridStrategy = struct {
    allocator: std.mem.Allocator,
    config: Config,
    grid_levels: []GridLevel,
    // ...

    pub fn init(allocator: std.mem.Allocator, config: Config) !*GridStrategy;
    pub fn deinit(self: *GridStrategy) void;
    pub fn asStrategy(self: *GridStrategy) IStrategy;
    // IStrategy 接口方法...
};
```

### 3. GridConfig

配置结构:

```zig
pub const Config = struct {
    pair: TradingPair,
    upper_price: Decimal,
    lower_price: Decimal,
    grid_count: u32 = 10,
    order_size: Decimal = Decimal.fromFloat(0.001),
    take_profit_pct: f64 = 0.5,
    enable_long: bool = true,
    enable_short: bool = false,
    max_position: Decimal = Decimal.fromFloat(1.0),

    pub fn validate(self: Config) !void;
    pub fn gridInterval(self: Config) Decimal;
    pub fn priceAtLevel(self: Config, level: u32) Decimal;
};
```

---

## 文件结构

```
src/
├── cli/
│   └── commands/
│       └── grid.zig              # CLI 命令实现
├── strategy/
│   ├── builtin/
│   │   └── grid.zig              # GridStrategy 实现
│   └── factory.zig               # 策略工厂 (包含 grid)
├── core/
│   └── config.zig                # ConfigLoader
├── risk/
│   ├── risk_engine.zig           # RiskEngine
│   └── alert.zig                 # AlertManager
└── root.zig                      # 导出 GridStrategy

examples/
├── strategies/
│   ├── grid_btc.json             # BTC 网格配置示例
│   └── grid_eth.json             # ETH 网格配置示例
└── 26_grid_trading.zig           # 代码示例

docs/features/grid-trading/
├── README.md
├── api.md
├── implementation.md
├── testing.md
├── bugs.md
└── changelog.md
```

---

## 执行流程

### 1. 初始化流程

```
cmdGrid() 入口
    │
    ▼
解析 CLI 参数
    │
    ▼
加载配置文件 (如果指定)
    │
    ├── ConfigLoader.load()
    └── 提取 exchange 凭证
    │
    ▼
创建 GridConfig
    │
    ├── 验证配置
    └── 计算网格层级
    │
    ▼
创建 GridBot
    │
    ├── 初始化网格层级
    ├── 初始化订单列表
    └── 初始化 Account
    │
    ▼
初始化风险管理 (如果启用)
    │
    ├── 创建 RiskEngine
    ├── 创建 AlertManager
    └── 添加 ConsoleChannel
    │
    ▼
连接交易所 (如果非 paper 模式)
    │
    ├── 创建 HyperliquidConnector
    └── 验证凭证
    │
    ▼
放置初始订单
    │
    ▼
进入主循环
```

### 2. 主循环流程

```
while (running) {
    │
    ▼
获取当前价格
    │
    ├── Paper: 使用模拟价格
    └── Live: 从交易所获取
    │
    ▼
检查订单状态
    │
    ├── Paper: simulateFills()
    └── Live: checkRealFills()
    │
    ▼
处理买单成交
    │
    ├── 更新仓位
    ├── 计算 PnL
    ├── 放置对应卖单
    └── 发送告警
    │
    ▼
处理卖单成交
    │
    ├── 更新仓位
    ├── 计算利润
    ├── 重新放置买单
    └── 发送告警
    │
    ▼
打印状态 (每 10 次迭代)
    │
    ▼
等待下一个 tick
}
```

### 3. 订单放置流程

```
placeBuyOrder(level)
    │
    ▼
构建 OrderRequest
    │
    ▼
风险检查
    │
    ├── checkRisk(order_request)
    │   ├── 通过 → 继续
    │   └── 拒绝 → 记录并返回
    │
    ▼
提交订单
    │
    ├── Paper: 添加到本地订单列表
    └── Live: exchange.createOrder()
    │
    ▼
记录订单状态
    │
    ▼
发送交易告警
```

---

## 风险管理集成

### RiskEngine 初始化

```zig
pub fn initRiskManagement(self: *GridBot, max_position_size: Decimal, risk_limit: f64) !void {
    // 设置账户初始值
    self.account.cross_margin_summary.account_value = Decimal.fromFloat(10000);

    // 创建风控配置
    const risk_config = RiskEngineConfig{
        .max_position_size = max_position_size,
        .max_position_per_symbol = max_position_size,
        .max_leverage = Decimal.fromFloat(3.0),
        .max_daily_loss = max_position_size.mul(Decimal.fromFloat(risk_limit)),
        .max_daily_loss_pct = risk_limit,
        .max_orders_per_minute = 60,
        .kill_switch_threshold = max_position_size.mul(Decimal.fromFloat(risk_limit * 2)),
        .close_positions_on_kill_switch = true,
    };

    // 创建风险引擎
    const risk_engine = try self.allocator.create(RiskEngine);
    risk_engine.* = RiskEngine.init(self.allocator, risk_config, null, &self.account);
    self.risk_engine = risk_engine;

    // 创建告警管理器
    const alert_manager = try self.allocator.create(AlertManager);
    alert_manager.* = AlertManager.init(self.allocator, AlertConfig.default());
    self.alert_manager = alert_manager;

    // 添加控制台告警通道
    var console = try self.allocator.create(ConsoleChannel);
    console.* = ConsoleChannel.init(.{
        .colorize = true,
        .show_details = true,
        .show_timestamp = true,
    });
    try alert_manager.addChannel(console.asChannel());
}
```

### 订单风险检查

```zig
fn checkRisk(self: *GridBot, order_request: OrderRequest) bool {
    if (!self.risk_enabled) return true;

    if (self.risk_engine) |re| {
        const result = re.checkOrder(order_request);
        if (!result.passed) {
            self.orders_rejected_by_risk += 1;
            self.logger.warn("[RISK] Order rejected: {s}", .{
                result.message orelse "Unknown reason"
            }) catch {};

            // 发送风险告警
            if (self.alert_manager) |am| {
                am.riskAlert(.risk_position_exceeded, .{
                    .symbol = order_request.pair.base,
                    .quantity = order_request.amount,
                    .price = order_request.price,
                }) catch {};
            }
            return false;
        }
    }
    return true;
}
```

### 风险检查项

1. **Kill Switch 检查**: 如果已激活，拒绝所有订单
2. **仓位大小检查**: 单笔订单 + 现有仓位不超过限制
3. **杠杆检查**: 总敞口不超过最大杠杆
4. **日损失检查**: 当日亏损不超过限制
5. **订单频率检查**: 每分钟订单数不超过限制
6. **保证金检查**: 可用保证金充足

---

## Paper Trading 模式

### 模拟价格生成

Paper 模式下，价格在网格中点初始化:

```zig
pub fn getCurrentPrice(self: *GridBot) !Decimal {
    if (self.connector) |conn| {
        // Live: 从交易所获取
        const exchange = conn.interface();
        const ticker = try exchange.getTicker(self.config.pair);
        const mid_price = ticker.bid.add(ticker.ask).div(Decimal.fromInt(2)) catch ticker.last;
        self.last_price = mid_price;
        return mid_price;
    } else {
        // Paper: 模拟价格
        if (self.last_price.isZero()) {
            const mid = self.config.lower_price.add(self.config.upper_price)
                .div(Decimal.fromInt(2)) catch self.config.lower_price;
            self.last_price = mid;
        }
        return self.last_price;
    }
}
```

### 模拟成交逻辑

```zig
fn simulateFills(self: *GridBot, current_price: Decimal) !void {
    // 检查买单
    var i: usize = 0;
    while (i < self.buy_orders.items.len) {
        const order = &self.buy_orders.items[i];
        if (order.status == .pending and current_price.cmp(order.price) != .gt) {
            // 买单成交!
            order.status = .filled;
            order.filled_qty = self.config.order_size;

            self.current_position = self.current_position.add(self.config.order_size);
            self.total_bought = self.total_bought.add(self.config.order_size);
            self.trades_count += 1;

            // 放置对应卖单
            const sell_price = order.price.mul(
                Decimal.fromFloat(1.0 + self.config.take_profit_pct / 100.0)
            );
            try self.sell_orders.append(self.allocator, .{
                .level = order.level,
                .price = sell_price,
                .side = .sell,
                .status = .pending,
            });

            _ = self.buy_orders.orderedRemove(i);
            continue;
        }
        i += 1;
    }

    // 检查卖单 (类似逻辑)
    // ...
}
```

---

## Live Trading 模式

### 交易所连接

```zig
pub fn connect(self: *GridBot, wallet: []const u8, private_key: []const u8, testnet: bool) !void {
    const exchange_config = ExchangeConfig{
        .name = "hyperliquid",
        .api_key = wallet,
        .api_secret = private_key,
        .testnet = testnet,
    };

    self.connector = try HyperliquidConnector.create(
        self.allocator,
        exchange_config,
        self.logger.*,
    );

    try self.logger.info("Connected to Hyperliquid {s}", .{
        if (testnet) "Testnet" else "Mainnet",
    });
}
```

### 订单提交

```zig
fn placeBuyOrder(self: *GridBot, level: *GridLevel) !void {
    if (self.connector) |conn| {
        const exchange = conn.interface();

        const order_request = OrderRequest{
            .pair = self.config.pair,
            .side = .buy,
            .order_type = .limit,
            .amount = self.config.order_size,
            .price = level.price,
            .time_in_force = .gtc,
            .reduce_only = false,
        };

        // 风险检查
        if (!self.checkRisk(order_request)) {
            try self.logger.warn("[BUY ORDER] Rejected by risk check @ {d:.2}", .{
                level.price.toFloat()
            });
            return;
        }

        // 提交订单
        const order = try exchange.createOrder(order_request);

        try self.buy_orders.append(self.allocator, .{
            .level = level.level,
            .price = level.price,
            .side = .buy,
            .status = .active,
            .exchange_order_id = order.exchange_order_id,
        });

        // 发送告警
        self.sendTradeAlert(.trade_executed, self.config.pair.base, level.price, self.config.order_size, null);
    }
}
```

---

## 配置加载流程

### ConfigLoader 使用

```zig
// 在 cmdGrid 中加载配置
const config_path = res.args.config;
if (config_path) |path| {
    try logger.info("Loading config from: {s}", .{path});
    if (ConfigLoader.load(allocator, path, AppConfig)) |parsed| {
        app_config = parsed;
        try logger.info("Config loaded successfully", .{});
    } else |err| {
        try logger.warn("Failed to load config file: {s} - using defaults", .{@errorName(err)});
    }
}
```

### 凭证优先级

```zig
// 优先级: CLI 参数 > 配置文件 > 环境变量
var wallet: ?[]const u8 = res.args.wallet;
var private_key: ?[]const u8 = res.args.key;

// 从配置文件加载
if (app_config) |cfg| {
    if (cfg.value.getExchange("hyperliquid")) |exchange_cfg| {
        if (wallet == null and exchange_cfg.api_key.len > 0) {
            wallet = exchange_cfg.api_key;
        }
        if (private_key == null and exchange_cfg.api_secret.len > 0) {
            private_key = exchange_cfg.api_secret;
        }
    }
}

// 从环境变量加载
if (wallet == null) {
    wallet = std.posix.getenv("ZIGQUANT_WALLET");
}
if (private_key == null) {
    private_key = std.posix.getenv("ZIGQUANT_PRIVATE_KEY");
}
```

---

## 性能考虑

### 内存管理

- 使用 `ArrayList` 管理动态订单列表
- 订单成交后立即移除，避免内存泄漏
- 使用 `errdefer` 确保初始化失败时释放资源

### 并发安全

- 当前实现为单线程
- RiskEngine 内部使用原子操作保护 Kill Switch 状态
- AlertManager 使用 Mutex 保护并发访问

### 延迟优化

- 风险检查 < 1ms
- 订单提交延迟取决于网络 (testnet ~100ms)
- Paper 模式无网络延迟

---

*Last updated: 2025-12-28*
