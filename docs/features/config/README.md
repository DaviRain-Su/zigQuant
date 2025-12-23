# Config - 配置管理

> 灵活的配置加载、环境变量覆盖、敏感信息保护

**状态**: ✅ 已完成
**版本**: v0.2.0
**Story**: [005-config](../../../stories/v0.1-foundation/005-config.md)
**最后更新**: 2025-12-23

---

## 📋 概述

Config 模块提供统一的配置管理系统，支持多种格式、环境变量覆盖和敏感信息保护。

### 为什么需要 Config？

量化交易系统需要灵活的配置管理：
- 不同环境（开发、测试、生产）使用不同配置
- API 密钥等敏感信息需要保护
- 配置需要版本控制和可追溯
- 支持热更新和动态调整

### 核心特性

- ✅ **多格式支持**: JSON (TOML 计划中)
- ✅ **多交易所配置**: 同时连接多个交易所
- ✅ **优先级加载**: 默认值 → 文件 → 环境变量
- ✅ **环境变量覆盖**: ZIGQUANT_* 前缀
- ✅ **敏感信息保护**: sanitize() 方法
- ✅ **类型安全**: 编译时类型检查
- ✅ **验证机制**: 自动验证配置有效性

---

## 🚀 快速开始

### 基本使用

```zig
const std = @import("std");
const config = @import("core/config.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 加载配置 (从文件)
    var parsed = try config.ConfigLoader.loadFromJSON(
        allocator,
        try std.fs.cwd().readFileAlloc(allocator, "config.json", 1024 * 1024),
        config.AppConfig,
    );
    defer parsed.deinit();
    const cfg = parsed.value;

    std.debug.print("Server: {s}:{}\n", .{ cfg.server.host, cfg.server.port });
}
```

### 配置文件示例

**config.json**:
```json
{
  "server": {
    "host": "localhost",
    "port": 8080
  },
  "exchanges": [
    {
      "name": "binance",
      "api_key": "binance-key",
      "api_secret": "binance-secret",
      "testnet": false
    },
    {
      "name": "okx",
      "api_key": "okx-key",
      "api_secret": "okx-secret",
      "testnet": false
    }
  ],
  "trading": {
    "max_position_size": 10000.0,
    "leverage": 1
  }
}
```

**TOML 支持** (计划中):
```toml
# ⚠️ TOML 支持尚未实现，当前仅支持 JSON
# 未来版本将支持 TOML 格式
```

### 环境变量覆盖

```bash
# 覆盖配置文件中的值
export ZIGQUANT_SERVER_PORT=9090

# 覆盖特定交易所的配置（使用索引或名称）
export ZIGQUANT_EXCHANGES_BINANCE_API_KEY="binance-production-key"
export ZIGQUANT_EXCHANGES_OKX_API_KEY="okx-production-key"

# 运行程序
./zigquant
# 将使用 port=9090 和生产环境的 API keys
```

### 敏感信息保护

```zig
var parsed = try config.ConfigLoader.loadFromJSON(allocator, json_str, config.AppConfig);
defer parsed.deinit();
const cfg = parsed.value;

// 打印配置（敏感信息自动隐藏）
for (cfg.exchanges) |exchange| {
    const sanitized = exchange.sanitize();  // ExchangeConfig.sanitize() 不需要 allocator
    std.debug.print("{}\n", .{sanitized});
}
// 输出: ExchangeConfig{ .name = "binance", .api_key = "***REDACTED***", .api_secret = "***REDACTED***" }
//       ExchangeConfig{ .name = "okx", .api_key = "***REDACTED***", .api_secret = "***REDACTED***" }
```

### 多交易所使用

```zig
const json_str = try std.fs.cwd().readFileAlloc(allocator, "config.json", 1024 * 1024);
defer allocator.free(json_str);

var parsed = try config.ConfigLoader.loadFromJSON(allocator, json_str, config.AppConfig);
defer parsed.deinit();
const cfg = parsed.value;

// 遍历所有交易所
for (cfg.exchanges) |exchange| {
    std.debug.print("Connecting to {s}...\n", .{exchange.name});
    const client = try ExchangeClient.init(allocator, exchange);
    defer client.deinit();
}

// 通过名称查找特定交易所
const binance = cfg.getExchange("binance") orelse return error.ExchangeNotFound;
std.debug.print("Binance API: {s}\n", .{binance.api_key});

// 套利场景：同时连接多个交易所
const binance_client = try ExchangeClient.init(allocator, cfg.getExchange("binance").?);
defer binance_client.deinit();

const okx_client = try ExchangeClient.init(allocator, cfg.getExchange("okx").?);
defer okx_client.deinit();

// 执行跨交易所套利
try executeArbitrage(binance_client, okx_client);
```

---

## 📚 相关文档

- [API 参考](./api.md) - 完整的 API 文档
- [实现细节](./implementation.md) - 内部实现说明
- [测试文档](./testing.md) - 测试覆盖和基准
- [Bug 追踪](./bugs.md) - 已知问题和修复
- [变更日志](./changelog.md) - 版本历史

---

## 🔧 核心 API

