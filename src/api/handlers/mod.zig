//! API Handlers
//!
//! Request handlers for all API endpoints.

const std = @import("std");

pub const health = @import("health.zig");
pub const auth = @import("auth.zig");

// Will be added in subsequent implementations:
// pub const strategies = @import("strategies.zig");
// pub const backtest = @import("backtest.zig");
// pub const orders = @import("orders.zig");
// pub const positions = @import("positions.zig");
// pub const account = @import("account.zig");
// pub const metrics = @import("metrics.zig");

test {
    std.testing.refAllDecls(@This());
}
