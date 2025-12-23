# Config - 测试文档

> 测试覆盖、测试策略和基准测试

**最后更新**: 2025-01-22

---

## 单元测试

```zig
test "Load JSON config with multiple exchanges" {
    const json =
        \\{
        \\  "server": {"host": "localhost", "port": 8080},
        \\  "exchanges": [
        \\    {"name": "binance", "api_key": "binance-key", "api_secret": "binance-secret", "testnet": false},
        \\    {"name": "okx", "api_key": "okx-key", "api_secret": "okx-secret", "testnet": false}
        \\  ],
        \\  "trading": {"max_position_size": 10000.0, "leverage": 1, "risk_limit": 5000.0},
        \\  "logging": {"level": "info", "file": null}
        \\}
    ;

    const cfg = try ConfigLoader.loadFromJSON(std.testing.allocator, json, AppConfig);
    defer cfg.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("localhost", cfg.server.host);
    try std.testing.expectEqual(@as(u16, 8080), cfg.server.port);
    try std.testing.expectEqual(@as(usize, 2), cfg.exchanges.len);
    try std.testing.expectEqualStrings("binance", cfg.exchanges[0].name);
    try std.testing.expectEqualStrings("okx", cfg.exchanges[1].name);
}

test "Environment variable override for exchanges" {
    try std.os.setenv("ZIGQUANT_SERVER_PORT", "9090");
    try std.os.setenv("ZIGQUANT_EXCHANGES_BINANCE_API_KEY", "new-binance-key");
    defer std.os.unsetenv("ZIGQUANT_SERVER_PORT");
    defer std.os.unsetenv("ZIGQUANT_EXCHANGES_BINANCE_API_KEY");

    var exchanges = [_]ExchangeConfig{
        .{ .name = "binance", .api_key = "old-key", .api_secret = "secret", .testnet = false },
        .{ .name = "okx", .api_key = "okx-key", .api_secret = "okx-secret", .testnet = false },
    };

    var cfg = AppConfig{
        .server = .{ .host = "localhost", .port = 8080 },
        .exchanges = &exchanges,
        // ...
    };

    try ConfigLoader.applyEnvOverrides(&cfg, "ZIGQUANT");
    try std.testing.expectEqual(@as(u16, 9090), cfg.server.port);
    try std.testing.expectEqualStrings("new-binance-key", cfg.exchanges[0].api_key);
}

test "Get exchange by name" {
    var exchanges = [_]ExchangeConfig{
        .{ .name = "binance", .api_key = "key1", .api_secret = "secret1", .testnet = false },
        .{ .name = "okx", .api_key = "key2", .api_secret = "secret2", .testnet = false },
    };

    const cfg = AppConfig{
        .server = .{ .host = "localhost", .port = 8080 },
        .exchanges = &exchanges,
        // ...
    };

    const binance = cfg.getExchange("binance");
    try std.testing.expect(binance != null);
    try std.testing.expectEqualStrings("binance", binance.?.name);

    const okx = cfg.getExchange("okx");
    try std.testing.expect(okx != null);
    try std.testing.expectEqualStrings("okx", okx.?.name);

    const notfound = cfg.getExchange("bybit");
    try std.testing.expect(notfound == null);
}

test "Sanitize sensitive fields" {
    const cfg = ExchangeConfig{
        .name = "binance",
        .api_key = "real-key",
        .api_secret = "real-secret",
        .testnet = false,
    };

    const sanitized = cfg.sanitize();
    try std.testing.expectEqualStrings("***REDACTED***", sanitized.api_key);
    try std.testing.expectEqualStrings("***REDACTED***", sanitized.api_secret);
    try std.testing.expectEqualStrings("binance", sanitized.name);
}

test "Config validation - invalid port" {
    var exchanges = [_]ExchangeConfig{
        .{ .name = "binance", .api_key = "key", .api_secret = "secret", .testnet = false },
    };

    const cfg = AppConfig{
        .server = .{ .host = "localhost", .port = 0 },  // Invalid port
        .exchanges = &exchanges,
        // ...
    };

    const result = cfg.validate();
    try std.testing.expectError(error.InvalidPort, result);
}

test "Config validation - no exchanges" {
    const cfg = AppConfig{
        .server = .{ .host = "localhost", .port = 8080 },
        .exchanges = &[_]ExchangeConfig{},  // Empty exchanges
        // ...
    };

    const result = cfg.validate();
    try std.testing.expectError(error.NoExchangeConfigured, result);
}

test "Config validation - duplicate exchange names" {
    var exchanges = [_]ExchangeConfig{
        .{ .name = "binance", .api_key = "key1", .api_secret = "secret1", .testnet = false },
        .{ .name = "binance", .api_key = "key2", .api_secret = "secret2", .testnet = false },  // Duplicate
    };

    const cfg = AppConfig{
        .server = .{ .host = "localhost", .port = 8080 },
        .exchanges = &exchanges,
        // ...
    };

    const result = cfg.validate();
    try std.testing.expectError(error.DuplicateExchangeName, result);
}
```

---

## 测试运行

```bash
zig test src/core/config.zig
```

---

*Last updated: 2025-01-22*
