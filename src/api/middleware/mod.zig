//! API Middleware
//!
//! Middleware components for the API server.

const std = @import("std");

/// Authentication middleware
pub const auth = @import("auth.zig");
pub const AuthContext = auth.AuthContext;
pub const AuthError = auth.AuthError;

// Future middleware:
// pub const cors = @import("cors.zig");
// pub const logger = @import("logger.zig");

test {
    std.testing.refAllDecls(@This());
}
