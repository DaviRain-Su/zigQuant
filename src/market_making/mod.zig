//! Market Making Module
//!
//! This module provides components for market making strategies:
//! - Clock-driven execution mode for periodic quote updates
//! - IClockStrategy interface for clock-driven strategies
//!
//! ## Story 033: Clock-Driven Mode
//!
//! The Clock scheduler triggers strategies at fixed time intervals,
//! suitable for market making and other strategies that need periodic updates.
//!
//! ## Usage
//!
//! ```zig
//! const mm = @import("market_making");
//!
//! // Create clock with 100ms interval
//! var clock = try mm.Clock.init(allocator, 100);
//! defer clock.deinit();
//!
//! // Register strategy
//! try clock.addStrategy(my_strategy.asClockStrategy());
//!
//! // Run clock (blocking)
//! try clock.start();
//! ```

// Sub-modules
pub const clock = @import("clock.zig");
pub const interfaces = @import("interfaces.zig");

// Re-export main types
pub const Clock = clock.Clock;
pub const ClockStats = clock.ClockStats;
pub const ClockError = clock.ClockError;
pub const SimpleTestStrategy = clock.SimpleTestStrategy;
pub const IClockStrategy = interfaces.IClockStrategy;

// ============================================================================
// Tests
// ============================================================================

test {
    const std = @import("std");
    std.testing.refAllDecls(@This());
}
