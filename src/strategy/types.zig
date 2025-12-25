//! Strategy Types
//!
//! This module defines the core types used for strategy configuration and metadata.
//! These types provide runtime configuration, parameter validation, and strategy
//! identification.
//!
//! Design principles:
//! - Type-safe configuration with compile-time validation
//! - Flexible parameter system for strategy tuning
//! - Clear metadata for strategy identification
//! - Memory-efficient with minimal allocations

const std = @import("std");
const Decimal = @import("../root.zig").Decimal;
const Timeframe = @import("../root.zig").Timeframe;
const TradingPair = @import("../root.zig").TradingPair;

// ============================================================================
// Strategy Metadata
// ============================================================================

/// Strategy metadata
/// Provides identification and description information for a strategy
pub const StrategyMetadata = struct {
    /// Strategy name (e.g., "SMA Crossover")
    name: []const u8,

    /// Strategy version (semantic versioning)
    version: []const u8,

    /// Strategy author
    author: []const u8,

    /// Brief description of strategy logic
    description: []const u8,

    /// Validate metadata fields
    pub fn validate(self: StrategyMetadata) !void {
        if (self.name.len == 0) {
            return error.EmptyStrategyName;
        }
        if (self.version.len == 0) {
            return error.EmptyStrategyVersion;
        }
    }

    /// Check if metadata is valid
    pub fn isValid(self: StrategyMetadata) bool {
        return self.name.len > 0 and self.version.len > 0;
    }
};

// ============================================================================
// Strategy Parameters
// ============================================================================

/// Parameter type for strategy configuration
pub const ParameterType = enum {
    integer, // Integer parameter (period, lookback, etc.)
    decimal, // Decimal parameter (threshold, multiplier, etc.)
    boolean, // Boolean flag
    string, // String parameter

    /// Convert to string representation
    pub fn toString(self: ParameterType) []const u8 {
        return switch (self) {
            .integer => "integer",
            .decimal => "decimal",
            .boolean => "boolean",
            .string => "string",
        };
    }
};

/// Parameter value union
pub const ParameterValue = union(ParameterType) {
    integer: i64,
    decimal: Decimal,
    boolean: bool,
    string: []const u8,

    /// Get integer value
    pub fn asInteger(self: ParameterValue) ?i64 {
        return switch (self) {
            .integer => |v| v,
            else => null,
        };
    }

    /// Get decimal value
    pub fn asDecimal(self: ParameterValue) ?Decimal {
        return switch (self) {
            .decimal => |v| v,
            else => null,
        };
    }

    /// Get boolean value
    pub fn asBoolean(self: ParameterValue) ?bool {
        return switch (self) {
            .boolean => |v| v,
            else => null,
        };
    }

    /// Get string value
    pub fn asString(self: ParameterValue) ?[]const u8 {
        return switch (self) {
            .string => |v| v,
            else => null,
        };
    }
};

/// Strategy parameter definition
pub const StrategyParameter = struct {
    /// Parameter name (e.g., "fast_period")
    name: []const u8,

    /// Parameter description
    description: []const u8,

    /// Parameter value
    value: ParameterValue,

    /// Validate parameter
    pub fn validate(self: StrategyParameter) !void {
        if (self.name.len == 0) {
            return error.EmptyParameterName;
        }
    }

    /// Check if parameter is valid
    pub fn isValid(self: StrategyParameter) bool {
        return self.name.len > 0;
    }
};

// ============================================================================
// ROI Configuration
// ============================================================================

/// Minimal ROI configuration
/// Defines profit-taking targets at different time intervals
pub const MinimalROI = struct {
    /// Time offset in minutes from entry
    minutes: u32,

    /// Target ROI as percentage (e.g., 0.01 = 1%)
    roi_percent: Decimal,

    /// Validate ROI configuration
    pub fn validate(self: MinimalROI) !void {
        if (self.roi_percent.isNegative()) {
            return error.NegativeROI;
        }
    }

    /// Check if ROI is valid
    pub fn isValid(self: MinimalROI) bool {
        return !self.roi_percent.isNegative();
    }
};

