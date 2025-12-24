# Config - API 参考

> 完整的 API 文档和使用示例

**最后更新**: 2025-12-24

---

## ConfigLoader

配置加载器

### `load(allocator, path, T) !T`

从文件加载配置（根据文件扩展名自动识别格式）

**参数**:
- `allocator: Allocator` - 内存分配器
- `path: []const u8` - 配置文件路径
- `T: type` - 配置类型（编译时参数）

**返回**: `T` - 配置对象

**错误**:
- `error.UnsupportedFormat` - TOML 格式未实现
- `error.UnknownFormat` - 未知文件扩展名
- 文件读取和解析相关错误

**注意**: 此方法当前仅支持 JSON 格式，TOML 会返回 `error.UnsupportedFormat`

```zig
// ❌ TOML 当前不支持
const cfg = try ConfigLoader.load(allocator, "config.toml", AppConfig);
// 返回 error.UnsupportedFormat

// ✅ JSON 支持
const cfg = try ConfigLoader.load(allocator, "config.json", AppConfig);
```

### `loadFromJSON(allocator, json_str, T) !std.json.Parsed(T)`

从 JSON 字符串加载配置

**参数**:
- `allocator: Allocator` - 内存分配器
- `json_str: []const u8` - JSON 字符串
- `T: type` - 配置类型（编译时参数）

**返回**: `std.json.Parsed(T)` - 必须调用 `.deinit()` 释放内存

**功能**:
1. 解析 JSON 字符串
2. 自动应用环境变量覆盖（ZIGQUANT_* 前缀）
3. 自动验证配置（如果 T 有 validate 方法）

```zig
const json =
    \\{
    \\  "server": {"host": "localhost", "port": 8080},
    \\  "exchanges": [
    \\    {"name": "binance", "api_key": "key", "api_secret": "secret"}
    \\  ],
    \\  "trading": {"max_position_size": 10000.0, "leverage": 1, "risk_limit": 0.02},
    \\  "logging": {"level": "info"}
    \\}
;
var parsed = try ConfigLoader.loadFromJSON(allocator, json, AppConfig);
defer parsed.deinit();
const cfg = parsed.value;
```

### `applyEnvOverrides(config, prefix, allocator) !void`

应用环境变量覆盖

**参数**:
- `config: anytype` - 配置对象指针
- `prefix: []const u8` - 环境变量前缀（通常为 "ZIGQUANT"）
- `allocator: Allocator` - 内存分配器

**功能**:
- 递归处理嵌套结构
- 支持基本类型（int, float, bool, string）
- 支持可选类型（?T）
- 支持数组/切片（按索引和名称）

```zig
var cfg = AppConfig{ ... };
try ConfigLoader.applyEnvOverrides(&cfg, "ZIGQUANT", allocator);
```

---

## AppConfig

应用程序配置

```zig
pub const AppConfig = struct {
    server: ServerConfig = .{},
    exchanges: []ExchangeConfig = &[_]ExchangeConfig{},
    trading: TradingConfig = .{},
    logging: LoggingConfig = .{},

    pub fn validate(self: AppConfig) ConfigError!void;
    pub fn sanitize(self: AppConfig, allocator: Allocator) !AppConfig;

    /// 通过名称查找交易所配置
    pub fn getExchange(self: AppConfig, name: []const u8) ?ExchangeConfig;

    // 注意：内存由 Parsed(AppConfig) 管理，无 deinit 方法
};
```

### 默认值

- `server`: `ServerConfig{ .host = "localhost", .port = 8080 }`
- `exchanges`: 空数组 `&[_]ExchangeConfig{}`
- `trading`: `TradingConfig{ .max_position_size = 10000.0, .leverage = 1, .risk_limit = 0.02 }`
- `logging`: `LoggingConfig{ .level = "info", .file = null, .max_size = 10_000_000 }`

### `validate() ConfigError!void`

验证配置有效性

**验证规则**:
1. 服务器端口不能为 0
2. 至少配置一个交易所
3. 交易所名称不能为空且不能重复
4. 交易所 API 凭证不能为空
5. 杠杆范围: 1-100
6. 最大仓位必须 > 0
7. 风险限制范围: 0-1.0
8. 日志级别必须有效（trace, debug, info, warn, error, fatal）

