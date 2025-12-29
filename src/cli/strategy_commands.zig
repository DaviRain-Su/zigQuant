//! Strategy Commands Dispatcher
//!
//! Routes strategy-related commands to their implementations.
//!
//! Supported commands:
//! - backtest - Run strategy backtests
//! - optimize - Parameter optimization (stub)
//! - run-strategy - Live/paper trading (stub)
//! - grid - Grid trading bot (paper/testnet/live)
//! - live - Live trading with configurable strategy (config file only)

const std = @import("std");
const zigQuant = @import("zigQuant");
const backtest = @import("commands/backtest.zig");
const optimize = @import("commands/optimize.zig");
const run_strategy = @import("commands/run_strategy.zig");
const grid = @import("commands/grid.zig");
const live = @import("commands/live.zig");

const Logger = zigQuant.Logger;

pub fn executeStrategyCommand(
    allocator: std.mem.Allocator,
    logger: *Logger,
    command: []const u8,
    args: []const []const u8,
) !void {
    // Skip the command name itself - only pass the options/flags to the command handlers
    const command_args = if (args.len > 1) args[1..] else &[_][]const u8{};

    if (std.mem.eql(u8, command, "backtest")) {
        try backtest.cmdBacktest(allocator, logger, command_args);
    } else if (std.mem.eql(u8, command, "optimize")) {
        try optimize.cmdOptimize(allocator, logger, command_args);
    } else if (std.mem.eql(u8, command, "run-strategy")) {
        try run_strategy.cmdRunStrategy(allocator, logger, command_args);
    } else if (std.mem.eql(u8, command, "grid")) {
        try grid.cmdGrid(allocator, logger, command_args);
    } else if (std.mem.eql(u8, command, "live")) {
        try live.cmdLive(allocator, logger, command_args);
    } else {
        try logger.err("Unknown strategy command: {s}", .{command});
        try logger.info("", .{});
        try printStrategyHelp(logger);
        return error.UnknownCommand;
    }
}

pub fn isStrategyCommand(command: []const u8) bool {
    return std.mem.eql(u8, command, "backtest") or
        std.mem.eql(u8, command, "optimize") or
        std.mem.eql(u8, command, "run-strategy") or
        std.mem.eql(u8, command, "grid") or
        std.mem.eql(u8, command, "live");
}

fn printStrategyHelp(logger: *Logger) !void {
    try logger.info("Available strategy commands:", .{});
    try logger.info("  backtest       - Run strategy backtests", .{});
    try logger.info("  optimize       - Parameter optimization (coming soon)", .{});
    try logger.info("  run-strategy   - Live/paper trading (coming soon)", .{});
    try logger.info("  grid           - Grid trading bot (paper/testnet/live)", .{});
    try logger.info("  live           - Live trading with configurable strategy", .{});
    try logger.info("", .{});
    try logger.info("Use 'zigquant <command> --help' for command-specific help", .{});
}