// ============================================================================
// Trailing Stop Configuration
// ============================================================================

/// Trailing stop configuration
/// Defines how stop loss trails the price as profit increases
pub const TrailingStopConfig = struct {
    /// Activate trailing stop when profit reaches this percentage
    activate_percent: Decimal,

    /// Stop loss offset from peak (as percentage)
    offset_percent: Decimal,

    /// Validate trailing stop configuration
    pub fn validate(self: TrailingStopConfig) !void {
        if (self.activate_percent.isNegative()) {
            return error.NegativeActivatePercent;
        }
        if (self.offset_percent.isNegative()) {
            return error.NegativeOffsetPercent;
        }
        // Offset should be less than activation threshold
        if (self.offset_percent.cmp(self.activate_percent) == .gt) {
            return error.OffsetExceedsActivation;
        }
    }

    /// Check if configuration is valid
    pub fn isValid(self: TrailingStopConfig) bool {
        return !self.activate_percent.isNegative() and
            !self.offset_percent.isNegative() and
            self.offset_percent.cmp(self.activate_percent) != .gt;
    }
};

// ============================================================================
// Strategy Configuration
// ============================================================================

/// Strategy configuration
/// Complete configuration for a strategy instance
pub const StrategyConfig = struct {
    /// Strategy metadata
    metadata: StrategyMetadata,

    /// Trading pair to operate on
    pair: TradingPair,

    /// Timeframe for analysis
    timeframe: Timeframe,

    /// Strategy parameters
    parameters: []const StrategyParameter,

    /// Optional minimal ROI targets
    minimal_roi: ?[]const MinimalROI,

    /// Optional trailing stop configuration
    trailing_stop: ?TrailingStopConfig,

    /// Risk management configuration
    max_open_trades: u32, // Maximum number of concurrent positions
    stake_amount: Decimal, // Amount to stake per position

    /// Allocator for memory management
    allocator: std.mem.Allocator,

    /// Initialize strategy configuration
    pub fn init(
        allocator: std.mem.Allocator,
        metadata: StrategyMetadata,
        pair: TradingPair,
        timeframe: Timeframe,
        parameters: []const StrategyParameter,
        minimal_roi: ?[]const MinimalROI,
        trailing_stop: ?TrailingStopConfig,
        max_open_trades: u32,
        stake_amount: Decimal,
    ) !StrategyConfig {
        // Validate metadata
        try metadata.validate();

        // Validate parameters
        for (parameters) |param| {
            try param.validate();
        }

        // Validate minimal ROI if provided
        if (minimal_roi) |roi_list| {
            for (roi_list) |roi| {
                try roi.validate();
            }
        }

        // Validate trailing stop if provided
        if (trailing_stop) |ts| {
            try ts.validate();
        }

        // Copy parameters
        const params_copy = try allocator.dupe(StrategyParameter, parameters);
        errdefer allocator.free(params_copy);

        // Copy minimal ROI if provided
        var roi_copy: ?[]const MinimalROI = null;
        if (minimal_roi) |roi_list| {
            roi_copy = try allocator.dupe(MinimalROI, roi_list);
        }

        return StrategyConfig{
            .metadata = metadata,
            .pair = pair,
            .timeframe = timeframe,
            .parameters = params_copy,
            .minimal_roi = roi_copy,
            .trailing_stop = trailing_stop,
            .max_open_trades = max_open_trades,
            .stake_amount = stake_amount,
            .allocator = allocator,
        };
    }

    /// Free allocated memory
    pub fn deinit(self: StrategyConfig) void {
        self.allocator.free(self.parameters);
        if (self.minimal_roi) |roi| {
            self.allocator.free(roi);
        }
    }

    /// Get parameter by name
    pub fn getParameter(self: StrategyConfig, name: []const u8) ?StrategyParameter {
        for (self.parameters) |param| {
            if (std.mem.eql(u8, param.name, name)) {
                return param;
            }
        }
        return null;
    }

    /// Check if parameter exists
    pub fn hasParameter(self: StrategyConfig, name: []const u8) bool {
        return self.getParameter(name) != null;
    }

    /// Validate entire configuration
    pub fn validate(self: StrategyConfig) !void {
        try self.metadata.validate();

        for (self.parameters) |param| {
            try param.validate();
        }

        if (self.minimal_roi) |roi_list| {
            for (roi_list) |roi| {
                try roi.validate();
            }
        }

        if (self.trailing_stop) |ts| {
            try ts.validate();
        }
    }
};

