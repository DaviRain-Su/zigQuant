//! REPL - Read-Eval-Print Loop
//!
//! 交互式命令行界面

const std = @import("std");
const CLI = @import("cli.zig").CLI;
const format = @import("format.zig");

pub fn run(cli: *CLI) !void {
    const stdin_file = std.fs.File.stdin();

    try format.printHeader(&cli.stdout.interface, "zigQuant REPL");
    try (&cli.stdout.interface).writeAll("Type 'help' for commands, 'exit' to quit\n\n");

    var buffer: [1024]u8 = undefined;
    var buf_pos: usize = 0;
    var arena = std.heap.ArenaAllocator.init(cli.allocator);
    defer arena.deinit();

    while (true) {
        _ = arena.reset(.retain_capacity);
        const arena_alloc = arena.allocator();

        // Prompt
        try format.printColored(&cli.stdout.interface, .bright_yellow, "zigquant> ", .{});

        // Read line character by character
        buf_pos = 0;
        while (buf_pos < buffer.len) {
            const n = try stdin_file.read(buffer[buf_pos .. buf_pos + 1]);
            if (n == 0) break; // EOF
            if (buffer[buf_pos] == '\n') break;
            buf_pos += 1;
        }
        if (buf_pos == 0) break; // EOF with no input
        const line = buffer[0..buf_pos];
        const trimmed = std.mem.trim(u8, line, &std.ascii.whitespace);

        if (trimmed.len == 0) continue;

        // Check for exit
        if (std.mem.eql(u8, trimmed, "exit") or std.mem.eql(u8, trimmed, "quit")) {
            break;
        }

        // Parse command
        const ArgsList = std.ArrayList([]const u8);
        var args = ArgsList{};
        try args.ensureTotalCapacity(arena_alloc, 16);
        var iter = std.mem.tokenizeAny(u8, trimmed, &std.ascii.whitespace);
        while (iter.next()) |arg| {
            try args.append(arena_alloc, arg);
        }

        if (args.items.len == 0) continue;

        // Execute command
        cli.executeCommand(args.items) catch {};
    }

    try (&cli.stdout.interface).writeAll("\n");
    try format.printSuccess(&cli.stdout.interface, "Goodbye!", .{});
}
