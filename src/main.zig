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

    // Check if it's a strategy command (backtest, optimize, run-strategy)
    if (strategy_commands.isStrategyCommand(command)) {
        // Strategy commands don't need exchange connection
        // They use a simple logger instead of full CLI
        var log_buf: [4096]u8 = undefined;
        var fbs = std.io.fixedBufferStream(&log_buf);
        const WriterType = @TypeOf(fbs.writer());
        var console = ConsoleWriter(WriterType).initWithColors(allocator, fbs.writer(), true);
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
            std.process.exit(1);
        };

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
