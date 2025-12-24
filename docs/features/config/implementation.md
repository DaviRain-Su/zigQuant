# Config - 实现细节

> 内部实现说明和设计决策

**最后更新**: 2025-12-24

---

## 核心算法

### 1. 配置加载流程

```zig
pub fn loadFromJSON(
    allocator: Allocator,
    json_str: []const u8,
    comptime T: type,
) !std.json.Parsed(T) {
    // 1. 从 JSON 解析配置
    var parsed = try std.json.parseFromSlice(
        T,
        allocator,
        json_str,
        .{ .allocate = .alloc_always },
    );
    errdefer parsed.deinit();

    // 2. 应用环境变量覆盖（最高优先级）
    try applyEnvOverrides(&parsed.value, "ZIGQUANT", allocator);

    // 3. 验证配置
    if (@hasDecl(T, "validate")) {
        try parsed.value.validate();
    }

    // 4. 返回 Parsed 对象（调用者负责 deinit）
    return parsed;
}
```

**优先级**: 环境变量 > JSON 文件 > 结构体默认值

---

### 2. 环境变量覆盖

```zig
pub fn applyEnvOverrides(
    config: anytype,
    prefix: []const u8,
    allocator: Allocator,
) !void {
    const T = @TypeOf(config.*);
    const fields = @typeInfo(T).Struct.fields;

    inline for (fields) |field| {
        const env_key = try std.fmt.allocPrint(
            allocator,
            "{s}_{s}",
            .{ prefix, toUpperCase(field.name) },
        );
        defer allocator.free(env_key);

        if (std.posix.getenv(env_key)) |value| {
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

            try applyEnvOverrides(&@field(config, field.name), nested_prefix, allocator);
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

                try applyEnvOverrides(item, indexed_prefix, allocator);

                // 支持按名称覆盖: ZIGQUANT_EXCHANGES_BINANCE_API_KEY
                if (@hasField(@TypeOf(item.*), "name")) {
                    const name = @field(item, "name");
                    const named_prefix = try std.fmt.allocPrint(
                        allocator,
                        "{s}_{s}_{s}",
                        .{ prefix, toUpperCase(field.name), toUpperCase(name) },
                    );
                    defer allocator.free(named_prefix);

                    try applyEnvOverrides(item, named_prefix, allocator);
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

#### ExchangeConfig.sanitize()

```zig
pub fn sanitize(self: ExchangeConfig) ExchangeConfig {
    return .{
        .name = self.name,
        .api_key = if (self.api_key.len > 0) "***REDACTED***" else "",
        .api_secret = if (self.api_secret.len > 0) "***REDACTED***" else "",
        .testnet = self.testnet,
    };
}
```

**设计决策**:
- 返回新实例，不修改原配置
- 仅当密钥非空时才显示 REDACTED（避免误导）
- 不需要 allocator（返回编译时字符串）
- 用于日志和调试输出

#### AppConfig.sanitize()

```zig
pub fn sanitize(self: AppConfig, allocator: Allocator) !AppConfig {
    var sanitized_exchanges = try allocator.alloc(ExchangeConfig, self.exchanges.len);
    for (self.exchanges, 0..) |exchange, i| {
        sanitized_exchanges[i] = exchange.sanitize();
    }

    return .{
        .server = self.server,
        .exchanges = sanitized_exchanges,
        .trading = self.trading,
        .logging = self.logging,
    };
}
```

**设计决策**:
- 需要 allocator 分配新的 exchanges 数组
- 调用者负责释放 exchanges 字段
- 其他字段不含敏感信息，直接拷贝

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

### load() 方法

```zig
pub fn load(
    allocator: Allocator,
    path: []const u8,
    comptime T: type,
) !T {
    // 读取文件内容
    const file_content = try std.fs.cwd().readFileAlloc(
        allocator,
        path,
        1024 * 1024, // 1MB max
    );
    defer allocator.free(file_content);

    // 根据扩展名判断格式
    if (std.mem.endsWith(u8, path, ".json")) {
        return try loadFromJSON(allocator, file_content, T);
    } else if (std.mem.endsWith(u8, path, ".toml")) {
        // TOML support can be added later
        return error.UnsupportedFormat;
    } else {
        return error.UnknownFormat;
    }
}
```

**问题**: 此方法返回 `T` 而不是 `std.json.Parsed(T)`，但内部调用 `loadFromJSON` 返回 `Parsed(T)`。这导致类型不匹配。

**建议**: 直接使用 `loadFromJSON` 或修改 `load` 返回类型为 `std.json.Parsed(T)`

### loadFromJSON() 方法

```zig
pub fn loadFromJSON(
    allocator: Allocator,
    json_str: []const u8,
    comptime T: type,
) !std.json.Parsed(T) {
    var parsed = try std.json.parseFromSlice(
        T,
        allocator,
        json_str,
        .{ .allocate = .alloc_always },
    );
    errdefer parsed.deinit();

    // 应用环境变量覆盖
    try applyEnvOverrides(&parsed.value, "ZIGQUANT", allocator);

    // 验证配置
    if (@hasDecl(T, "validate")) {
        try parsed.value.validate();
    }

    return parsed;
}
```

**实现细节**:
- 使用 `std.json.parseFromSlice` 解析 JSON
- `.allocate = .alloc_always` 确保所有字符串都被分配
- 返回 `Parsed(T)` 对象，调用者必须调用 `.deinit()` 释放内存
- 使用 `errdefer` 确保出错时自动清理
- 编译时检查 `T` 是否有 `validate` 方法

---

## TOML 支持（未实现）

TOML 格式当前未实现，`load()` 方法会返回错误：

```zig
} else if (std.mem.endsWith(u8, path, ".toml")) {
    // TOML support can be added later
    return error.UnsupportedFormat;  // ⚠️ 未实现
}
```

**原因**: Zig 标准库不包含 TOML 解析器

**未来实现**: 可以集成第三方 TOML 库（如 zig-toml）

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

    if (self.trading.risk_limit <= 0 or self.trading.risk_limit > 1.0) {
        return error.InvalidRiskLimit;
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

### 2. 直接返回 Parsed 对象

当前实现直接返回 `std.json.Parsed(T)` 对象，避免了额外的内存拷贝：

```zig
// ✅ 高效：直接返回 parsed
return parsed;

