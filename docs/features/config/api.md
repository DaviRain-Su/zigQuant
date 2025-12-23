# Config - API 参考

> 完整的 API 文档和使用示例

**最后更新**: 2025-01-22

---

## ConfigLoader

配置加载器

### `loadFromJSON(allocator, json_str, T) !std.json.Parsed(T)`

从 JSON 字符串加载配置

**返回**: `std.json.Parsed(T)` - 必须调用 `.deinit()` 释放内存

```zig
const json =
    \\{
    \\  "server": {"host": "localhost", "port": 8080},
    \\  "exchanges": []
    \\}
;
var parsed = try ConfigLoader.loadFromJSON(allocator, json, AppConfig);
defer parsed.deinit();
const cfg = parsed.value;
```

### `applyEnvOverrides(config, prefix, allocator) !void`

应用环境变量覆盖

```zig
var cfg = AppConfig{ ... };
try ConfigLoader.applyEnvOverrides(&cfg, "ZIGQUANT", allocator);
```

---

## AppConfig

应用程序配置

```zig
pub const AppConfig = struct {
    server: ServerConfig,
    exchanges: []ExchangeConfig,  // 多交易所配置
    trading: TradingConfig,
    logging: LoggingConfig,

    pub fn validate(self: AppConfig) !void;
    pub fn sanitize(self: AppConfig, allocator: Allocator) !AppConfig;

    /// 通过名称查找交易所配置
    pub fn getExchange(self: AppConfig, name: []const u8) ?ExchangeConfig;

    // 注意：内存由 Parsed(AppConfig) 管理，无 deinit 方法
};
```

### `getExchange(name: []const u8) ?ExchangeConfig`

通过交易所名称查找配置

```zig
const json_str = try std.fs.cwd().readFileAlloc(allocator, "config.json", 1024 * 1024);
defer allocator.free(json_str);

var parsed = try ConfigLoader.loadFromJSON(allocator, json_str, AppConfig);
defer parsed.deinit();
const cfg = parsed.value;

if (cfg.getExchange("binance")) |binance| {
    std.debug.print("Binance: {s}\n", .{binance.name});
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
    api_key: []const u8,
    api_secret: []const u8,
    testnet: bool = false,

    pub fn sanitize(self: ExchangeConfig) ExchangeConfig;
};
```

### `sanitize() ExchangeConfig`

隐藏敏感信息

```zig
const cfg = ExchangeConfig{
    .name = "binance",
    .api_key = "real-key",
    .api_secret = "real-secret",
    .testnet = false,
};

std.debug.print("{}\n", .{cfg.sanitize()});
// 输出: { .name = "binance", .api_key = "***REDACTED***", ... }
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

*Last updated: 2025-01-22*