```zig
/// 配置加载器
pub const ConfigLoader = struct {
    /// 从 JSON 字符串加载配置
    /// 返回 Parsed(T) 对象，调用者必须调用 .deinit() 释放内存
    pub fn loadFromJSON(
        allocator: Allocator,
        json_str: []const u8,
        comptime T: type,
    ) !std.json.Parsed(T);

    /// 应用环境变量覆盖
    pub fn applyEnvOverrides(
        config: anytype,
        prefix: []const u8,
        allocator: Allocator,
    ) !void;
};

/// 应用配置
pub const AppConfig = struct {
    server: ServerConfig,
    exchanges: []ExchangeConfig,  // 支持多个交易所
    trading: TradingConfig,
    logging: LoggingConfig,

    pub fn validate(self: AppConfig) !void;
    pub fn sanitize(self: AppConfig, allocator: Allocator) !AppConfig;

    /// 通过名称查找交易所配置
    pub fn getExchange(self: AppConfig, name: []const u8) ?ExchangeConfig;

    // 注意：内存管理由 JSON 解析器处理
    // 使用 loadFromJSON 返回的 Parsed(AppConfig) 对象的 .deinit() 方法释放内存
};

/// 服务器配置
pub const ServerConfig = struct {
    host: []const u8,
    port: u16,
};

/// 交易所配置
pub const ExchangeConfig = struct {
    name: []const u8,
    api_key: []const u8,
    api_secret: []const u8,
    testnet: bool = false,

    pub fn sanitize(self: ExchangeConfig) ExchangeConfig;
};

/// 交易配置
pub const TradingConfig = struct {
    max_position_size: f64,
    leverage: u8,
    risk_limit: f64,
};

/// 日志配置
pub const LoggingConfig = struct {
    level: []const u8,
    file: ?[]const u8,
    max_size: usize = 10_000_000,
};
```

---

## 📝 最佳实践

### ✅ DO

```zig
// 1. 使用环境变量管理敏感信息
// config.json - 不包含密钥
{
  "exchanges": [
    {
      "name": "binance",
      "testnet": false
    },
    {
      "name": "okx",
      "testnet": false
    }
  ]
}

// .env 文件或环境变量
export ZIGQUANT_EXCHANGES_BINANCE_API_KEY="binance-key"
export ZIGQUANT_EXCHANGES_BINANCE_API_SECRET="binance-secret"
export ZIGQUANT_EXCHANGES_OKX_API_KEY="okx-key"
export ZIGQUANT_EXCHANGES_OKX_API_SECRET="okx-secret"

// 2. 验证配置（自动在 loadFromJSON 中执行）
const json_str = try std.fs.cwd().readFileAlloc(allocator, "config.json", 1024 * 1024);
defer allocator.free(json_str);
var parsed = try ConfigLoader.loadFromJSON(allocator, json_str, AppConfig);
defer parsed.deinit();
const cfg = parsed.value;  // 配置已自动验证

// 3. 打印时隐藏敏感信息
const sanitized = try cfg.sanitize(allocator);
defer allocator.free(sanitized.exchanges);
std.debug.print("{}\n", .{sanitized});

// 4. 使用不同环境的配置文件
const env = std.posix.getenv("ENV") orelse "dev";
const config_file = if (std.mem.eql(u8, env, "prod"))
    "config.prod.json"
else
    "config.dev.json";
const json = try std.fs.cwd().readFileAlloc(allocator, config_file, 1024 * 1024);
defer allocator.free(json);
var parsed = try ConfigLoader.loadFromJSON(allocator, json, AppConfig);
defer parsed.deinit();
```

### ❌ DON'T

```zig
// 1. 避免硬编码敏感信息
const cfg = AppConfig{
    .exchange = .{
        .api_key = "hardcoded-key",  // ❌ 不要这样做
        .api_secret = "hardcoded-secret",  // ❌ 危险
    },
};

// 2. 避免将密钥提交到版本控制
// config.json (应该在 .gitignore 中)
{
  "api_key": "real-key"  // ❌ 不要提交
}

// 3. 避免直接打印配置
std.debug.print("{}\n", .{cfg});  // ❌ 可能泄露密钥

// 4. 避免跳过验证
const cfg = try ConfigLoader.load(allocator, "config.json", AppConfig);
// ❌ 没有调用 cfg.validate()
```

---

## 🎯 使用场景

### ✅ 适用

- **多环境部署**: 开发、测试、生产
- **多交易所管理**: 同时连接多个交易所进行套利、对冲
- **敏感信息管理**: API 密钥、密码
- **功能开关**: 启用/禁用特性
- **性能调优**: 连接池大小、超时时间
- **业务参数**: 交易限额、风险参数

### ❌ 不适用

- 运行时动态配置（使用配置中心）
- 频繁变化的参数（使用数据库）
- 用户级配置（使用专门的用户设置）

---

## 📊 性能指标

- **配置加载**: <100ms（JSON/TOML 解析）
- **环境变量覆盖**: <10ms
- **验证**: <1ms
- **内存占用**: <10KB

---

## 💡 未来改进

- [ ] 支持 TOML 格式 (当前 load() 返回 error.UnsupportedFormat)
- [ ] 支持 YAML 格式
- [ ] 配置热更新（文件监听）
- [ ] 配置加密（AES）
- [ ] 远程配置中心集成
- [ ] 配置版本管理
- [ ] 配置 diff 工具
- [ ] 添加 AppConfig.deinit() 方法简化内存管理

---

*Last updated: 2025-01-22*
