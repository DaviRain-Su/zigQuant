# Config - 实现细节

> 内部实现说明和设计决策

**最后更新**: 2025-01-22

---

## 核心算法

### 1. 配置加载优先级

```zig
pub fn load(allocator: Allocator, path: []const u8, comptime T: type) !T {
    // 1. 加载默认配置
    var cfg = T{};

    // 2. 从文件加载（覆盖默认值）
    const file_content = try std.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024);
    defer allocator.free(file_content);

    cfg = try parseConfig(allocator, file_content, T);

    // 3. 应用环境变量（最高优先级）
    try applyEnvOverrides(&cfg, "ZIGQUANT");

    // 4. 验证配置
    if (@hasDecl(T, "validate")) {
        try cfg.validate();
    }

    return cfg;
}
```

**优先级**: 环境变量 > 文件 > 默认值

---

### 2. 环境变量覆盖

```zig
pub fn applyEnvOverrides(config: anytype, prefix: []const u8) !void {
    const T = @TypeOf(config.*);
    const fields = @typeInfo(T).Struct.fields;

    inline for (fields) |field| {
        const env_key = try std.fmt.allocPrint(
            allocator,
            "{s}_{s}",
            .{ prefix, toUpperCase(field.name) },
        );
        defer allocator.free(env_key);

        if (std.os.getenv(env_key)) |value| {
            @field(config, field.name) = try parseValue(field.type, value);
        }

        // 递归处理嵌套结构
        if (@typeInfo(field.type) == .Struct) {
            const nested_prefix = try std.fmt.allocPrint(
                allocator,
                "{s}_{s}",
                .{ prefix, toUpperCase(field.name) },
            );
            defer allocator.free(nested_prefix);

            try applyEnvOverrides(&@field(config, field.name), nested_prefix);
        }

        // 处理数组/切片（如 exchanges）
        if (@typeInfo(field.type) == .Pointer and
            @typeInfo(field.type).Pointer.size == .Slice)
        {
            const slice = @field(config, field.name);
            for (slice, 0..) |*item, i| {
                // 支持按索引覆盖: ZIGQUANT_EXCHANGES_0_API_KEY
                const indexed_prefix = try std.fmt.allocPrint(
                    allocator,
                    "{s}_{s}_{}",
                    .{ prefix, toUpperCase(field.name), i },
                );
                defer allocator.free(indexed_prefix);

                try applyEnvOverrides(item, indexed_prefix);

                // 支持按名称覆盖: ZIGQUANT_EXCHANGES_BINANCE_API_KEY
                if (@hasField(@TypeOf(item.*), "name")) {
                    const name = @field(item, "name");
                    const named_prefix = try std.fmt.allocPrint(
                        allocator,
                        "{s}_{s}_{s}",
                        .{ prefix, toUpperCase(field.name), toUpperCase(name) },
                    );
                    defer allocator.free(named_prefix);

                    try applyEnvOverrides(item, named_prefix);
                }
            }
        }
    }
}
```

**示例**:
```bash
# 基本配置
ZIGQUANT_SERVER_PORT=9090

# 按索引覆盖交易所配置
ZIGQUANT_EXCHANGES_0_API_KEY="binance-key"
ZIGQUANT_EXCHANGES_1_API_KEY="okx-key"

# 按名称覆盖交易所配置（推荐）
ZIGQUANT_EXCHANGES_BINANCE_API_KEY="binance-key"
ZIGQUANT_EXCHANGES_BINANCE_API_SECRET="binance-secret"
ZIGQUANT_EXCHANGES_OKX_API_KEY="okx-key"
ZIGQUANT_EXCHANGES_OKX_API_SECRET="okx-secret"
```

转换为:
```zig
config.server.port = 9090;
config.exchanges[0].api_key = "binance-key";  // 按索引
config.exchanges[1].api_key = "okx-key";

// 或按名称（更安全）
for (config.exchanges) |*exchange| {
    if (std.mem.eql(u8, exchange.name, "binance")) {
        exchange.api_key = "binance-key";
        exchange.api_secret = "binance-secret";
    }
}
```

---

### 3. 敏感信息隐藏

