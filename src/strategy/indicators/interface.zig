//! Technical Indicator Interface
//!
//! Provides a unified interface for all technical indicators.
//!
//! Design principles:
//! - Polymorphic interface using VTable pattern
//! - Memory-safe with proper cleanup
//! - Efficient calculation on candle arrays
//! - Support for incremental updates

const std = @import("std");
const Decimal = @import("../../root.zig").Decimal;
const Candle = @import("../../root.zig").Candle;

/// Technical indicator interface
/// All indicators implement this interface using VTable pattern
pub const IIndicator = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        /// Calculate indicator values from candle data
        /// @param ptr - Indicator instance pointer
        /// @param candles - Array of candles to process
        /// @return Array of indicator values (same length as candles, with NaN for insufficient data)
        calculate: *const fn (ptr: *anyopaque, candles: []const Candle) anyerror![]Decimal,

        /// Get indicator name
        /// @param ptr - Indicator instance pointer
        /// @return Indicator name (e.g., "SMA", "EMA", "RSI")
        getName: *const fn (ptr: *anyopaque) []const u8,

        /// Get minimum required candles for calculation
        /// @param ptr - Indicator instance pointer
        /// @return Number of candles required before valid values are produced
        getRequiredCandles: *const fn (ptr: *anyopaque) u32,

        /// Clean up indicator resources
        /// @param ptr - Indicator instance pointer
        deinit: *const fn (ptr: *anyopaque) void,
    };

    /// Calculate indicator values
    pub fn calculate(self: IIndicator, candles: []const Candle) ![]Decimal {
        return self.vtable.calculate(self.ptr, candles);
    }

    /// Get indicator name
    pub fn getName(self: IIndicator) []const u8 {
        return self.vtable.getName(self.ptr);
    }

    /// Get required candle count
    pub fn getRequiredCandles(self: IIndicator) u32 {
        return self.vtable.getRequiredCandles(self.ptr);
    }

    /// Clean up resources
    pub fn deinit(self: IIndicator) void {
        self.vtable.deinit(self.ptr);
    }
};

// ============================================================================
// Tests
// ============================================================================

test "IIndicator: interface compiles" {
    // This test just verifies the interface definition compiles
    const allocator = std.testing.allocator;
    _ = allocator;
}
