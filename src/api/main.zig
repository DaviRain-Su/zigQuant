//! zigQuant API Server
//!
//! Standalone REST API server for zigQuant trading platform.
//! This is a separate executable to avoid dependency conflicts with the main CLI.

const std = @import("std");
const httpz = @import("httpz");

const config_mod = @import("config.zig");
const ApiConfig = config_mod.ApiConfig;
const ApiDependencies = config_mod.ApiDependencies;
const ApiServer = @import("server.zig").ApiServer;

/// Default development JWT secret (32 bytes)
/// WARNING: Never use this in production!
const DEV_JWT_SECRET = "zigquant-dev-secret-key-32bytes!";

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse command line arguments
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // Get JWT secret from environment or use development default
    const jwt_secret = std.posix.getenv("ZIGQUANT_JWT_SECRET") orelse blk: {
        std.log.warn("ZIGQUANT_JWT_SECRET not set, using development secret", .{});
        std.log.warn("WARNING: Do not use this in production!", .{});
        break :blk DEV_JWT_SECRET;
    };

    // Default configuration with JWT secret
    var config = ApiConfig{
        .jwt_secret = jwt_secret,
    };

    // Parse arguments
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--port") or std.mem.eql(u8, arg, "-p")) {
            i += 1;
            if (i < args.len) {
                config.port = std.fmt.parseInt(u16, args[i], 10) catch {
                    std.log.err("Invalid port number: {s}", .{args[i]});
                    return error.InvalidArgument;
                };
            }
        } else if (std.mem.eql(u8, arg, "--host") or std.mem.eql(u8, arg, "-h")) {
            i += 1;
            if (i < args.len) {
                config.host = args[i];
            }
        } else if (std.mem.eql(u8, arg, "--help")) {
            printHelp();
            return;
        }
    }

    std.log.info("zigQuant API Server v{s}", .{@import("mod.zig").version});
    std.log.info("Starting server on {s}:{d}...", .{ config.host, config.port });

    // Create dependencies (placeholder for now)
    const deps = ApiDependencies{};

    // Initialize and start the server
    const server = try ApiServer.init(allocator, config, deps);
    defer server.deinit();

    std.log.info("Server listening on http://{s}:{d}", .{ config.host, config.port });
    std.log.info("Health check: http://{s}:{d}/health", .{ config.host, config.port });
    std.log.info("Press Ctrl+C to stop", .{});

    try server.start();
}

fn printHelp() void {
    const help =
        \\zigQuant API Server
        \\
        \\Usage: zigquant-api [OPTIONS]
        \\
        \\Options:
        \\  -p, --port <PORT>    Server port (default: 8080)
        \\  -h, --host <HOST>    Server host (default: 0.0.0.0)
        \\      --help           Show this help message
        \\
        \\Examples:
        \\  zigquant-api                    # Start on default port 8080
        \\  zigquant-api --port 3000        # Start on port 3000
        \\  zigquant-api -h 127.0.0.1       # Listen only on localhost
        \\
    ;
    std.debug.print("{s}", .{help});
}
