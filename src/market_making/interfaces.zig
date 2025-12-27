//! IClockStrategy Interface
//!
//! This module defines the clock-driven strategy interface using Zig's VTable pattern.
//! Clock-driven strategies are triggered at fixed time intervals, suitable for
//! market making and other strategies that need periodic quote updates.
//!
//! Design:
//! - onTick: Called at each clock tick with tick number and timestamp
//! - onStart: Called when clock starts running
//! - onStop: Called when clock stops

const std = @import("std");

// ============================================================================
// IClockStrategy Interface
// ============================================================================

/// Clock-driven strategy interface using VTable pattern
/// Strategies implementing this interface will be called at fixed intervals
pub const IClockStrategy = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    /// Virtual function table
    pub const VTable = struct {
        /// Called at each clock tick
        /// @param ptr: Strategy instance pointer
        /// @param tick: Current tick number (starts from 1)
        /// @param timestamp_ns: Current timestamp in nanoseconds
        onTick: *const fn (ptr: *anyopaque, tick: u64, timestamp_ns: i128) anyerror!void,

        /// Called when clock starts
        /// @param ptr: Strategy instance pointer
        onStart: *const fn (ptr: *anyopaque) anyerror!void,

        /// Called when clock stops
        /// @param ptr: Strategy instance pointer
        onStop: *const fn (ptr: *anyopaque) void,
    };

    // ========================================================================
    // Proxy Methods
    // ========================================================================

    /// Handle clock tick
    pub fn onTick(self: IClockStrategy, tick: u64, timestamp_ns: i128) !void {
        return self.vtable.onTick(self.ptr, tick, timestamp_ns);
    }

    /// Handle clock start
    pub fn onStart(self: IClockStrategy) !void {
        return self.vtable.onStart(self.ptr);
    }

    /// Handle clock stop
    pub fn onStop(self: IClockStrategy) void {
        self.vtable.onStop(self.ptr);
    }
};

// ============================================================================
// Tests
// ============================================================================

test "IClockStrategy: VTable structure" {
    // Verify VTable has correct function pointer types
    const vtable_info = @typeInfo(IClockStrategy.VTable);
    try std.testing.expect(vtable_info == .@"struct");
    try std.testing.expectEqual(@as(usize, 3), vtable_info.@"struct".fields.len);
}
