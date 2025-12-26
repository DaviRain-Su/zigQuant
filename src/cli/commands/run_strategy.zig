//! Run-Strategy Command (Stub)
//!
//! Execute trading strategies in live or paper trading mode.
//! This feature requires Exchange integration from Stories 006-012.
//!
//! Usage (planned):
//! ```bash
//! zigquant run-strategy --strategy dual_ma --config config.json --live
//! ```

const std = @import("std");
const zigQuant = @import("zigQuant");

const Logger = zigQuant.Logger;

pub fn cmdRunStrategy(
    allocator: std.mem.Allocator,
    logger: *Logger,
    args: []const []const u8,
) !void {
    _ = allocator;

    // Check if --live flag is present
    var is_live = false;
    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--live")) {
            is_live = true;
            break;
        }
    }

    try logger.warn("╔════════════════════════════════════════════════════╗", .{});
    try logger.warn("║  Run-Strategy Command - Not Yet Available         ║", .{});
    try logger.warn("╚════════════════════════════════════════════════════╝", .{});
    try logger.info("", .{});

    if (is_live) {
        try logger.err("Live trading is not yet available", .{});
        try logger.info("Exchange integration is in progress (Stories 006-012)", .{});
        try logger.info("", .{});
        try logger.info("Please use the 'backtest' command to test your strategies", .{});
        return error.NotImplemented;
    }

    try logger.warn("Paper trading mode requires WebSocket infrastructure", .{});
    try logger.info("Currently not implemented - please use 'backtest' instead", .{});
    try logger.info("", .{});
    try logger.info("Planned usage:", .{});
    try logger.info("  # Live trading", .{});
    try logger.info("  zigquant run-strategy --strategy dual_ma --config config.json --live", .{});
    try logger.info("", .{});
    try logger.info("  # Paper trading", .{});
    try logger.info("  zigquant run-strategy --strategy dual_ma --config config.json --paper", .{});
    try logger.info("", .{});
    try logger.info("Features:", .{});
    try logger.info("  - Real-time WebSocket market data", .{});
    try logger.info("  - Asynchronous order execution", .{});
    try logger.info("  - Live P&L tracking", .{});
    try logger.info("  - Risk management and position limits", .{});
    try logger.info("  - Performance powered by libxev (v0.4.0)", .{});
}