```zig
pub fn sanitize(self: ExchangeConfig) ExchangeConfig {
    return .{
        .name = self.name,
        .api_key = "***REDACTED***",
        .api_secret = "***REDACTED***",
        .testnet = self.testnet,
    };
}
```

**设计决策**:
- 返回新实例，不修改原配置
- 只隐藏敏感字段
- 用于日志和调试输出

---

### 4. 多交易所查找

```zig
pub fn getExchange(self: AppConfig, name: []const u8) ?ExchangeConfig {
    for (self.exchanges) |exchange| {
        if (std.mem.eql(u8, exchange.name, name)) {
            return exchange;
        }
    }
    return null;
}
```

**算法说明**:
- 线性搜索交易所列表
- 按名称精确匹配
- 时间复杂度: O(n)，n 为交易所数量
- 对于小规模配置（<10 个交易所）性能足够

**优化方案**（可选）:
```zig
// 使用 HashMap 加速查找（如果交易所很多）
pub const AppConfig = struct {
    exchanges: []ExchangeConfig,
    exchange_map: std.StringHashMap(ExchangeConfig),  // 缓存

    pub fn init(allocator: Allocator, exchanges: []ExchangeConfig) !AppConfig {
        var map = std.StringHashMap(ExchangeConfig).init(allocator);
        for (exchanges) |exchange| {
            try map.put(exchange.name, exchange);
        }
        return .{
            .exchanges = exchanges,
            .exchange_map = map,
        };
    }

    pub fn getExchange(self: AppConfig, name: []const u8) ?ExchangeConfig {
        return self.exchange_map.get(name);  // O(1) 查找
    }
};
```

---

## JSON 解析

```zig
fn parseConfig(allocator: Allocator, content: []const u8, comptime T: type) !T {
    const parsed = try std.json.parseFromSlice(T, allocator, content, .{});
    defer parsed.deinit();

    return parsed.value;
}
```

---

## TOML 解析

```zig
fn parseConfigTOML(allocator: Allocator, content: []const u8, comptime T: type) !T {
    // 使用第三方 TOML 库
    const toml = @import("toml");
    return try toml.parse(T, allocator, content);
}
```

---

## 配置验证

```zig
pub fn validate(self: AppConfig) !void {
    // 服务器配置验证
    if (self.server.port == 0) {
        return error.InvalidPort;
    }

    // 交易所配置验证
    if (self.exchanges.len == 0) {
        return error.NoExchangeConfigured;
    }

    // 验证交易所名称唯一性
    for (self.exchanges, 0..) |exchange1, i| {
        for (self.exchanges[i+1..]) |exchange2| {
            if (std.mem.eql(u8, exchange1.name, exchange2.name)) {
                return error.DuplicateExchangeName;
            }
        }

        // 验证每个交易所的配置
        if (exchange1.name.len == 0) {
            return error.EmptyExchangeName;
        }
        if (exchange1.api_key.len == 0) {
            return error.EmptyAPIKey;
        }
        if (exchange1.api_secret.len == 0) {
            return error.EmptyAPISecret;
        }
    }

    // 交易配置验证
    if (self.trading.leverage < 1 or self.trading.leverage > 100) {
        return error.InvalidLeverage;
    }

    if (self.trading.max_position_size <= 0) {
        return error.InvalidPositionSize;
    }

    // 日志配置验证
    const valid_levels = [_][]const u8{ "trace", "debug", "info", "warn", "error", "fatal" };
    var valid = false;
    for (valid_levels) |level| {
        if (std.mem.eql(u8, self.logging.level, level)) {
            valid = true;
            break;
        }
    }
    if (!valid) {
        return error.InvalidLogLevel;
    }
}
```

---

## 性能优化

### 1. 编译时类型检查

```zig
comptime {
    if (@typeInfo(T) != .Struct) {
        @compileError("Config type must be a struct");
    }
}
```

### 2. 缓存环境变量

```zig
var env_cache = std.StringHashMap([]const u8).init(allocator);
defer env_cache.deinit();

// 只读取一次环境变量
if (env_cache.get(key)) |value| {
    return value;
}

const value = std.os.getenv(key);
try env_cache.put(key, value);
```

---

*Last updated: 2025-01-22*