// ============================================================================
// Tests
// ============================================================================

test "StrategyMetadata: validation" {
    const valid = StrategyMetadata{
        .name = "Test Strategy",
        .version = "1.0.0",
        .author = "Test Author",
        .description = "A test strategy",
    };
    try valid.validate();
    try std.testing.expect(valid.isValid());

    const invalid = StrategyMetadata{
        .name = "",
        .version = "1.0.0",
        .author = "Test Author",
        .description = "A test strategy",
    };
    try std.testing.expectError(error.EmptyStrategyName, invalid.validate());
    try std.testing.expect(!invalid.isValid());
}

test "ParameterType: toString" {
    try std.testing.expectEqualStrings("integer", ParameterType.integer.toString());
    try std.testing.expectEqualStrings("decimal", ParameterType.decimal.toString());
    try std.testing.expectEqualStrings("boolean", ParameterType.boolean.toString());
    try std.testing.expectEqualStrings("string", ParameterType.string.toString());
}

test "ParameterValue: type conversions" {
    const int_val = ParameterValue{ .integer = 42 };
    try std.testing.expectEqual(@as(i64, 42), int_val.asInteger().?);
    try std.testing.expect(int_val.asDecimal() == null);

    const dec_val = ParameterValue{ .decimal = Decimal.fromInt(100) };
    try std.testing.expect(dec_val.asDecimal() != null);
    try std.testing.expect(dec_val.asInteger() == null);

    const bool_val = ParameterValue{ .boolean = true };
    try std.testing.expectEqual(true, bool_val.asBoolean().?);
    try std.testing.expect(bool_val.asString() == null);

    const str_val = ParameterValue{ .string = "test" };
    try std.testing.expectEqualStrings("test", str_val.asString().?);
    try std.testing.expect(str_val.asBoolean() == null);
}

test "StrategyParameter: validation" {
    const valid = StrategyParameter{
        .name = "fast_period",
        .description = "Fast SMA period",
        .value = .{ .integer = 10 },
    };
    try valid.validate();
    try std.testing.expect(valid.isValid());

    const invalid = StrategyParameter{
        .name = "",
        .description = "Invalid param",
        .value = .{ .integer = 10 },
    };
    try std.testing.expectError(error.EmptyParameterName, invalid.validate());
    try std.testing.expect(!invalid.isValid());
}

test "MinimalROI: validation" {
    const valid = MinimalROI{
        .minutes = 60,
        .roi_percent = Decimal.fromFloat(0.01), // 1%
    };
    try valid.validate();
    try std.testing.expect(valid.isValid());

    const invalid = MinimalROI{
        .minutes = 60,
        .roi_percent = Decimal.fromFloat(-0.01), // Negative ROI
    };
    try std.testing.expectError(error.NegativeROI, invalid.validate());
    try std.testing.expect(!invalid.isValid());
}

test "TrailingStopConfig: validation" {
    const valid = TrailingStopConfig{
        .activate_percent = Decimal.fromFloat(0.02), // 2%
        .offset_percent = Decimal.fromFloat(0.01), // 1%
    };
    try valid.validate();
    try std.testing.expect(valid.isValid());

    // Negative activation
    const invalid1 = TrailingStopConfig{
        .activate_percent = Decimal.fromFloat(-0.02),
        .offset_percent = Decimal.fromFloat(0.01),
    };
    try std.testing.expectError(error.NegativeActivatePercent, invalid1.validate());
    try std.testing.expect(!invalid1.isValid());

    // Negative offset
    const invalid2 = TrailingStopConfig{
        .activate_percent = Decimal.fromFloat(0.02),
        .offset_percent = Decimal.fromFloat(-0.01),
    };
    try std.testing.expectError(error.NegativeOffsetPercent, invalid2.validate());
    try std.testing.expect(!invalid2.isValid());

    // Offset exceeds activation
    const invalid3 = TrailingStopConfig{
        .activate_percent = Decimal.fromFloat(0.01),
        .offset_percent = Decimal.fromFloat(0.02),
    };
    try std.testing.expectError(error.OffsetExceedsActivation, invalid3.validate());
    try std.testing.expect(!invalid3.isValid());
}