**错误类型**: 见 `ConfigError` 枚举

```zig
var parsed = try ConfigLoader.loadFromJSON(allocator, json_str, AppConfig);
defer parsed.deinit();
// loadFromJSON 已自动调用 validate()

// 手动验证
try parsed.value.validate();
```

### `sanitize(allocator: Allocator) !AppConfig`

隐藏敏感信息用于日志输出

**参数**:
- `allocator: Allocator` - 用于分配新的 exchanges 数组

**返回**: 新的 AppConfig，其中所有交易所的 API 凭证被替换为 "***REDACTED***"

**注意**: 需要手动释放返回对象的 exchanges 字段

```zig
const sanitized = try cfg.sanitize(allocator);
defer allocator.free(sanitized.exchanges);
std.log.info("Config: {}", .{sanitized});
```

### `getExchange(name: []const u8) ?ExchangeConfig`

通过交易所名称查找配置

**参数**:
- `name: []const u8` - 交易所名称

**返回**: `?ExchangeConfig` - 找到返回配置，否则返回 null

```zig
const json_str = try std.fs.cwd().readFileAlloc(allocator, "config.json", 1024 * 1024);
defer allocator.free(json_str);

var parsed = try ConfigLoader.loadFromJSON(allocator, json_str, AppConfig);
defer parsed.deinit();
const cfg = parsed.value;

if (cfg.getExchange("binance")) |binance| {
    std.debug.print("Binance: {s}\n", .{binance.name});
} else {
    std.debug.print("Binance not configured\n", .{});
}

if (cfg.getExchange("okx")) |okx| {
    std.debug.print("OKX: {s}\n", .{okx.name});
}
```

### 示例

```zig
const json_str = try std.fs.cwd().readFileAlloc(allocator, "config.json", 1024 * 1024);
defer allocator.free(json_str);

var parsed = try ConfigLoader.loadFromJSON(allocator, json_str, AppConfig);
defer parsed.deinit();
const cfg = parsed.value;

// 配置已自动验证（loadFromJSON 内部调用 validate）

// 遍历所有交易所
for (cfg.exchanges) |exchange| {
    const sanitized = exchange.sanitize();
    std.debug.print("Exchange: {}\n", .{sanitized});
}

// 查找特定交易所
const binance = cfg.getExchange("binance") orelse return error.ExchangeNotFound;
std.debug.print("Using Binance\n", .{});
```

---

## ExchangeConfig

交易所配置

```zig
pub const ExchangeConfig = struct {
    name: []const u8,
    api_key: []const u8 = "",
    api_secret: []const u8 = "",
    testnet: bool = false,

    pub fn sanitize(self: ExchangeConfig) ExchangeConfig;
};
```

### 字段说明

- `name`: 交易所名称（必填，用于查找）
- `api_key`: API 密钥（默认为空字符串，验证时要求非空）
- `api_secret`: API 密钥（默认为空字符串，验证时要求非空）
- `testnet`: 是否使用测试网（默认 false）

### `sanitize() ExchangeConfig`

隐藏敏感信息

**返回**: 新的 ExchangeConfig，api_key 和 api_secret 被替换为 "***REDACTED***"（仅当原值非空时）

**注意**: 不需要 allocator，返回值可直接使用

```zig
const cfg = ExchangeConfig{
    .name = "binance",
    .api_key = "real-key",
    .api_secret = "real-secret",
    .testnet = false,
};

const sanitized = cfg.sanitize();
std.debug.print("{}\n", .{sanitized});
// 输出: ExchangeConfig{ .name = "binance", .api_key = "***REDACTED***", .api_secret = "***REDACTED***", .testnet = false }
```

---

## ConfigError

配置验证错误

