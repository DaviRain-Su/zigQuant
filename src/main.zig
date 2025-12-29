//! zigQuant CLI - Main Entry Point

const std = @import("std");
const zigQuant = @import("zigQuant");
const CLI = @import("cli/cli.zig").CLI;
const format = @import("cli/format.zig");
const strategy_commands = @import("cli/strategy_commands.zig");

// API Server imports (v1 - std.http based, direct import for legacy server)
// Note: The v1 API server uses @import("zigQuant") internally, so we import it directly
// from main.zig to avoid circular module dependencies.
const api = @import("api/mod.zig");
const ApiServer = api.Server;
const ApiConfig = api.Config;
const ApiDependencies = api.Dependencies;
const HyperliquidConnector = zigQuant.HyperliquidConnector;
const ExchangeConfig = zigQuant.ExchangeConfig;

// Core config module for file-based configuration
const CoreConfig = zigQuant.config;
const AppConfig = CoreConfig.AppConfig;
const ConfigLoader = CoreConfig.ConfigLoader;

const Logger = zigQuant.Logger;
const ConsoleWriter = zigQuant.ConsoleWriter;

/// Default development JWT secret (32 bytes)
const DEV_JWT_SECRET = "zigquant-dev-secret-key-32bytes!";

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse command line arguments
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // Skip program name
    const cli_args = if (args.len > 1) args[1..] else &[_][]const u8{};

    if (cli_args.len == 0) {
        try printGeneralHelp();
        return;
    }

    // Get command name (first non-flag argument)
    const command = cli_args[0];

    // Check if it's the serve command (API server)
    if (std.mem.eql(u8, command, "serve")) {
        try runServeCommand(allocator, cli_args);
        return;
    }

    // Check if it's the serve2 command (Zap-based API server v2)
    if (std.mem.eql(u8, command, "serve2")) {
        try runServe2Command(allocator, cli_args);
        return;
    }

    // Check if it's a strategy command (backtest, optimize, run-strategy)
    if (strategy_commands.isStrategyCommand(command)) {
        // Strategy commands don't need exchange connection
        // They use a simple logger instead of full CLI
        const ConsoleWriterType = ConsoleWriter(std.fs.File);
        var console = ConsoleWriterType.initWithColors(allocator, std.fs.File.stdout(), true);
        defer console.deinit();
        var logger = Logger.init(allocator, console.writer(), .info);

        // Execute strategy command
        strategy_commands.executeStrategyCommand(
            allocator,
            &logger,
            command,
            cli_args,
        ) catch |err| {
            try logger.err("Command failed: {s}", .{@errorName(err)});
            console.writer().flush() catch {};
            std.process.exit(1);
        };

        // Flush output before exiting
        console.writer().flush() catch {};
        return;
    }

    // For trading commands, use the existing CLI with exchange connection
    // Check for config file option
    var config_path: ?[]const u8 = null;
    var command_start: usize = 0;

    for (cli_args, 0..) |arg, i| {
        if (std.mem.eql(u8, arg, "-c") or std.mem.eql(u8, arg, "--config")) {
            if (i + 1 < cli_args.len) {
                config_path = cli_args[i + 1];
                command_start = i + 2;
                break;
            }
        } else if (std.mem.startsWith(u8, arg, "--config=")) {
            config_path = arg["--config=".len..];
            command_start = i + 1;
            break;
        }
    }

    // Initialize CLI
    const cli = CLI.init(allocator, config_path) catch |err| {
        std.debug.print("Failed to initialize: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };
    defer cli.deinit();

    // Connect to exchange
    cli.connect() catch |err| {
        try format.printError(&cli.stderr.interface, "Failed to connect: {s}", .{@errorName(err)});
        std.process.exit(1);
    };

    // Execute trading command
    const command_args = if (command_start < cli_args.len)
        cli_args[command_start..]
    else
        &[_][]const u8{};

    cli.executeCommand(command_args) catch |err| {
        try format.printError(&cli.stderr.interface, "Command failed: {s}", .{@errorName(err)});
        cli.stderr.interface.flush() catch {};
        std.process.exit(1);
    };

    // Flush output buffers before exiting
    cli.stdout.interface.flush() catch {};
    cli.stderr.interface.flush() catch {};
}

fn printGeneralHelp() !void {
    const stdout = std.fs.File.stdout();
    try stdout.writeAll(
        \\
        \\zigQuant - Quantitative Trading Framework
        \\
        \\USAGE:
        \\    zigquant <COMMAND> [OPTIONS]
        \\
        \\SERVER COMMANDS:
        \\    serve            Start REST API server (std.http)
        \\    serve2           Start Zap-based API server (v2, high-performance)
        \\
        \\STRATEGY COMMANDS:
        \\    backtest         Run strategy backtests
        \\    optimize         Parameter optimization (coming soon)
        \\    run-strategy     Live/paper trading (coming soon)
        \\
        \\TRADING COMMANDS:
        \\    price            Query current price
        \\    book             Query order book
        \\    balance          Query account balance
        \\    positions        Query open positions
        \\    orders           Query open orders
        \\    buy              Place buy order
        \\    sell             Place sell order
        \\    cancel           Cancel specific order
        \\    cancel-all       Cancel all orders
        \\    repl             Start interactive REPL mode
        \\    help             Show help message
        \\
        \\EXAMPLES:
        \\    zigquant backtest --strategy dual_ma --config config.json --data btc.csv
        \\    zigquant price BTC-USDC
        \\    zigquant balance
        \\
        \\Use 'zigquant <COMMAND> --help' for command-specific help
        \\
        \\
    );
}

/// Exchange connector holder for lifecycle management
const ExchangeConnectors = struct {
    hyperliquid: ?*HyperliquidConnector = null,
    // Future: Add more exchange connectors here
    // binance: ?*BinanceConnector = null,
    // okx: ?*OkxConnector = null,

    pub fn deinit(self: *ExchangeConnectors) void {
        if (self.hyperliquid) |c| c.destroy();
        // Future: Destroy other connectors
    }
};

/// Run the API server command
fn runServeCommand(allocator: std.mem.Allocator, args: []const []const u8) !void {
    // Parse serve command arguments
    var port: u16 = 8080;
    var host: []const u8 = "0.0.0.0";
    var config_path: ?[]const u8 = null;
    var show_help = false;

    var i: usize = 1; // Skip "serve" command
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--port") or std.mem.eql(u8, arg, "-p")) {
            i += 1;
            if (i < args.len) {
                port = std.fmt.parseInt(u16, args[i], 10) catch {
                    std.debug.print("Invalid port number: {s}\n", .{args[i]});
                    return error.InvalidArgument;
                };
            }
        } else if (std.mem.eql(u8, arg, "--host")) {
            i += 1;
            if (i < args.len) {
                host = args[i];
            }
        } else if (std.mem.eql(u8, arg, "--config") or std.mem.eql(u8, arg, "-c")) {
            i += 1;
            if (i < args.len) {
                config_path = args[i];
            }
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            show_help = true;
        }
    }

    if (show_help) {
        try printServeHelp();
        return;
    }

    // Get JWT secret from environment or use development default
    const jwt_secret = std.posix.getenv("ZIGQUANT_JWT_SECRET") orelse blk: {
        std.log.warn("ZIGQUANT_JWT_SECRET not set, using development secret", .{});
        std.log.warn("WARNING: Do not use this in production!", .{});
        break :blk DEV_JWT_SECRET;
    };

    // Create logger for exchange connectors
    const ConsoleWriterType = ConsoleWriter(std.fs.File);
    var console = ConsoleWriterType.initWithColors(allocator, std.fs.File.stdout(), true);
    defer console.deinit();
    var logger = Logger.init(allocator, console.writer(), .info);
    defer logger.deinit();

    // Create dependencies with multi-exchange support
    var deps = ApiDependencies.init(allocator);
    defer deps.deinit();

    // Exchange connectors holder for lifecycle management
    var connectors = ExchangeConnectors{};
    defer connectors.deinit();

    var exchange_count: usize = 0;

    // ========================================================================
    // Load configuration from file or environment variables
    // ========================================================================

    // Hold parsed config at function level to extend its lifetime
    var parsed_config_holder: ?std.json.Parsed(AppConfig) = null;
    defer if (parsed_config_holder) |*pc| pc.deinit();

    if (config_path) |path| {
        // Load from config file
        std.log.info("Loading configuration from: {s}", .{path});

        parsed_config_holder = ConfigLoader.load(allocator, path, AppConfig) catch |err| {
            std.log.err("Failed to load config file: {s}", .{@errorName(err)});
            return err;
        };

        const app_config = parsed_config_holder.?.value;

        // Override host/port from command line if not default
        if (port != 8080) {
            // Command line port takes precedence
        } else {
            port = app_config.server.port;
        }
        if (std.mem.eql(u8, host, "0.0.0.0")) {
            host = app_config.server.host;
        }

        std.log.info("zigQuant API Server v1.0.0", .{});
        std.log.info("Config loaded: {d} exchange(s) configured", .{app_config.exchanges.len});

        // Initialize exchanges from config file
        for (app_config.exchanges) |exchange_cfg| {
            std.log.info("Initializing {s} exchange...", .{exchange_cfg.name});
            std.log.info("  Network: {s}", .{if (exchange_cfg.testnet) "testnet" else "mainnet"});

            if (std.mem.eql(u8, exchange_cfg.name, "hyperliquid")) {
                const hl_config = ExchangeConfig{
                    .name = "hyperliquid",
                    .api_key = exchange_cfg.api_key,
                    .api_secret = exchange_cfg.api_secret,
                    .testnet = exchange_cfg.testnet,
                };

                connectors.hyperliquid = try HyperliquidConnector.create(allocator, hl_config, logger);
                try connectors.hyperliquid.?.interface().connect();

                try deps.addExchange("hyperliquid", connectors.hyperliquid.?.interface(), hl_config);
                exchange_count += 1;
                std.log.info("  ✓ Connected to Hyperliquid", .{});
            }
            // Future: Add more exchanges here (binance, okx, etc.)
        }
    } else {
        // Load from environment variables (legacy mode)
        std.log.info("zigQuant API Server v1.0.0", .{});
        std.log.info("No config file specified, using environment variables", .{});

        // Get global testnet setting
        const testnet_str = std.posix.getenv("ZIGQUANT_TESTNET");
        const testnet = if (testnet_str) |s| !std.mem.eql(u8, s, "false") else true;

        // Hyperliquid from env
        if (std.posix.getenv("ZIGQUANT_HL_USER")) |hl_user| {
            const hl_secret = std.posix.getenv("ZIGQUANT_HL_SECRET");

            std.log.info("Initializing Hyperliquid exchange...", .{});
            std.log.info("  User: {s}", .{hl_user});
            std.log.info("  Network: {s}", .{if (testnet) "testnet" else "mainnet"});

            const hl_config = ExchangeConfig{
                .name = "hyperliquid",
                .api_key = hl_user,
                .api_secret = hl_secret orelse "",
                .testnet = testnet,
            };

            connectors.hyperliquid = try HyperliquidConnector.create(allocator, hl_config, logger);
            try connectors.hyperliquid.?.interface().connect();

            try deps.addExchange("hyperliquid", connectors.hyperliquid.?.interface(), hl_config);
            exchange_count += 1;
            std.log.info("  ✓ Connected to Hyperliquid", .{});
        }
    }

    // Log summary
    if (exchange_count == 0) {
        std.log.info("No exchanges configured, using mock data", .{});
    } else {
        std.log.info("Initialized {d} exchange(s)", .{exchange_count});
    }

    // Create API config
    const api_config = ApiConfig{
        .host = host,
        .port = port,
        .jwt_secret = jwt_secret,
    };

    std.log.info("Starting server on {s}:{d}...", .{ host, port });

    // Initialize and start the server
    const server = try ApiServer.init(allocator, api_config, deps);
    defer server.deinit();

    std.log.info("Server listening on http://{s}:{d}", .{ host, port });
    std.log.info("Health check: http://{s}:{d}/health", .{ host, port });
    std.log.info("API docs: http://{s}:{d}/api/v1/exchanges", .{ host, port });
    std.log.info("Press Ctrl+C to stop", .{});

    try server.start();
}

