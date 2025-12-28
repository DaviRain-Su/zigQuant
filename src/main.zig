//! zigQuant CLI - Main Entry Point

const std = @import("std");
const zigQuant = @import("zigQuant");
const CLI = @import("cli/cli.zig").CLI;
const format = @import("cli/format.zig");
const strategy_commands = @import("cli/strategy_commands.zig");

// API Server imports (direct import to avoid websocket module conflicts)
const api = @import("api/mod.zig");
const ApiServer = api.Server;
const ApiConfig = api.Config;
const ApiDependencies = api.Dependencies;
const HyperliquidConnector = zigQuant.HyperliquidConnector;
const ExchangeConfig = zigQuant.ExchangeConfig;

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
        \\    serve            Start REST API server
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

/// Run the API server command
fn runServeCommand(allocator: std.mem.Allocator, args: []const []const u8) !void {
    // Parse serve command arguments
    var port: u16 = 8080;
    var host: []const u8 = "0.0.0.0";
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
        } else if (std.mem.eql(u8, arg, "--host") or std.mem.eql(u8, arg, "-h")) {
            i += 1;
            if (i < args.len) {
                host = args[i];
            }
        } else if (std.mem.eql(u8, arg, "--help")) {
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

    // Get exchange configuration from environment
    const hl_user = std.posix.getenv("ZIGQUANT_HL_USER");
    const hl_secret = std.posix.getenv("ZIGQUANT_HL_SECRET");
    const testnet_str = std.posix.getenv("ZIGQUANT_TESTNET");
    const testnet = if (testnet_str) |s| !std.mem.eql(u8, s, "false") else true;

    // Create API config
    const config = ApiConfig{
        .host = host,
        .port = port,
        .jwt_secret = jwt_secret,
    };

    std.log.info("zigQuant API Server v{s}", .{api.version});
    std.log.info("Starting server on {s}:{d}...", .{host, port});

    // Create logger for exchange connector
    const ConsoleWriterType = ConsoleWriter(std.fs.File);
    var console = ConsoleWriterType.initWithColors(allocator, std.fs.File.stdout(), true);
    defer console.deinit();
    var logger = Logger.init(allocator, console.writer(), .info);
    defer logger.deinit();

    // Create dependencies
    var deps = ApiDependencies{};

    // Initialize exchange connector if credentials are provided
    var connector: ?*HyperliquidConnector = null;
    defer if (connector) |c| c.destroy();

    if (hl_user) |user| {
        std.log.info("Hyperliquid user configured: {s}", .{user});
        std.log.info("Network: {s}", .{if (testnet) "testnet" else "mainnet"});

        const exchange_config = ExchangeConfig{
            .name = "hyperliquid",
            .api_key = user,
            .api_secret = hl_secret orelse "",
            .testnet = testnet,
        };

        // Create Hyperliquid connector
        connector = try HyperliquidConnector.create(allocator, exchange_config, logger);

        // Connect to exchange
        try connector.?.interface().connect();
        std.log.info("Connected to Hyperliquid exchange", .{});

        // Set up dependencies with the exchange interface
        deps.exchange = connector.?.interface();
        deps.exchange_config = exchange_config;
    } else {
        std.log.info("No exchange configured, using mock data", .{});
    }

    // Initialize and start the server
    const server = try ApiServer.init(allocator, config, deps);
    defer server.deinit();

    std.log.info("Server listening on http://{s}:{d}", .{host, port});
    std.log.info("Health check: http://{s}:{d}/health", .{host, port});
    std.log.info("Press Ctrl+C to stop", .{});

    try server.start();
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
        \\    -p, --port <PORT>    Server port (default: 8080)
        \\    -h, --host <HOST>    Server host (default: 0.0.0.0)
        \\        --help           Show this help message
        \\
        \\ENVIRONMENT VARIABLES:
        \\    ZIGQUANT_JWT_SECRET      JWT signing secret (required for production)
        \\    ZIGQUANT_HL_USER         Hyperliquid wallet address (main account)
        \\    ZIGQUANT_HL_SECRET       Hyperliquid API wallet private key (optional)
        \\    ZIGQUANT_TESTNET         Use testnet (default: true, set to "false" for mainnet)
        \\
        \\EXAMPLES:
        \\    zigquant serve                          # Start on default port 8080
        \\    zigquant serve --port 3000              # Start on port 3000
        \\    ZIGQUANT_HL_USER=0x... zigquant serve   # With Hyperliquid account
        \\
        \\
    );
}