test "StrategyConfig: initialization and cleanup" {
    const allocator = std.testing.allocator;

    const metadata = StrategyMetadata{
        .name = "Test Strategy",
        .version = "1.0.0",
        .author = "Test Author",
        .description = "A test strategy",
    };

    const parameters = [_]StrategyParameter{
        .{
            .name = "fast_period",
            .description = "Fast SMA period",
            .value = .{ .integer = 10 },
        },
        .{
            .name = "slow_period",
            .description = "Slow SMA period",
            .value = .{ .integer = 20 },
        },
    };

    const roi = [_]MinimalROI{
        .{ .minutes = 60, .roi_percent = Decimal.fromFloat(0.01) },
        .{ .minutes = 120, .roi_percent = Decimal.fromFloat(0.02) },
    };

    const trailing_stop = TrailingStopConfig{
        .activate_percent = Decimal.fromFloat(0.02),
        .offset_percent = Decimal.fromFloat(0.01),
    };

    const config = try StrategyConfig.init(
        allocator,
        metadata,
        .{ .base = "BTC", .quote = "USDT" },
        .h1,
        &parameters,
        &roi,
        trailing_stop,
        3, // max_open_trades
        Decimal.fromInt(1000), // stake_amount
    );
    defer config.deinit();

    try std.testing.expectEqualStrings("Test Strategy", config.metadata.name);
    try std.testing.expectEqual(@as(usize, 2), config.parameters.len);
    try std.testing.expect(config.minimal_roi != null);
    try std.testing.expectEqual(@as(usize, 2), config.minimal_roi.?.len);
    try std.testing.expect(config.trailing_stop != null);
    try std.testing.expectEqual(@as(u32, 3), config.max_open_trades);
}

test "StrategyConfig: parameter lookup" {
    const allocator = std.testing.allocator;

    const metadata = StrategyMetadata{
        .name = "Test Strategy",
        .version = "1.0.0",
        .author = "Test Author",
        .description = "A test strategy",
    };

    const parameters = [_]StrategyParameter{
        .{
            .name = "fast_period",
            .description = "Fast SMA period",
            .value = .{ .integer = 10 },
        },
    };

    const config = try StrategyConfig.init(
        allocator,
        metadata,
        .{ .base = "BTC", .quote = "USDT" },
        .h1,
        &parameters,
        null,
        null,
        5, // max_open_trades
        Decimal.fromInt(500), // stake_amount
    );
    defer config.deinit();

    try std.testing.expect(config.hasParameter("fast_period"));
    try std.testing.expect(!config.hasParameter("slow_period"));

    const param = config.getParameter("fast_period").?;
    try std.testing.expectEqualStrings("fast_period", param.name);
    try std.testing.expectEqual(@as(i64, 10), param.value.asInteger().?);
}

test "StrategyConfig: no memory leak" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            @panic("Memory leak detected!");
        }
    }
    const allocator = gpa.allocator();

    const metadata = StrategyMetadata{
        .name = "Test Strategy",
        .version = "1.0.0",
        .author = "Test Author",
        .description = "A test strategy",
    };

    const parameters = [_]StrategyParameter{
        .{
            .name = "period",
            .description = "Period",
            .value = .{ .integer = 10 },
        },
    };

    const config = try StrategyConfig.init(
        allocator,
        metadata,
        .{ .base = "BTC", .quote = "USDT" },
        .h1,
        &parameters,
        null,
        null,
        3, // max_open_trades
        Decimal.fromInt(1000), // stake_amount
    );
    defer config.deinit();

    try config.validate();
}
