// Config System - Configuration Management
//
// Provides a flexible configuration management system:
// - Multiple format support (JSON, TOML)
// - Multiple exchange configuration
// - Priority-based loading: defaults → file → env vars
// - Environment variable override with ZIGQUANT_* prefix
// - Sensitive information protection via sanitize()
// - Type-safe configuration with validation
//
// Design principles:
// - Environment variables have highest priority
// - Compile-time type checking
// - Sensitive data protection
// - Multi-exchange support for arbitrage

const std = @import("std");
const Allocator = std.mem.Allocator;

// ============================================================================
// Configuration Errors
// ============================================================================

pub const ConfigError = error{
    InvalidPort,
    NoExchangeConfigured,
    DuplicateExchangeName,
    EmptyExchangeName,
    EmptyAPIKey,
    EmptyAPISecret,
    InvalidLeverage,
    InvalidPositionSize,
    InvalidLogLevel,
    InvalidRiskLimit,
};

// ============================================================================
// Server Configuration
// ============================================================================

pub const ServerConfig = struct {
    host: []const u8 = "localhost",
    port: u16 = 8080,
};

// ============================================================================
// Exchange Configuration
// ============================================================================

pub const ExchangeConfig = struct {
    name: []const u8,
    api_key: []const u8 = "",
    api_secret: []const u8 = "",
    testnet: bool = false,

    /// Sanitize sensitive information for logging
    pub fn sanitize(self: ExchangeConfig) ExchangeConfig {
        return .{
            .name = self.name,
            .api_key = if (self.api_key.len > 0) "***REDACTED***" else "",
            .api_secret = if (self.api_secret.len > 0) "***REDACTED***" else "",
            .testnet = self.testnet,
        };
    }
};

// ============================================================================
// Trading Configuration
// ============================================================================

pub const TradingConfig = struct {
    max_position_size: f64 = 10000.0,
    leverage: u8 = 1,
    risk_limit: f64 = 0.02, // 2% default risk limit
};

// ============================================================================
// Logging Configuration
// ============================================================================

pub const LoggingConfig = struct {
    level: []const u8 = "info",
    file: ?[]const u8 = null,
    max_size: usize = 10_000_000, // 10MB default
};

// ============================================================================
// Application Configuration
// ============================================================================

pub const AppConfig = struct {
    server: ServerConfig = .{},
    exchanges: []ExchangeConfig = &[_]ExchangeConfig{},
    trading: TradingConfig = .{},
    logging: LoggingConfig = .{},

    /// Validate configuration
    pub fn validate(self: AppConfig) ConfigError!void {
        // Server validation
        if (self.server.port == 0) {
            return ConfigError.InvalidPort;
        }

        // Exchange validation
        if (self.exchanges.len == 0) {
            return ConfigError.NoExchangeConfigured;
        }

        // Check for duplicate exchange names
        for (self.exchanges, 0..) |exchange1, i| {
            for (self.exchanges[i + 1 ..]) |exchange2| {
                if (std.mem.eql(u8, exchange1.name, exchange2.name)) {
                    return ConfigError.DuplicateExchangeName;
                }
            }

            // Validate each exchange
            if (exchange1.name.len == 0) {
                return ConfigError.EmptyExchangeName;
            }
            if (exchange1.api_key.len == 0) {
                return ConfigError.EmptyAPIKey;
            }
            if (exchange1.api_secret.len == 0) {
                return ConfigError.EmptyAPISecret;
            }
        }

        // Trading validation
        if (self.trading.leverage < 1 or self.trading.leverage > 100) {
            return ConfigError.InvalidLeverage;
        }

        if (self.trading.max_position_size <= 0) {
            return ConfigError.InvalidPositionSize;
        }

        if (self.trading.risk_limit <= 0 or self.trading.risk_limit > 1.0) {
            return ConfigError.InvalidRiskLimit;
        }

        // Logging validation
        const valid_levels = [_][]const u8{ "trace", "debug", "info", "warn", "error", "fatal" };
        var valid = false;
        for (valid_levels) |level| {
            if (std.mem.eql(u8, self.logging.level, level)) {
                valid = true;
                break;
            }
        }
        if (!valid) {
            return ConfigError.InvalidLogLevel;
        }
    }

    /// Sanitize sensitive information for logging
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

    /// Find exchange by name
    pub fn getExchange(self: AppConfig, name: []const u8) ?ExchangeConfig {
        for (self.exchanges) |exchange| {
            if (std.mem.eql(u8, exchange.name, name)) {
                return exchange;
            }
        }
        return null;
    }

    // Note: Memory management is handled by the JSON parser or the caller.
    // If loaded from JSON, use the Parsed(AppConfig) object's deinit() method.
    // If created manually, the caller is responsible for freeing allocated memory.
};

