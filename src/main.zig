//! zigQuant CLI - Main Entry Point

const std = @import("std");
const zigQuant = @import("zigQuant");
const CLI = @import("cli/cli.zig").CLI;
const format = @import("cli/format.zig");
const strategy_commands = @import("cli/strategy_commands.zig");

const Logger = zigQuant.Logger;
const ConsoleWriter = zigQuant.ConsoleWriter;

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

    // Check if it's the serve command (Zap-based API server)
    if (std.mem.eql(u8, command, "serve")) {
        try runServeCommand(allocator, cli_args);
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
        \\INTERFACE COMMANDS:
        \\    serve            Start REST API server (Zap/facil.io)
        \\
        \\STRATEGY COMMANDS:
        \\    backtest         Run strategy backtests
        \\    optimize         Parameter optimization (coming soon)
        \\    run-strategy     Live/paper trading (coming soon)
        \\    grid             Grid trading bot (paper/testnet/live)
        \\    live             Live trading with configurable strategy
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
        \\    zigquant serve -p 8080                  # Start API server
        \\    zigquant backtest --strategy dual_ma --config config.json --data btc.csv
        \\    zigquant price BTC-USDC
        \\    zigquant balance
        \\
        \\Use 'zigquant <COMMAND> --help' for command-specific help
        \\
        \\
    );
}

/// Run the Zap-based API server command
fn runServeCommand(allocator: std.mem.Allocator, args: []const []const u8) !void {
    // Parse serve command arguments
    var port: u16 = 8080;
    var show_help = false;
    var config_path: []const u8 = "config.json";

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

    // Load application config from file
    const app_config = zigQuant.ConfigLoader.load(allocator, config_path, zigQuant.AppConfig) catch |err| blk: {
        std.log.warn("Failed to load config from {s}: {}, using defaults", .{ config_path, err });
        break :blk null;
    };
    defer if (app_config) |cfg| cfg.deinit();

    // Extract Hyperliquid config if available
    var exchange_wallet: ?[]const u8 = null;
    var exchange_secret: ?[]const u8 = null;
    var exchange_testnet: bool = true;

    if (app_config) |cfg| {
        if (cfg.value.getExchange("hyperliquid")) |hl_config| {
            exchange_wallet = hl_config.api_key;
            exchange_secret = hl_config.api_secret;
            exchange_testnet = hl_config.testnet;
            std.log.info("Loaded Hyperliquid config: wallet={s}..., testnet={}", .{
                if (exchange_wallet.?.len > 10) exchange_wallet.?[0..10] else exchange_wallet.?,
                exchange_testnet,
            });
        }
        // Override port from config if not specified on command line
        if (port == 8080 and cfg.value.server.port != 8080) {
            port = cfg.value.server.port;
        }
    }

    // Get JWT secret from config file
    const jwt_secret: []const u8 = if (app_config) |cfg| cfg.value.security.jwt_secret else blk: {
        std.log.warn("No config loaded, using development JWT secret", .{});
        std.log.warn("WARNING: Do not use this in production!", .{});
        break :blk "zigquant-dev-secret-key-32bytes!";
    };

    // Create Zap server config
    const zap_config = zigQuant.ZapServerConfig{
        .port = port,
        .jwt_secret = jwt_secret,
        .log_requests = true,
    };

    // Create dependencies
    var deps = zigQuant.ZapServerDependencies.init(allocator);

    // Store exchange config in dependencies for live trading
    deps.exchange_wallet = exchange_wallet;
    deps.exchange_secret = exchange_secret;
    deps.exchange_testnet = exchange_testnet;

    // Initialize global log buffer for web UI log viewer
    const log_buffer: ?*zigQuant.LogBuffer = zigQuant.log_buffer.initGlobalBuffer(allocator, 1000) catch |err| blk: {
        std.log.warn("Failed to initialize log buffer: {}, log viewer will be unavailable", .{err});
        break :blk null;
    };
    defer if (log_buffer != null) zigQuant.log_buffer.deinitGlobalBuffer();

    // Initialize engine manager for grid trading
    var engine_manager = zigQuant.EngineManager.init(allocator);
    defer engine_manager.deinit();
    deps.setEngineManager(&engine_manager);

    std.log.info("Starting zigQuant API Server...", .{});
    std.log.info("Engine manager initialized for grid trading", .{});
    if (log_buffer != null) {
        std.log.info("Log buffer initialized with 1000 entry capacity", .{});
    }
    if (exchange_wallet != null) {
        std.log.info("Hyperliquid exchange configured (testnet={})", .{exchange_testnet});
    }

    // Initialize and start the server
    const server = try zigQuant.ZapServer.init(allocator, zap_config, &deps);
    defer server.deinit();

    try server.start();

    // When server.start() returns (after Ctrl+C), begin graceful shutdown
    std.log.info("", .{});
    std.log.info("Received shutdown signal, cleaning up...", .{});

    // Stop all live trading sessions first
    std.log.info("Stopping all live trading sessions...", .{});
    const live_stopped = engine_manager.stopAllLive();
    if (live_stopped > 0) {
        std.log.info("Stopped {d} live trading session(s)", .{live_stopped});
    }

    // Stop all strategy runners
    std.log.info("Stopping all strategies...", .{});
    const strategies_stopped = engine_manager.stopAllStrategies();
    if (strategies_stopped > 0) {
        std.log.info("Stopped {d} strategy session(s)", .{strategies_stopped});
    }

    std.log.info("Shutdown complete. Goodbye!", .{});
}

fn printServeHelp() !void {
    const stdout = std.fs.File.stdout();
    try stdout.writeAll(
        \\
        \\zigQuant serve - Start REST API Server
        \\
        \\USAGE:
        \\    zigquant serve [OPTIONS]
        \\
        \\OPTIONS:
        \\    -c, --config <FILE>  Config file path (default: config.json)
        \\    -p, --port <PORT>    Server port (default: 8080, or from config)
        \\    -h, --help           Show this help message
        \\
        \\CONFIG FILE:
        \\    All settings are read from config file:
        \\    - server.port: Server port
        \\    - security.jwt_secret: JWT signing secret
        \\    - exchanges: Exchange credentials
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
        \\    zigquant serve                          # Default config.json
        \\    zigquant serve -c prod.json             # Custom config
        \\    zigquant serve -c config.json -p 3000   # Override port
        \\
        \\
    );
}
