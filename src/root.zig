//! zigQuant - High-Performance Quantitative Trading Framework
//!
//! This is the root module for the zigQuant library.
const std = @import("std");

// Core modules
pub const time = @import("core/time.zig");

// Re-export commonly used types
pub const Timestamp = time.Timestamp;
pub const Duration = time.Duration;
pub const KlineInterval = time.KlineInterval;

test {
    // Run tests from all modules
    std.testing.refAllDecls(@This());
    _ = time;
}