```zig
pub const ConfigError = error{
    InvalidPort,              // 端口为 0
    NoExchangeConfigured,     // 没有配置交易所
    DuplicateExchangeName,    // 交易所名称重复
    EmptyExchangeName,        // 交易所名称为空
    EmptyAPIKey,              // API 密钥为空
    EmptyAPISecret,           // API 密钥为空
    InvalidLeverage,          // 杠杆不在 1-100 范围
    InvalidPositionSize,      // 最大仓位 <= 0
    InvalidLogLevel,          // 无效的日志级别
    InvalidRiskLimit,         // 风险限制不在 0-1.0 范围
};
```

---

## 完整示例

### 示例 1: 多环境配置

```zig
pub fn loadConfig(allocator: Allocator) !std.json.Parsed(AppConfig) {
    const env = std.posix.getenv("ENV") orelse "dev";

    const config_file = if (std.mem.eql(u8, env, "prod"))
        "config.prod.json"
    else if (std.mem.eql(u8, env, "test"))
        "config.test.json"
    else
        "config.dev.json";

    const json_str = try std.fs.cwd().readFileAlloc(allocator, config_file, 1024 * 1024);
    defer allocator.free(json_str);

    var parsed = try ConfigLoader.loadFromJSON(allocator, json_str, AppConfig);
    // 配置已自动验证

    // 打印所有配置的交易所
    std.log.info("Loaded {} exchanges", .{parsed.value.exchanges.len});
    for (parsed.value.exchanges) |exchange| {
        std.log.info("  - {s} (testnet: {})", .{exchange.name, exchange.testnet});
    }

    return parsed;  // 调用者负责 deinit
}
```

### 示例 2: 配置验证

```zig
const json_str = try std.fs.cwd().readFileAlloc(allocator, "config.json", 1024 * 1024);
defer allocator.free(json_str);

// loadFromJSON 自动验证配置，如果无效会返回错误
var parsed = ConfigLoader.loadFromJSON(allocator, json_str, AppConfig) catch |err| {
    std.log.err("Invalid config: {}", .{err});
    return err;
};
defer parsed.deinit();

std.log.info("Config loaded successfully", .{});
std.log.info("Configured exchanges: {}", .{parsed.value.exchanges.len});
```

### 示例 3: 跨交易所套利

```zig
pub fn setupArbitrageSystem(allocator: Allocator) !void {
    const json_str = try std.fs.cwd().readFileAlloc(allocator, "config.json", 1024 * 1024);
    defer allocator.free(json_str);

    var parsed = try ConfigLoader.loadFromJSON(allocator, json_str, AppConfig);
    defer parsed.deinit();
    const cfg = parsed.value;

    // 获取两个交易所用于套利
    const binance = cfg.getExchange("binance") orelse return error.BinanceNotConfigured;
    const okx = cfg.getExchange("okx") orelse return error.OKXNotConfigured;

    // 初始化交易所客户端
    var binance_client = try ExchangeClient.init(allocator, binance);
    defer binance_client.deinit();

    var okx_client = try ExchangeClient.init(allocator, okx);
    defer okx_client.deinit();

    // 监控两个交易所的价格差异
    while (true) {
        const binance_price = try binance_client.getPrice("BTC/USDT");
        const okx_price = try okx_client.getPrice("BTC/USDT");

        const price_diff = @abs(binance_price - okx_price);
        if (price_diff > 10.0) {  // 价差超过 $10
            std.log.info("Arbitrage opportunity: Binance ${d:.2}, OKX ${d:.2}", .{
                binance_price, okx_price
            });
            try executeArbitrage(binance_client, okx_client, price_diff);
        }

        std.time.sleep(1 * std.time.ns_per_s);
    }
}
```

---

## 其他配置类型

### ServerConfig

```zig
pub const ServerConfig = struct {
    host: []const u8 = "localhost",
    port: u16 = 8080,
};
```

### TradingConfig

```zig
pub const TradingConfig = struct {
    max_position_size: f64 = 10000.0,
    leverage: u8 = 1,
    risk_limit: f64 = 0.02,  // 2% 默认风险限制
};
```

### LoggingConfig

```zig
pub const LoggingConfig = struct {
    level: []const u8 = "info",
    file: ?[]const u8 = null,
    max_size: usize = 10_000_000,  // 10MB 默认
};
```

---

*Last updated: 2025-12-24*
