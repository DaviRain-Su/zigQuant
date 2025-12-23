const std = @import("std");
const zigQuant = @import("zigQuant");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== zigQuant - Time Module Demo ===\n\n", .{});

    // Get current timestamp
    const now = zigQuant.Timestamp.now();
    const now_iso = try now.toISO8601(allocator);
    defer allocator.free(now_iso);
    std.debug.print("Current timestamp: {} ms ({s})\n", .{ now.millis, now_iso });

    // Parse ISO 8601
    const parsed = try zigQuant.Timestamp.fromISO8601(allocator, "2024-01-15T10:30:00.500Z");
    const parsed_iso = try parsed.toISO8601(allocator);
    defer allocator.free(parsed_iso);
    std.debug.print("Parsed '2024-01-15T10:30:00.500Z': {} ms\n", .{parsed.millis});
    std.debug.print("  Roundtrip: {s}\n\n", .{parsed_iso});

    // Duration examples
    const one_hour = zigQuant.Duration.fromHours(1);
    const one_day = zigQuant.Duration.DAY;
    std.debug.print("One hour: {} ms ({}s)\n", .{ one_hour.millis, one_hour.toSeconds() });
    std.debug.print("One day: {} ms ({}s)\n\n", .{ one_day.millis, one_day.toSeconds() });

    // K-line alignment
    const ts = try zigQuant.Timestamp.fromISO8601(allocator, "2024-01-15T10:32:45Z");
    const aligned_5m = ts.alignToKline(.@"5m");
    const aligned_iso = try aligned_5m.toISO8601(allocator);
    defer allocator.free(aligned_iso);
    std.debug.print("Original: 2024-01-15T10:32:45Z\n", .{});
    std.debug.print("Aligned to 5m: {s}\n\n", .{aligned_iso});

    // K-line intervals
    std.debug.print("K-line intervals:\n", .{});
    inline for (@typeInfo(zigQuant.KlineInterval).@"enum".fields) |field| {
        const interval = @field(zigQuant.KlineInterval, field.name);
        std.debug.print("  {s}: {} ms\n", .{ interval.toString(), interval.toMillis() });
    }

    std.debug.print("\n=== zigQuant - Error System Demo ===\n\n", .{});

    // Error wrapping
    const ctx = zigQuant.ErrorContext.initWithCode(429, "Rate limit exceeded");
    std.debug.print("ErrorContext: code={?}, message={s}\n", .{ ctx.code, ctx.message });

    // Wrapped error with chain
    const wrapped1 = zigQuant.errors.wrap(zigQuant.NetworkError.Timeout, "Network timeout");
    const wrapped2 = zigQuant.errors.wrapWithSource(zigQuant.APIError.ServerError, "API call failed", &wrapped1);
    std.debug.print("Error chain depth: {}\n", .{wrapped2.chainDepth()});

    // Print error chain to buffer
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(allocator);
    try wrapped2.printChain(buf.writer(allocator));
    std.debug.print("{s}", .{buf.items});

    // Retry configuration
    const retry_config = zigQuant.RetryConfig{
        .max_retries = 3,
        .strategy = .exponential_backoff,
        .initial_delay_ms = 100,
        .max_delay_ms = 5000,
    };
    std.debug.print("\nRetry delays:\n", .{});
    for (0..4) |i| {
        const delay = retry_config.calculateDelay(@intCast(i));
        std.debug.print("  Attempt {}: {} ms\n", .{ i, delay });
    }

    // Error categorization
    std.debug.print("\nError categories:\n", .{});
    std.debug.print("  ConnectionFailed: {s}\n", .{zigQuant.errors.errorCategory(zigQuant.NetworkError.ConnectionFailed)});
    std.debug.print("  RateLimitExceeded: {s}\n", .{zigQuant.errors.errorCategory(zigQuant.APIError.RateLimitExceeded)});
    std.debug.print("  ParseError: {s}\n", .{zigQuant.errors.errorCategory(zigQuant.DataError.ParseError)});

    std.debug.print("\nRetryable errors:\n", .{});
    std.debug.print("  ConnectionFailed: {}\n", .{zigQuant.errors.isRetryable(zigQuant.NetworkError.ConnectionFailed)});
    std.debug.print("  Unauthorized: {}\n", .{zigQuant.errors.isRetryable(zigQuant.APIError.Unauthorized)});

    std.debug.print("\n=== zigQuant - Logger Module Demo ===\n\n", .{});

    // Demo 1: Console Logger with structured fields
    std.debug.print("Demo 1: Console Logger (stderr)\n", .{});
    {
        const ConsoleWriterType = zigQuant.ConsoleWriter(std.fs.File);
        var console = ConsoleWriterType.init(allocator, std.fs.File.stderr());
        defer console.deinit();

        var log = zigQuant.Logger.init(allocator, console.writer(), .debug);
        defer log.deinit();

        try log.debug("应用程序启动", .{ .version = "0.1.0", .pid = 12345 });
        try log.info("交易系统初始化", .{ .symbols = 5, .exchanges = 2 });
        try log.warn("API 延迟较高", .{ .latency_ms = 250, .threshold_ms = 100 });
        try log.err("订单执行失败", .{ .order_id = "ORD001", .reason = "insufficient_balance" });
    }

    // Demo 2: JSON Logger
    std.debug.print("\nDemo 2: JSON Logger (stdout)\n", .{});
    {
        const JSONWriterType = zigQuant.JSONWriter(std.fs.File);
        var json = JSONWriterType.init(allocator, std.fs.File.stdout());

        var log = zigQuant.Logger.init(allocator, json.writer(), .info);
        defer log.deinit();

        try log.info("订单创建", .{
            .order_id = "ORD001",
            .symbol = "BTC/USDT",
            .side = "buy",
            .price = 50000.0,
            .quantity = 1.5,
        });

        try log.info("交易执行", .{
            .trade_id = "TRD001",
            .order_id = "ORD001",
            .executed_price = 50100.0,
            .fee = 75.15,
        });
    }

    // Demo 3: File Logger
    std.debug.print("\nDemo 3: File Logger\n", .{});
    {
        var file_writer = try zigQuant.FileWriter.init(allocator, "/tmp/zigquant_demo.log");
        defer file_writer.deinit();

        var log = zigQuant.Logger.init(allocator, file_writer.writer(), .info);
        defer log.deinit();

        try log.info("系统启动", .{
            .timestamp = std.time.timestamp(),
            .mode = "production",
        });

        try log.info("策略加载", .{
            .strategy = "momentum",
            .parameters = 5,
        });

        std.debug.print("日志已写入 /tmp/zigquant_demo.log\n", .{});
    }

    // Demo 4: Log level filtering
    std.debug.print("\nDemo 4: 日志级别过滤 (只显示 warn 及以上)\n", .{});
    {
        const ConsoleWriterType = zigQuant.ConsoleWriter(std.fs.File);
        var console = ConsoleWriterType.init(allocator, std.fs.File.stderr());
        defer console.deinit();

        var log = zigQuant.Logger.init(allocator, console.writer(), .warn);
        defer log.deinit();

        try log.debug("调试信息", .{}); // 不会显示
        try log.info("普通信息", .{}); // 不会显示
        try log.warn("警告信息", .{ .code = 404 }); // 会显示
        try log.err("错误信息", .{ .error_type = "NetworkError" }); // 会显示
    }

    // Demo 5: All log levels
    std.debug.print("\nDemo 5: 所有日志级别\n", .{});
    {
        const ConsoleWriterType = zigQuant.ConsoleWriter(std.fs.File);
        var console = ConsoleWriterType.init(allocator, std.fs.File.stderr());
        defer console.deinit();

        var log = zigQuant.Logger.init(allocator, console.writer(), .trace);
        defer log.deinit();

        try log.trace("追踪信息", .{ .function = "processOrder" });
        try log.debug("调试信息", .{ .variable = "price", .value = 50000 });
        try log.info("一般信息", .{ .event = "order_created" });
        try log.warn("警告信息", .{ .memory_usage = 85 });
        try log.err("错误信息", .{ .error_code = 500 });
        try log.fatal("致命错误", .{ .reason = "system_crash" });
    }

    std.debug.print("\n=== zigQuant - Config Module Demo ===\n\n", .{});

    // Demo: Load configuration from JSON
    std.debug.print("Demo: 从 JSON 加载配置\n", .{});
    {
        const config_json =
            \\{
            \\  "server": {
            \\    "host": "0.0.0.0",
            \\    "port": 8080
            \\  },
            \\  "exchanges": [
            \\    {
            \\      "name": "binance",
            \\      "api_key": "your-api-key-here",
            \\      "api_secret": "your-api-secret-here",
            \\      "testnet": true
            \\    },
            \\    {
            \\      "name": "okx",
            \\      "api_key": "okx-api-key",
            \\      "api_secret": "okx-api-secret",
            \\      "testnet": false
            \\    }
            \\  ],
            \\  "trading": {
            \\    "max_position_size": 10000.0,
            \\    "leverage": 3,
            \\    "risk_limit": 0.02
            \\  },
            \\  "logging": {
            \\    "level": "info",
            \\    "max_size": 20000000
            \\  }
            \\}
        ;

        const config_parsed = try zigQuant.ConfigLoader.loadFromJSON(
            allocator,
            config_json,
            zigQuant.AppConfig,
        );
        defer config_parsed.deinit();

        const config = config_parsed.value;

        std.debug.print("服务器配置: {s}:{}\n", .{ config.server.host, config.server.port });
        std.debug.print("交易所数量: {}\n", .{config.exchanges.len});

        for (config.exchanges) |exchange| {
            std.debug.print("  - {s} (testnet: {})\n", .{ exchange.name, exchange.testnet });
        }

        std.debug.print("交易配置:\n", .{});
        std.debug.print("  最大持仓: {d}\n", .{config.trading.max_position_size});
        std.debug.print("  杠杆倍数: {}\n", .{config.trading.leverage});
        std.debug.print("  风险限制: {d}\n", .{config.trading.risk_limit});

        // Test sanitize - hide sensitive information
        const sanitized = try config.sanitize(allocator);
        defer allocator.free(sanitized.exchanges);

        std.debug.print("\n敏感信息保护 (sanitized):\n", .{});
        for (sanitized.exchanges) |exchange| {
            std.debug.print("  - {s}: api_key={s}\n", .{ exchange.name, exchange.api_key });
        }

        // Test getExchange
        if (config.getExchange("binance")) |binance| {
            std.debug.print("\n查找交易所 'binance': 找到 (testnet={})\n", .{binance.testnet});
        }
    }

    std.debug.print("\n=== zigQuant - Decimal Module Demo ===\n\n", .{});

    // Demo 1: 精度对比 - 浮点数 vs Decimal
    std.debug.print("Demo 1: 精度对比 (浮点数问题)\n", .{});
    {
        // 浮点数精度问题
        const f1: f64 = 0.1;
        const f2: f64 = 0.2;
        const f3 = f1 + f2;
        std.debug.print("  f64: 0.1 + 0.2 = {d:.20} ❌ (不精确)\n", .{f3});

        // Decimal 精确计算
        const d1 = try zigQuant.Decimal.fromString("0.1");
        const d2 = try zigQuant.Decimal.fromString("0.2");
        const d3 = d1.add(d2);
        const d3_str = try d3.toString(allocator);
        defer allocator.free(d3_str);
        std.debug.print("  Decimal: 0.1 + 0.2 = {s} ✅ (精确)\n", .{d3_str});
    }

    // Demo 2: 金融计算 - 买入 BTC
    std.debug.print("\nDemo 2: 金融计算示例 (买入 BTC)\n", .{});
    {
        const price = try zigQuant.Decimal.fromString("43250.50"); // BTC 价格
        const amount = try zigQuant.Decimal.fromString("0.01"); // 买入数量
        const fee_rate = try zigQuant.Decimal.fromString("0.001"); // 0.1% 手续费

        const cost = price.mul(amount); // 成本 = 价格 × 数量
        const fee = cost.mul(fee_rate); // 手续费 = 成本 × 费率
        const total = cost.add(fee); // 总计 = 成本 + 手续费

        const price_str = try price.toString(allocator);
        defer allocator.free(price_str);
        const amount_str = try amount.toString(allocator);
        defer allocator.free(amount_str);
        const cost_str = try cost.toString(allocator);
        defer allocator.free(cost_str);
        const fee_str = try fee.toString(allocator);
        defer allocator.free(fee_str);
        const total_str = try total.toString(allocator);
        defer allocator.free(total_str);

        std.debug.print("  价格: ${s} USDT\n", .{price_str});
        std.debug.print("  数量: {s} BTC\n", .{amount_str});
        std.debug.print("  成本: ${s} USDT\n", .{cost_str});
        std.debug.print("  手续费 (0.1%): ${s} USDT\n", .{fee_str});
        std.debug.print("  总计: ${s} USDT\n", .{total_str});
    }

    // Demo 3: 四则运算
    std.debug.print("\nDemo 3: 四则运算\n", .{});
    {
        const a = try zigQuant.Decimal.fromString("100.50");
        const b = try zigQuant.Decimal.fromString("25.25");

        const sum = a.add(b);
        const diff = a.sub(b);
        const product = a.mul(b);
        const quotient = try a.div(b);

        const sum_str = try sum.toString(allocator);
        defer allocator.free(sum_str);
        const diff_str = try diff.toString(allocator);
        defer allocator.free(diff_str);
        const product_str = try product.toString(allocator);
        defer allocator.free(product_str);
        const quotient_str = try quotient.toString(allocator);
        defer allocator.free(quotient_str);

        std.debug.print("  100.50 + 25.25 = {s}\n", .{sum_str});
        std.debug.print("  100.50 - 25.25 = {s}\n", .{diff_str});
        std.debug.print("  100.50 × 25.25 = {s}\n", .{product_str});
        std.debug.print("  100.50 ÷ 25.25 = {s}\n", .{quotient_str});
    }

    // Demo 4: 比较操作
    std.debug.print("\nDemo 4: 比较操作\n", .{});
    {
        const price1 = try zigQuant.Decimal.fromString("50000");
        const price2 = try zigQuant.Decimal.fromString("48000");
        const price3 = try zigQuant.Decimal.fromString("50000");

        std.debug.print("  50000 > 48000? {}\n", .{price1.cmp(price2) == .gt});
        std.debug.print("  50000 < 48000? {}\n", .{price1.cmp(price2) == .lt});
        std.debug.print("  50000 == 50000? {}\n", .{price1.eql(price3)});
    }

    // Demo 5: 工具函数
    std.debug.print("\nDemo 5: 工具函数\n", .{});
    {
        const positive = try zigQuant.Decimal.fromString("123.456");
        const negative = try zigQuant.Decimal.fromString("-123.456");
        const zero = zigQuant.Decimal.ZERO;

        std.debug.print("  123.456 是正数? {}\n", .{positive.isPositive()});
        std.debug.print("  -123.456 是负数? {}\n", .{negative.isNegative()});
        std.debug.print("  0 是零? {}\n", .{zero.isZero()});

        const abs_neg = negative.abs();
        const abs_str = try abs_neg.toString(allocator);
        defer allocator.free(abs_str);
        std.debug.print("  |-123.456| = {s}\n", .{abs_str});

        const negated = positive.negate();
        const neg_str = try negated.toString(allocator);
        defer allocator.free(neg_str);
        std.debug.print("  -(123.456) = {s}\n", .{neg_str});
    }

    // Demo 6: 从不同类型构造
    std.debug.print("\nDemo 6: 从不同类型构造\n", .{});
    {
        const from_int = zigQuant.Decimal.fromInt(42);
        const from_float = zigQuant.Decimal.fromFloat(3.14159);
        const from_string = try zigQuant.Decimal.fromString("123.456789");

        const int_str = try from_int.toString(allocator);
        defer allocator.free(int_str);
        const float_str = try from_float.toString(allocator);
        defer allocator.free(float_str);
        const string_str = try from_string.toString(allocator);
        defer allocator.free(string_str);

        std.debug.print("  fromInt(42): {s}\n", .{int_str});
        std.debug.print("  fromFloat(3.14159): {s}\n", .{float_str});
        std.debug.print("  fromString(\"123.456789\"): {s}\n", .{string_str});
    }

    // Demo 7: 套利场景计算
    std.debug.print("\nDemo 7: 套利场景 (跨交易所价差)\n", .{});
    {
        const binance_price = try zigQuant.Decimal.fromString("43250.50");
        const okx_price = try zigQuant.Decimal.fromString("43280.75");

        const price_diff = okx_price.sub(binance_price);
        const diff_str = try price_diff.toString(allocator);
        defer allocator.free(diff_str);

        const profit_rate = try price_diff.div(binance_price);
        const profit_rate_float = profit_rate.toFloat() * 100;

        std.debug.print("  Binance 价格: 43250.50 USDT\n", .{});
        std.debug.print("  OKX 价格: 43280.75 USDT\n", .{});
        std.debug.print("  价差: {s} USDT\n", .{diff_str});
        std.debug.print("  收益率: {d:.4}%\n", .{profit_rate_float});

        if (profit_rate_float > 0.1) {
            std.debug.print("  💰 套利机会！\n", .{});
        }
    }

    std.debug.print("\n=== Demo Complete ===\n", .{});
}