// ❌ 低效：拷贝并释放 parsed
defer parsed.deinit();
return parsed.value;  // 会导致 use-after-free
```

### 3. 环境变量查找优化

使用 `std.posix.getenv` 直接查找，无额外缓存开销。

---

## 环境变量解析器

### parseValue() 函数

```zig
fn parseValue(comptime T: type, value: []const u8, allocator: Allocator) !T {
    const type_info = @typeInfo(T);

    return switch (type_info) {
        .int => try std.fmt.parseInt(T, value, 10),
        .float => try std.fmt.parseFloat(T, value),
        .bool => std.mem.eql(u8, value, "true") or std.mem.eql(u8, value, "1"),
        .pointer => |ptr_info| {
            if (ptr_info.size == .slice and ptr_info.child == u8) {
                // 字符串类型，复制值
                return try allocator.dupe(u8, value);
            }
            @compileError("Unsupported pointer type");
        },
        .optional => |opt_info| {
            if (value.len == 0) {
                return null;
            }
            return try parseValue(opt_info.child, value, allocator);
        },
        else => @compileError("Unsupported type for env override: " ++ @typeName(T)),
    };
}
```

**支持的类型**:
- 整数类型（u8, u16, i32 等）
- 浮点类型（f32, f64）
- 布尔类型（"true"/"1" 为 true，其他为 false）
- 字符串切片（[]const u8）
- 可选类型（?T，空字符串解析为 null）

**不支持的类型**:
- 结构体（通过递归 applyEnvOverrides 处理）
- 数组（通过切片处理）
- 联合类型
- 枚举（可以未来添加）

---

*Last updated: 2025-12-24*