fn printServeHelp() !void {
    const stdout = std.fs.File.stdout();
    try stdout.writeAll(
        \\
        \\zigQuant serve - Start REST API Server (Multi-Exchange)
        \\
        \\USAGE:
        \\    zigquant serve [OPTIONS]
        \\
        \\OPTIONS:
        \\    -c, --config <FILE>  Configuration file path (JSON format)
        \\    -p, --port <PORT>    Server port (default: 8080, overrides config)
        \\        --host <HOST>    Server host (default: 0.0.0.0, overrides config)
        \\    -h, --help           Show this help message
        \\
        \\CONFIGURATION FILE (recommended):
        \\    Use a JSON config file to configure multiple exchanges:
        \\
        \\    {
        \\      "server": { "host": "0.0.0.0", "port": 8080 },
        \\      "exchanges": [
        \\        {
        \\          "name": "hyperliquid",
        \\          "api_key": "0x...",
        \\          "api_secret": "...",
        \\          "testnet": true
        \\        }
        \\      ],
        \\      "trading": { "max_position_size": 1000, "leverage": 1 },
        \\      "logging": { "level": "info" }
        \\    }
        \\
        \\ENVIRONMENT VARIABLES (legacy mode):
        \\    When no config file is specified, use environment variables:
        \\
        \\    ZIGQUANT_JWT_SECRET      JWT signing secret (required for production)
        \\    ZIGQUANT_TESTNET         Use testnet (default: true)
        \\    ZIGQUANT_HL_USER         Hyperliquid wallet address
        \\    ZIGQUANT_HL_SECRET       Hyperliquid API private key
        \\
        \\    Environment variables can also override config file values.
        \\
        \\API ENDPOINTS:
        \\    GET /api/v1/exchanges           List all connected exchanges
        \\    GET /api/v1/positions           Get positions from all exchanges
        \\    GET /api/v1/positions?exchange=hyperliquid  Filter by exchange
        \\
        \\EXAMPLES:
        \\    zigquant serve -c config.json           # Use config file
        \\    zigquant serve -c config.json -p 3000   # Config + custom port
        \\    zigquant serve                          # Env vars or mock data
        \\    ZIGQUANT_HL_USER=0x... zigquant serve   # Env var mode
        \\
        \\
    );
}

