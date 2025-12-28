//! API Handlers
//!
//! Request handlers for all API endpoints.

const std = @import("std");

pub const health = @import("health.zig");
pub const auth = @import("auth.zig");
pub const advanced = @import("advanced.zig");

test {
    std.testing.refAllDecls(@This());
}
