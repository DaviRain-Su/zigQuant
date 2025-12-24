//! zigQuant CLI - Main Entry Point

const std = @import("std");
const CLI = @import("cli/cli.zig").CLI;
const format = @import("cli/format.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse command line arguments
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // Skip program name
    const cli_args = if (args.len > 1) args[1..] else &[_][]const u8{};

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
        var stderr_buffer: [4096]u8 = undefined;
        var stderr = std.fs.File.stderr().writer(&stderr_buffer);
        try format.printError(&stderr.interface, "Failed to initialize: {s}", .{@errorName(err)});
        std.process.exit(1);
    };
    defer cli.deinit();

    // Connect to exchange
    cli.connect() catch |err| {
        try format.printError(&cli.stderr.interface, "Failed to connect: {s}", .{@errorName(err)});
        std.process.exit(1);
    };

    // Execute command or show help
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
