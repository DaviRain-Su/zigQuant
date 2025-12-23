const std = @import("std");
const zigQuant = @import("zigQuant");

// Configure std.log to use our custom logger
var logger_instance: zigQuant.Logger = undefined;

pub const std_options = .{
    .logFn = zigQuant.StdLogWriter.logFn,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    var stderr_buffer: [4096]u8 = undefined;
    var stderr_writer = std.fs.File.stderr().writer(&stderr_buffer);

    // Create a console writer
    var console = zigQuant.ConsoleWriter.init(&stderr_writer.interface);
    defer console.deinit();

    // Initialize our logger
    logger_instance = zigQuant.Logger.init(allocator, console.writer(), .debug);
    defer logger_instance.deinit();

    // Set the global logger for StdLogWriter
    zigQuant.StdLogWriter.setLogger(&logger_instance);

    // Now you can use std.log as usual, and it will route through our Logger!
    std.log.debug("Application starting...", .{});
    std.log.info("Server listening on port {}", .{8080});

    // Using scoped logging
    const db_log = std.log.scoped(.database);
    db_log.info("Connection pool initialized", .{});

    const network_log = std.log.scoped(.network);
    network_log.warn("High latency detected: {} ms", .{150});

    // Error logging
    std.log.err("Failed to connect to API: {s}", .{"timeout"});

    std.log.info("Shutdown complete", .{});
}