/// Run the Zap-based API server command (v2)
fn runServe2Command(allocator: std.mem.Allocator, args: []const []const u8) !void {
    // Parse serve command arguments
    var port: u16 = 8080;
    var show_help = false;

    var i: usize = 1; // Skip "serve2" command
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--port") or std.mem.eql(u8, arg, "-p")) {
            i += 1;
            if (i < args.len) {
                port = std.fmt.parseInt(u16, args[i], 10) catch {
                    std.debug.print("Invalid port number: {s}\n", .{args[i]});
                    return error.InvalidArgument;
                };
            }
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            show_help = true;
        }
    }

    if (show_help) {
        try printServe2Help();
        return;
    }

    // Get JWT secret from environment or use development default
    const jwt_secret = std.posix.getenv("ZIGQUANT_JWT_SECRET") orelse blk: {
        std.log.warn("ZIGQUANT_JWT_SECRET not set, using development secret", .{});
        std.log.warn("WARNING: Do not use this in production!", .{});
        break :blk DEV_JWT_SECRET;
    };

    // Create Zap server config
    const zap_config = zigQuant.ZapServerConfig{
        .port = port,
        .jwt_secret = jwt_secret,
        .log_requests = true,
    };

    // Create dependencies
    var deps = zigQuant.ZapServerDependencies.init(allocator);

    // Initialize engine manager for grid trading
    var engine_manager = zigQuant.EngineManager.init(allocator);
    defer engine_manager.deinit();
    deps.setEngineManager(&engine_manager);

    std.log.info("Starting zigQuant Zap Server v2.0.0...", .{});
    std.log.info("Engine manager initialized for grid trading", .{});

    // Initialize and start the server
    const server = try zigQuant.ZapServer.init(allocator, zap_config, &deps);
    defer server.deinit();

    try server.start();
}

