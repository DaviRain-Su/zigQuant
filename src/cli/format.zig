//! CLI Output Formatting - 彩色输出和表格格式化
//!
//! 提供 CLI 友好的输出格式化功能：
//! - ANSI 颜色代码
//! - 表格格式化
//! - 数字格式化

const std = @import("std");

// ============================================================================
// ANSI Color Codes
// ============================================================================

pub const Color = enum {
    reset,
    red,
    green,
    yellow,
    blue,
    magenta,
    cyan,
    white,
    gray,
    bright_red,
    bright_green,
    bright_yellow,

    pub fn code(self: Color) []const u8 {
        return switch (self) {
            .reset => "\x1b[0m",
            .red => "\x1b[31m",
            .green => "\x1b[32m",
            .yellow => "\x1b[33m",
            .blue => "\x1b[34m",
            .magenta => "\x1b[35m",
            .cyan => "\x1b[36m",
            .white => "\x1b[37m",
            .gray => "\x1b[90m",
            .bright_red => "\x1b[91m",
            .bright_green => "\x1b[92m",
            .bright_yellow => "\x1b[93m",
        };
    }
};

// ============================================================================
// Colored Output
// ============================================================================

/// Print colored text to stdout
pub fn printColored(writer: anytype, color: Color, comptime fmt: []const u8, args: anytype) !void {
    try writer.writeAll(color.code());
    try writer.print(fmt, args);
    try writer.writeAll(Color.reset.code());
}

/// Print colored line to stdout (with newline)
pub fn printColoredLine(writer: anytype, color: Color, comptime fmt: []const u8, args: anytype) !void {
    try printColored(writer, color, fmt, args);
    try writer.writeAll("\n");
}

// ============================================================================
// Formatting Helpers
// ============================================================================

/// Format float as price with 2 decimal places
pub fn formatPrice(allocator: std.mem.Allocator, price: f64) ![]const u8 {
    return try std.fmt.allocPrint(allocator, "{d:.2}", .{price});
}

/// Format float as quantity with 6 decimal places
pub fn formatQuantity(allocator: std.mem.Allocator, qty: f64) ![]const u8 {
    return try std.fmt.allocPrint(allocator, "{d:.6}", .{qty});
}

/// Format float as percentage
pub fn formatPercentage(allocator: std.mem.Allocator, value: f64) ![]const u8 {
    const value_pct = value * 100.0;
    return try std.fmt.allocPrint(allocator, "{d:.2}%", .{value_pct});
}

// ============================================================================
// Box Drawing
// ============================================================================

/// Print a header box
pub fn printHeader(writer: anytype, title: []const u8) !void {
    const line_len = title.len + 4;

    try writer.writeAll("\n");
    try printColored(writer, .cyan, "╔", .{});
    for (0..line_len) |_| {
        try printColored(writer, .cyan, "═", .{});
    }
    try printColoredLine(writer, .cyan, "╗", .{});

    try printColored(writer, .cyan, "║ ", .{});
    try printColored(writer, .bright_yellow, "{s}", .{title});
    try printColoredLine(writer, .cyan, " ║", .{});

    try printColored(writer, .cyan, "╚", .{});
    for (0..line_len) |_| {
        try printColored(writer, .cyan, "═", .{});
    }
    try printColoredLine(writer, .cyan, "╝", .{});
    try writer.writeAll("\n");
}

/// Print a section separator
pub fn printSeparator(writer: anytype) !void {
    try printColoredLine(writer, .gray, "────────────────────────────────────────", .{});
}

// ============================================================================
// Status Messages
// ============================================================================

/// Print success message
pub fn printSuccess(writer: anytype, comptime fmt: []const u8, args: anytype) !void {
    try printColored(writer, .green, "✓ ", .{});
    try writer.print(fmt, args);
    try writer.writeAll("\n");
}

/// Print error message
pub fn printError(writer: anytype, comptime fmt: []const u8, args: anytype) !void {
    try printColored(writer, .red, "✗ Error: ", .{});
    try writer.print(fmt, args);
    try writer.writeAll("\n");
}

