# Grid Trading API 参考

> 网格交易策略完整 API 文档

**版本**: v0.10.0
**最后更新**: 2025-12-28

---

## 目录

- [GridStrategy](#gridstrategy)
- [GridStrategyConfig](#gridstrategyconfig)
- [GridLevel](#gridlevel)
- [CLI 命令](#cli-命令)
- [配置文件格式](#配置文件格式)

---

## GridStrategy

网格交易策略实现，实现 `IStrategy` 接口。

### 结构定义

```zig
pub const GridStrategy = struct {
    allocator: std.mem.Allocator,
    config: Config,
    grid_levels: []GridLevel,
    active_buy_orders: std.ArrayList(GridOrder),
    active_sell_orders: std.ArrayList(GridOrder),
    current_position: Decimal,
    realized_pnl: Decimal,
    trades_count: u32,
    
    // ... 内部字段
};
```

### 构造函数

#### `init`

创建新的网格策略实例。

```zig
pub fn init(allocator: std.mem.Allocator, config: Config) !*GridStrategy
```

**参数**:
- `allocator`: 内存分配器
- `config`: 网格配置

**返回**: 策略实例指针

**错误**:
- `error.OutOfMemory`: 内存分配失败
- `error.InvalidConfig`: 配置验证失败

**示例**:
```zig
const config = GridStrategyConfig{
    .pair = .{ .base = "BTC", .quote = "USDC" },
    .upper_price = Decimal.fromFloat(100000),
    .lower_price = Decimal.fromFloat(90000),
    .grid_count = 10,
    .order_size = Decimal.fromFloat(0.001),
};

var strategy = try GridStrategy.init(allocator, config);
defer strategy.deinit();
```

#### `deinit`

释放策略资源。

```zig
pub fn deinit(self: *GridStrategy) void
```

### 方法

#### `asStrategy`

获取 `IStrategy` 接口。

```zig
pub fn asStrategy(self: *GridStrategy) IStrategy
```

**返回**: 实现 `IStrategy` 接口的对象

#### `onCandle`

处理新的 K 线数据。

```zig
pub fn onCandle(self: *GridStrategy, candle: Candle) ?Signal
```

**参数**:
- `candle`: K 线数据

**返回**: 交易信号或 `null`

#### `getPosition`

获取当前仓位。

```zig
pub fn getPosition(self: *GridStrategy) Decimal
```

**返回**: 当前持仓数量

#### `getPnL`

获取已实现盈亏。

```zig
pub fn getPnL(self: *GridStrategy) Decimal
```

**返回**: 已实现盈亏金额

#### `getTradesCount`

获取交易次数。

```zig
pub fn getTradesCount(self: *GridStrategy) u32
```

**返回**: 总交易次数

---

## GridStrategyConfig

网格策略配置结构。

### 结构定义

```zig
pub const Config = struct {
    /// 交易对
    pair: TradingPair,

    /// 价格上界
    upper_price: Decimal,

    /// 价格下界
    lower_price: Decimal,

    /// 网格数量
    grid_count: u32 = 10,

    /// 每格订单大小
    order_size: Decimal = Decimal.fromFloat(0.001),

    /// 止盈百分比 (0.5 = 0.5%)
    take_profit_pct: f64 = 0.5,

    /// 是否启用做多
    enable_long: bool = true,

    /// 是否启用做空
    enable_short: bool = false,

    /// 最大总仓位
    max_position: Decimal = Decimal.fromFloat(1.0),
};
```

### 字段说明

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `pair` | `TradingPair` | 必需 | 交易对，如 BTC-USDC |
| `upper_price` | `Decimal` | 必需 | 网格价格上界 |
| `lower_price` | `Decimal` | 必需 | 网格价格下界 |
| `grid_count` | `u32` | 10 | 网格层数 |
| `order_size` | `Decimal` | 0.001 | 每层订单数量 |
| `take_profit_pct` | `f64` | 0.5 | 止盈百分比 |
| `enable_long` | `bool` | true | 启用做多 |
| `enable_short` | `bool` | false | 启用做空 |
| `max_position` | `Decimal` | 1.0 | 最大持仓 |

### 方法

#### `validate`

验证配置有效性。

```zig
pub fn validate(self: Config) !void
```

**错误**:
- `error.InvalidPriceRange`: 价格范围无效 (upper <= lower)
- `error.InvalidGridCount`: 网格数量无效 (< 2)
- `error.InvalidOrderSize`: 订单大小无效 (<= 0)

#### `gridInterval`

计算网格间距。

```zig
pub fn gridInterval(self: Config) Decimal
```

**返回**: 每层网格的价格间距

**计算公式**:
```
interval = (upper_price - lower_price) / grid_count
```

#### `priceAtLevel`

获取指定层的价格。

```zig
pub fn priceAtLevel(self: Config, level: u32) Decimal
```

**参数**:
- `level`: 网格层级 (0 = 最低)

**返回**: 该层的价格

**计算公式**:
```
price = lower_price + level * gridInterval()
```

---

## GridLevel

网格层级结构。

### 结构定义

```zig
pub const GridLevel = struct {
    /// 层级编号 (0 = 最低)
    level: u32,

    /// 该层价格
    price: Decimal,

    /// 是否有活跃买单
    has_buy_order: bool = false,

    /// 是否有活跃卖单
    has_sell_order: bool = false,
};
```

---

## CLI 命令

### 命令格式

```bash
zigquant grid [OPTIONS]
```

### 必需参数

```bash
-p, --pair <pair>         交易对 (如 BTC-USDC)
    --upper <price>       价格上界
    --lower <price>       价格下界
```

### 网格参数

```bash
-g, --grids <count>       网格数量 (默认: 10)
-s, --size <amount>       每格订单大小 (默认: 0.001)
    --tp <percent>        止盈百分比 (默认: 0.5)
    --max-position <amt>  最大仓位 (默认: 1.0)
```

### 交易模式

```bash
    --paper               Paper Trading 模式 (默认)
    --testnet             Hyperliquid 测试网
    --live                Hyperliquid 主网 (慎用!)
```

### 凭证配置

```bash
    --config <file>       配置文件路径
    --wallet <address>    钱包地址 (0x...)
    --key <privatekey>    私钥
```

### 风险管理

```bash
    --no-risk             禁用风险管理检查
```

### 运行参数

```bash
    --interval <ms>       检查间隔 (默认: 5000ms)
    --duration <minutes>  运行时长 (默认: 0=无限)
-h, --help                显示帮助信息
```

### 示例

```bash
# Paper Trading
zigquant grid -p BTC-USDC --upper 100000 --lower 90000 -g 10

# Testnet 使用配置文件
zigquant grid --config config.test.json \
    -p BTC-USDC --upper 100000 --lower 90000 --testnet

# 自定义参数
zigquant grid -p ETH-USDC --upper 4000 --lower 3500 \
    -g 20 -s 0.1 --tp 0.3 --max-position 5 --testnet
```

---

## 配置文件格式

### JSON 结构

```json
{
  "server": {
    "host": "127.0.0.1",
    "port": 8080
  },
  "exchanges": [
    {
      "name": "hyperliquid",
      "api_key": "0x...",
      "api_secret": "...",
      "testnet": true
    }
  ],
  "trading": {
    "max_position_size": 1000.0,
    "leverage": 1,
    "risk_limit": 0.02
  },
  "logging": {
    "level": "info",
    "file": null,
    "max_size": 10000000
  }
}
```

### 字段说明

#### exchanges

| 字段 | 类型 | 说明 |
|------|------|------|
| `name` | string | 交易所名称，必须为 "hyperliquid" |
| `api_key` | string | 钱包地址 (0x 开头) |
| `api_secret` | string | 私钥 (不带 0x) |
| `testnet` | bool | 是否使用测试网 |

#### trading

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `max_position_size` | float | 10000.0 | 最大仓位价值 (USD) |
| `leverage` | int | 1 | 杠杆倍数 |
| `risk_limit` | float | 0.02 | 日损失限制 (2%) |

### 优先级

凭证加载优先级: CLI 参数 > 配置文件 > 环境变量

**环境变量**:
- `ZIGQUANT_WALLET`: 钱包地址
- `ZIGQUANT_PRIVATE_KEY`: 私钥

---

## 风险管理 API

Grid Trading 集成了 RiskEngine，以下是相关 API:

### RiskEngine 集成

```zig
// GridBot 结构中的风险管理字段
const GridBot = struct {
    // ...
    risk_engine: ?*RiskEngine = null,
    alert_manager: ?*AlertManager = null,
    account: Account,
    risk_enabled: bool = true,
    orders_rejected_by_risk: u32 = 0,
};

// 初始化风险管理
pub fn initRiskManagement(
    self: *GridBot,
    max_position_size: Decimal,
    risk_limit: f64,
) !void;

// 检查订单风险
fn checkRisk(self: *GridBot, order_request: OrderRequest) bool;

// 发送交易告警
fn sendTradeAlert(
    self: *GridBot,
    category: AlertCategory,
    symbol: []const u8,
    price: Decimal,
    quantity: Decimal,
    pnl: ?Decimal,
) void;
```

### RiskEngineConfig

```zig
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
```

---

## 类型定义

### TradingPair

```zig
pub const TradingPair = struct {
    base: []const u8,   // 基础货币 (如 "BTC")
    quote: []const u8,  // 报价货币 (如 "USDC")
};
```

### Decimal

使用 zigQuant 的高精度十进制类型:

```zig
const Decimal = @import("zigQuant").Decimal;

// 创建
const d1 = Decimal.fromFloat(100.5);
const d2 = Decimal.fromInt(100);
const d3 = try Decimal.fromString("100.5");

// 运算
const sum = d1.add(d2);
const diff = d1.sub(d2);
const prod = d1.mul(d2);
const quot = try d1.div(d2);

// 比较
const cmp = d1.cmp(d2);  // .lt, .eq, .gt
const is_zero = d1.isZero();
```

---

## 错误类型

### 配置错误

```zig
pub const ConfigError = error{
    InvalidPriceRange,      // 价格范围无效
    InvalidGridCount,       // 网格数量无效
    InvalidOrderSize,       // 订单大小无效
    InvalidTakeProfit,      // 止盈比例无效
};
```

### CLI 错误

```zig
pub const CLIError = error{
    MissingPair,            // 缺少交易对
    MissingUpper,           // 缺少上界
    MissingLower,           // 缺少下界
    MissingWallet,          // 缺少钱包地址
    MissingPrivateKey,      // 缺少私钥
    InvalidPair,            // 交易对格式无效
};
```

---

*Last updated: 2025-12-28*