// ============================================================================
// Configuration Loader
// ============================================================================

pub const ConfigLoader = struct {
    /// Load configuration from file with environment variable override
    pub fn load(
        allocator: Allocator,
        path: []const u8,
        comptime T: type,
    ) !T {
        // Read file content
        const file_content = try std.fs.cwd().readFileAlloc(
            allocator,
            path,
            1024 * 1024, // 1MB max
        );
        defer allocator.free(file_content);

        // Determine format by extension
        if (std.mem.endsWith(u8, path, ".json")) {
            return try loadFromJSON(allocator, file_content, T);
        } else if (std.mem.endsWith(u8, path, ".toml")) {
            // TOML support can be added later
            return error.UnsupportedFormat;
        } else {
            return error.UnknownFormat;
        }
    }

    /// Load configuration from JSON string
    /// Returns a Parsed(T) object that must be deinited by the caller
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

        // Apply environment variable overrides
        try applyEnvOverrides(&parsed.value, "ZIGQUANT", allocator);

        // Validate configuration
        if (@hasDecl(T, "validate")) {
            try parsed.value.validate();
        }

        return parsed;
    }

    /// Apply environment variable overrides
    pub fn applyEnvOverrides(
        config: anytype,
        prefix: []const u8,
        allocator: Allocator,
    ) !void {
        const T = @TypeOf(config.*);
        const type_info = @typeInfo(T);

        if (type_info != .@"struct") return;

        const fields = type_info.@"struct".fields;

        inline for (fields) |field| {
            // Build environment variable key
            const env_key_upper = try allocator.alloc(u8, field.name.len);
            defer allocator.free(env_key_upper);

            _ = std.ascii.upperString(env_key_upper, field.name);

            const env_key = try std.fmt.allocPrint(
                allocator,
                "{s}_{s}",
                .{ prefix, env_key_upper },
            );
            defer allocator.free(env_key);

            // Handle nested structs
            const field_type_info = @typeInfo(field.type);
            if (field_type_info == .@"struct") {
                const nested_prefix = try std.fmt.allocPrint(
                    allocator,
                    "{s}_{s}",
                    .{ prefix, env_key_upper },
                );
                defer allocator.free(nested_prefix);

                try applyEnvOverrides(&@field(config.*, field.name), nested_prefix, allocator);
            } else if (field_type_info == .pointer and
                field_type_info.pointer.size == .slice)
            {
                    const slice = @field(config.*, field.name);
                for (slice, 0..) |*item, i| {
                    // Support index-based override
                    const indexed_prefix = try std.fmt.allocPrint(
                        allocator,
                        "{s}_{s}_{}",
                        .{ prefix, env_key_upper, i },
                    );
                    defer allocator.free(indexed_prefix);

                    try applyEnvOverrides(item, indexed_prefix, allocator);

                    // Support name-based override for exchanges (only for struct types)
                    const item_type_info = @typeInfo(@TypeOf(item.*));
                    if (item_type_info == .@"struct") {
                        if (@hasField(@TypeOf(item.*), "name")) {
                            const name = @field(item.*, "name");
                            const name_upper = try allocator.alloc(u8, name.len);
                            defer allocator.free(name_upper);

                            _ = std.ascii.upperString(name_upper, name);

                            const named_prefix = try std.fmt.allocPrint(
                                allocator,
                                "{s}_{s}_{s}",
                                .{ prefix, env_key_upper, name_upper },
                            );
                            defer allocator.free(named_prefix);

                            try applyEnvOverrides(item, named_prefix, allocator);
                        }
                    }
                }
            } else {
                // Handle simple types (int, float, bool, string, optional)
                // Check if environment variable exists
                if (std.posix.getenv(env_key)) |value| {
                    // Parse and set value based on type
                    @field(config.*, field.name) = try parseValue(field.type, value, allocator);
                }
            }
        }
    }

    /// Parse string value to typed value
    fn parseValue(comptime T: type, value: []const u8, allocator: Allocator) !T {
        const type_info = @typeInfo(T);

        return switch (type_info) {
            .int => try std.fmt.parseInt(T, value, 10),
            .float => try std.fmt.parseFloat(T, value),
            .bool => std.mem.eql(u8, value, "true") or std.mem.eql(u8, value, "1"),
            .pointer => |ptr_info| {
                if (ptr_info.size == .slice and ptr_info.child == u8) {
                    // For strings, duplicate the value
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
};

// ============================================================================
// Tests
// ============================================================================

test "ExchangeConfig sanitize" {
    const exchange = ExchangeConfig{
        .name = "binance",
        .api_key = "my-secret-key",
        .api_secret = "my-secret-secret",
        .testnet = false,
    };

    const sanitized = exchange.sanitize();

    try std.testing.expectEqualStrings("binance", sanitized.name);
    try std.testing.expectEqualStrings("***REDACTED***", sanitized.api_key);
    try std.testing.expectEqualStrings("***REDACTED***", sanitized.api_secret);
    try std.testing.expectEqual(false, sanitized.testnet);
}

test "AppConfig getExchange" {
    var exchanges = [_]ExchangeConfig{
        .{ .name = "binance", .api_key = "key1", .api_secret = "secret1" },
        .{ .name = "okx", .api_key = "key2", .api_secret = "secret2" },
    };

    const cfg = AppConfig{
        .exchanges = &exchanges,
    };

    const binance = cfg.getExchange("binance");
    try std.testing.expect(binance != null);
    try std.testing.expectEqualStrings("binance", binance.?.name);

    const okx = cfg.getExchange("okx");
    try std.testing.expect(okx != null);
    try std.testing.expectEqualStrings("okx", okx.?.name);

    const not_found = cfg.getExchange("coinbase");
    try std.testing.expect(not_found == null);
}

test "ConfigLoader loadFromJSON basic" {
    const json =
        \\{
        \\  "server": {
        \\    "host": "0.0.0.0",
        \\    "port": 9090
        \\  },
        \\  "exchanges": [
        \\    {
        \\      "name": "binance",
        \\      "api_key": "test-key",
        \\      "api_secret": "test-secret",
        \\      "testnet": true
        \\    }
        \\  ],
        \\  "trading": {
        \\    "max_position_size": 5000.0,
        \\    "leverage": 2,
        \\    "risk_limit": 0.01
        \\  },
        \\  "logging": {
        \\    "level": "debug",
        \\    "max_size": 20000000
        \\  }
        \\}
    ;

    const parsed = try ConfigLoader.loadFromJSON(
        std.testing.allocator,
        json,
        AppConfig,
    );
    defer parsed.deinit();

    const cfg = parsed.value;

    try std.testing.expectEqualStrings("0.0.0.0", cfg.server.host);
    try std.testing.expectEqual(@as(u16, 9090), cfg.server.port);

    try std.testing.expectEqual(@as(usize, 1), cfg.exchanges.len);
    try std.testing.expectEqualStrings("binance", cfg.exchanges[0].name);
    try std.testing.expectEqual(true, cfg.exchanges[0].testnet);

    try std.testing.expectEqual(@as(f64, 5000.0), cfg.trading.max_position_size);
    try std.testing.expectEqual(@as(u8, 2), cfg.trading.leverage);

    try std.testing.expectEqualStrings("debug", cfg.logging.level);
}

test "AppConfig validate" {
    var exchanges = [_]ExchangeConfig{
        .{ .name = "binance", .api_key = "key1", .api_secret = "secret1" },
    };

    const cfg = AppConfig{
        .server = .{ .host = "localhost", .port = 8080 },
        .exchanges = &exchanges,
        .trading = .{ .leverage = 2, .max_position_size = 10000.0, .risk_limit = 0.02 },
        .logging = .{ .level = "info" },
    };

    try cfg.validate();
}

test "AppConfig validate errors" {
    // Test invalid port
    {
        const cfg = AppConfig{
            .server = .{ .port = 0 },
        };
        try std.testing.expectError(ConfigError.InvalidPort, cfg.validate());
    }

    // Test no exchanges
    {
        const cfg = AppConfig{
            .server = .{ .port = 8080 },
        };
        try std.testing.expectError(ConfigError.NoExchangeConfigured, cfg.validate());
    }

    // Test invalid leverage
    {
        var exchanges = [_]ExchangeConfig{
            .{ .name = "binance", .api_key = "key", .api_secret = "secret" },
        };
        const cfg = AppConfig{
            .server = .{ .port = 8080 },
            .exchanges = &exchanges,
            .trading = .{ .leverage = 200 }, // Too high
        };
        try std.testing.expectError(ConfigError.InvalidLeverage, cfg.validate());
    }
}