/// Print warning message
pub fn printWarning(writer: anytype, comptime fmt: []const u8, args: anytype) !void {
    try printColored(writer, .yellow, "⚠ Warning: ", .{});
    try writer.print(fmt, args);
    try writer.writeAll("\n");
}

/// Print info message
pub fn printInfo(writer: anytype, comptime fmt: []const u8, args: anytype) !void {
    try printColored(writer, .blue, "ℹ ", .{});
    try writer.print(fmt, args);
    try writer.writeAll("\n");
}

// ============================================================================
// Simple Table
// ============================================================================

pub const TableColumn = struct {
    header: []const u8,
    width: usize,
    alignment: Alignment = .left,

    pub const Alignment = enum {
        left,
        right,
        center,
    };
};

pub fn Table(comptime columns: []const TableColumn, comptime WriterType: type) type {
    return struct {
        const Self = @This();

        writer: WriterType,

        pub fn init(writer: WriterType) Self {
            return .{ .writer = writer };
        }

        pub fn printHeader(self: *Self) !void {
            // Top border
            try self.writer.writeAll("┌");
            for (columns, 0..) |col, i| {
                for (0..col.width + 2) |_| {
                    try self.writer.writeAll("─");
                }
                if (i < columns.len - 1) {
                    try self.writer.writeAll("┬");
                }
            }
            try self.writer.writeAll("┐\n");

            // Header row
            try self.writer.writeAll("│");
            for (columns) |col| {
                try self.writer.writeAll(" ");
                try printColored(self.writer, .bright_yellow, "{s}", .{col.header});
                const padding = col.width - col.header.len;
                for (0..padding) |_| {
                    try self.writer.writeAll(" ");
                }
                try self.writer.writeAll(" │");
            }
            try self.writer.writeAll("\n");

            // Header separator
            try self.writer.writeAll("├");
            for (columns, 0..) |col, i| {
                for (0..col.width + 2) |_| {
                    try self.writer.writeAll("─");
                }
                if (i < columns.len - 1) {
                    try self.writer.writeAll("┼");
                }
            }
            try self.writer.writeAll("┤\n");
        }

        pub fn printRow(self: *Self, values: [columns.len][]const u8) !void {
            try self.writer.writeAll("│");
            for (columns, 0..) |col, i| {
                try self.writer.writeAll(" ");
                const value = values[i];
                const padding = if (value.len < col.width) col.width - value.len else 0;

                switch (col.alignment) {
                    .left => {
                        try self.writer.writeAll(value);
                        for (0..padding) |_| {
                            try self.writer.writeAll(" ");
                        }
                    },
                    .right => {
                        for (0..padding) |_| {
                            try self.writer.writeAll(" ");
                        }
                        try self.writer.writeAll(value);
                    },
                    .center => {
                        const left_pad = padding / 2;
                        for (0..left_pad) |_| {
                            try self.writer.writeAll(" ");
                        }
                        try self.writer.writeAll(value);
                        for (0..padding - left_pad) |_| {
                            try self.writer.writeAll(" ");
                        }
                    },
                }

                try self.writer.writeAll(" │");
            }
            try self.writer.writeAll("\n");
        }

        pub fn printFooter(self: *Self) !void {
            try self.writer.writeAll("└");
            for (columns, 0..) |col, i| {
                for (0..col.width + 2) |_| {
                    try self.writer.writeAll("─");
                }
                if (i < columns.len - 1) {
                    try self.writer.writeAll("┴");
                }
            }
            try self.writer.writeAll("┘\n");
        }
    };
}

// ============================================================================
// Tests
// ============================================================================

test "Color codes" {
    try std.testing.expectEqualStrings("\x1b[31m", Color.red.code());
    try std.testing.expectEqualStrings("\x1b[0m", Color.reset.code());
}

test "formatPrice" {
    const allocator = std.testing.allocator;
    const price: f64 = 1234.567;
    const formatted = try formatPrice(allocator, price);
    defer allocator.free(formatted);
    try std.testing.expectEqualStrings("1234.57", formatted);
}