fn printServe2Help() !void {
    const stdout = std.fs.File.stdout();
    try stdout.writeAll(
        \\
        \\zigQuant serve2 - Start Zap-based REST API Server (v2)
        \\
        \\USAGE:
        \\    zigquant serve2 [OPTIONS]
        \\
        \\OPTIONS:
        \\    -p, --port <PORT>    Server port (default: 8080)
        \\    -h, --help           Show this help message
        \\
        \\ENVIRONMENT VARIABLES:
        \\    ZIGQUANT_JWT_SECRET  JWT signing secret (required for production)
        \\
        \\FEATURES:
        \\    - High-performance Zap/facil.io HTTP server
        \\    - JWT authentication
        \\    - Grid Trading API
        \\    - Health/Ready endpoints
        \\    - Prometheus metrics
        \\
        \\API ENDPOINTS:
        \\    GET  /health                  Health check
        \\    GET  /ready                   Readiness check
        \\    GET  /version                 API version info
        \\    GET  /metrics                 Prometheus metrics
        \\    POST /api/v1/auth/login       Login and get JWT token
        \\    POST /api/v1/auth/refresh     Refresh JWT token
        \\    GET  /api/v1/auth/me          Get current user info
        \\    GET  /api/v1/grid             List all grid bots
        \\    POST /api/v1/grid             Create new grid bot
        \\    GET  /api/v1/grid/:id         Get grid bot details
        \\    DELETE /api/v1/grid/:id       Stop grid bot
        \\    GET  /api/v1/grid/summary     Get grid summary stats
        \\
        \\EXAMPLES:
        \\    zigquant serve2                        # Default port 8080
        \\    zigquant serve2 -p 3000                # Custom port
        \\    ZIGQUANT_JWT_SECRET=... zigquant serve2
        \\
        \\
    );
}
