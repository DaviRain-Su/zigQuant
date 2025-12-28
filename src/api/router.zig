//! Custom HTTP Router
//!
//! A lightweight router for std.http.Server that supports:
//! - Path parameters (e.g., /api/v1/strategies/:id)
//! - Query string parsing
//! - Multiple HTTP methods
//! - Route matching with priority

const std = @import("std");
const Allocator = std.mem.Allocator;

/// HTTP Method enum
pub const Method = enum {
    GET,
    POST,
    PUT,
    DELETE,
    PATCH,
    OPTIONS,
    HEAD,

    /// Parse from std.http.Method
    pub fn fromStdMethod(method: std.http.Method) ?Method {
        return switch (method) {
            .GET => .GET,
            .POST => .POST,
            .PUT => .PUT,
            .DELETE => .DELETE,
            .PATCH => .PATCH,
            .OPTIONS => .OPTIONS,
            .HEAD => .HEAD,
            else => null,
        };
    }

    /// Convert to std.http.Method
    pub fn toStdMethod(self: Method) std.http.Method {
        return switch (self) {
            .GET => .GET,
            .POST => .POST,
            .PUT => .PUT,
            .DELETE => .DELETE,
            .PATCH => .PATCH,
            .OPTIONS => .OPTIONS,
            .HEAD => .HEAD,
        };
    }
};

/// Route definition
pub const Route = struct {
    method: Method,
    pattern: []const u8,
    handler: *const HandlerFn,
    requires_auth: bool,
    description: []const u8,
};

/// Handler function signature
pub const HandlerFn = fn (*RequestContext) anyerror!void;

/// Path parameters extracted from URL
pub const PathParams = std.StringHashMap([]const u8);

/// Query parameters from URL
pub const QueryParams = std.StringHashMap([]const u8);

/// Match result returned by router
pub const MatchResult = struct {
    route: Route,
    params: PathParams,
};

/// Request context passed to handlers
pub const RequestContext = struct {
    allocator: Allocator,
    arena: std.heap.ArenaAllocator,
    method: Method,
    path: []const u8,
    params: PathParams,
    query: QueryParams,
    headers: std.http.HeaderIterator,
    body: ?[]const u8,
    response: *Response,
    server_context: *anyopaque,
    user_id: ?[]const u8,

    /// Initialize a new request context
    pub fn init(allocator: Allocator, server_context: *anyopaque) RequestContext {
        return .{
            .allocator = allocator,
            .arena = std.heap.ArenaAllocator.init(allocator),
            .method = .GET,
            .path = "/",
            .params = PathParams.init(allocator),
            .query = QueryParams.init(allocator),
            .headers = undefined,
            .body = null,
            .response = undefined,
            .server_context = server_context,
            .user_id = null,
        };
    }

    /// Get a path parameter by name
    pub fn param(self: *const RequestContext, name: []const u8) ?[]const u8 {
        return self.params.get(name);
    }

    /// Get a query parameter by name
    pub fn queryParam(self: *const RequestContext, name: []const u8) ?[]const u8 {
        return self.query.get(name);
    }

    /// Get a header value by name (case-insensitive)
    pub fn header(self: *RequestContext, name: []const u8) ?[]const u8 {
        var iter = self.headers;
        while (iter.next()) |h| {
            if (std.ascii.eqlIgnoreCase(h.name, name)) {
                return h.value;
            }
        }
        return null;
    }

    /// Clean up resources
    pub fn deinit(self: *RequestContext) void {
        self.params.deinit();
        self.query.deinit();
        self.arena.deinit();
    }
};

/// HTTP Response builder
pub const Response = struct {
    allocator: Allocator,
    status: std.http.Status,
    headers: std.ArrayListUnmanaged(Header),
    body: std.ArrayListUnmanaged(u8),

    pub const Header = struct {
        name: []const u8,
        value: []const u8,
    };

    /// Initialize a new response
    pub fn init(allocator: Allocator) Response {
        _ = allocator;
        return .{
            .allocator = undefined,
            .status = .ok,
            .headers = .{},
            .body = .{},
        };
    }

    /// Initialize with allocator
    pub fn initWithAllocator(allocator: Allocator) Response {
        return .{
            .allocator = allocator,
            .status = .ok,
            .headers = .{},
            .body = .{},
        };
    }

    /// Set response status
    pub fn setStatus(self: *Response, status: std.http.Status) void {
        self.status = status;
    }

    /// Add a header
    pub fn addHeader(self: *Response, name: []const u8, value: []const u8) !void {
        try self.headers.append(self.allocator, .{ .name = name, .value = value });
    }

    /// Set Content-Type header
    pub fn setContentType(self: *Response, content_type: []const u8) !void {
        // Remove existing Content-Type if any
        var i: usize = 0;
        while (i < self.headers.items.len) {
            if (std.ascii.eqlIgnoreCase(self.headers.items[i].name, "Content-Type")) {
                _ = self.headers.orderedRemove(i);
            } else {
                i += 1;
            }
        }
        try self.addHeader("Content-Type", content_type);
    }

    /// Write JSON response
    pub fn json(self: *Response, val: anytype) !void {
        try self.setContentType("application/json");
        self.body.clearRetainingCapacity();
        const json_bytes = try std.json.Stringify.valueAlloc(self.allocator, val, .{});
        defer self.allocator.free(json_bytes);
        try self.body.appendSlice(self.allocator, json_bytes);
    }

    /// Write plain text response
    pub fn text(self: *Response, content: []const u8) !void {
        try self.setContentType("text/plain");
        self.body.clearRetainingCapacity();
        try self.body.appendSlice(self.allocator, content);
    }

    /// Write HTML response
    pub fn html(self: *Response, content: []const u8) !void {
        try self.setContentType("text/html");
        self.body.clearRetainingCapacity();
        try self.body.appendSlice(self.allocator, content);
    }

    /// Clean up resources
    pub fn deinit(self: *Response) void {
        self.headers.deinit(self.allocator);
        self.body.deinit(self.allocator);
    }
};

/// HTTP Router
pub const Router = struct {
    allocator: Allocator,
    routes: std.ArrayListUnmanaged(Route),

    const Self = @This();

    /// Initialize a new router
    pub fn init(allocator: Allocator) Self {
        return .{
            .allocator = allocator,
            .routes = .{},
        };
    }

    /// Clean up resources
    pub fn deinit(self: *Self) void {
        self.routes.deinit(self.allocator);
    }

    /// Add a GET route
    pub fn get(self: *Self, pattern: []const u8, handler: *const HandlerFn) !void {
        try self.addRoute(.GET, pattern, handler, true, "");
    }

    /// Add a GET route without auth
    pub fn getNoAuth(self: *Self, pattern: []const u8, handler: *const HandlerFn) !void {
        try self.addRoute(.GET, pattern, handler, false, "");
    }

    /// Add a POST route
    pub fn post(self: *Self, pattern: []const u8, handler: *const HandlerFn) !void {
        try self.addRoute(.POST, pattern, handler, true, "");
    }

    /// Add a POST route without auth
    pub fn postNoAuth(self: *Self, pattern: []const u8, handler: *const HandlerFn) !void {
        try self.addRoute(.POST, pattern, handler, false, "");
    }

    /// Add a PUT route
    pub fn put(self: *Self, pattern: []const u8, handler: *const HandlerFn) !void {
        try self.addRoute(.PUT, pattern, handler, true, "");
    }

    /// Add a DELETE route
    pub fn delete(self: *Self, pattern: []const u8, handler: *const HandlerFn) !void {
        try self.addRoute(.DELETE, pattern, handler, true, "");
    }

    /// Add a PATCH route
    pub fn patch(self: *Self, pattern: []const u8, handler: *const HandlerFn) !void {
        try self.addRoute(.PATCH, pattern, handler, true, "");
    }

    /// Add an OPTIONS route
    pub fn options(self: *Self, pattern: []const u8, handler: *const HandlerFn) !void {
        try self.addRoute(.OPTIONS, pattern, handler, false, "");
    }

    /// Add a route with full configuration
    pub fn addRoute(
        self: *Self,
        method: Method,
        pattern: []const u8,
        handler: *const HandlerFn,
        requires_auth: bool,
        description: []const u8,
    ) !void {
        try self.routes.append(self.allocator, .{
            .method = method,
            .pattern = pattern,
            .handler = handler,
            .requires_auth = requires_auth,
            .description = description,
        });
    }

    /// Match a request to a route
    pub fn match(self: *Self, allocator: Allocator, method: Method, path: []const u8) !?MatchResult {
        // Remove query string from path for matching
        const path_only = if (std.mem.indexOf(u8, path, "?")) |idx|
            path[0..idx]
        else
            path;

        for (self.routes.items) |route| {
            if (route.method == method) {
                if (try matchPattern(allocator, route.pattern, path_only)) |params| {
                    return .{ .route = route, .params = params };
                }
            }
        }
        return null;
    }

    /// Get all registered routes (for documentation)
    pub fn getRoutes(self: *Self) []const Route {
        return self.routes.items;
    }
};

/// Match a pattern against a path, extracting parameters
/// Pattern can contain :param placeholders
/// Returns null if no match, otherwise returns extracted parameters
fn matchPattern(allocator: Allocator, pattern: []const u8, path: []const u8) !?PathParams {
    var params = PathParams.init(allocator);
    errdefer params.deinit();

    // Handle wildcard pattern
    if (std.mem.eql(u8, pattern, "/*")) {
        return params;
    }

    var pattern_iter = std.mem.splitScalar(u8, pattern, '/');
    var path_iter = std.mem.splitScalar(u8, path, '/');

    while (true) {
        const pattern_segment = pattern_iter.next();
        const path_segment = path_iter.next();

        if (pattern_segment == null and path_segment == null) {
            // Both exhausted, match successful
            return params;
        }

        if (pattern_segment == null or path_segment == null) {
            // One exhausted but not the other, no match
            params.deinit();
            return null;
        }

        const p = pattern_segment.?;
        const s = path_segment.?;

        if (p.len > 0 and p[0] == ':') {
            // This is a parameter, extract it
            const param_name = p[1..];
            try params.put(param_name, s);
        } else if (std.mem.eql(u8, p, "*")) {
            // Wildcard matches anything
            continue;
        } else if (!std.mem.eql(u8, p, s)) {
            // Literal segment doesn't match
            params.deinit();
            return null;
        }
    }
}

/// Parse query string into parameters
pub fn parseQueryString(allocator: Allocator, query_string: []const u8) !QueryParams {
    var params = QueryParams.init(allocator);
    errdefer params.deinit();

    if (query_string.len == 0) {
        return params;
    }

    var iter = std.mem.splitScalar(u8, query_string, '&');
    while (iter.next()) |pair| {
        if (std.mem.indexOf(u8, pair, "=")) |eq_idx| {
            const key = pair[0..eq_idx];
            const value = pair[eq_idx + 1 ..];
            // URL decode would go here in a full implementation
            try params.put(key, value);
        } else {
            // Key without value
            try params.put(pair, "");
        }
    }

    return params;
}

/// Extract query string from path
pub fn extractQueryString(path: []const u8) ?[]const u8 {
    if (std.mem.indexOf(u8, path, "?")) |idx| {
        return path[idx + 1 ..];
    }
    return null;
}

// ============================================================================
// Tests
// ============================================================================

test "matchPattern - exact match" {
    const allocator = std.testing.allocator;
    const result = try matchPattern(allocator, "/health", "/health");
    try std.testing.expect(result != null);
    var params = result.?;
    defer params.deinit();
    try std.testing.expectEqual(@as(usize, 0), params.count());
}

test "matchPattern - parameter extraction" {
    const allocator = std.testing.allocator;
    const result = try matchPattern(allocator, "/api/v1/strategies/:id", "/api/v1/strategies/123");
    try std.testing.expect(result != null);
    var params = result.?;
    defer params.deinit();
    try std.testing.expectEqual(@as(usize, 1), params.count());
    try std.testing.expectEqualStrings("123", params.get("id").?);
}

test "matchPattern - multiple parameters" {
    const allocator = std.testing.allocator;
    const result = try matchPattern(allocator, "/api/:version/:resource/:id", "/api/v1/orders/456");
    try std.testing.expect(result != null);
    var params = result.?;
    defer params.deinit();
    try std.testing.expectEqual(@as(usize, 3), params.count());
    try std.testing.expectEqualStrings("v1", params.get("version").?);
    try std.testing.expectEqualStrings("orders", params.get("resource").?);
    try std.testing.expectEqualStrings("456", params.get("id").?);
}

test "matchPattern - no match" {
    const allocator = std.testing.allocator;
    const result = try matchPattern(allocator, "/api/v1/strategies", "/api/v2/strategies");
    try std.testing.expect(result == null);
}

test "parseQueryString - basic" {
    const allocator = std.testing.allocator;
    var params = try parseQueryString(allocator, "foo=bar&baz=qux");
    defer params.deinit();
    try std.testing.expectEqualStrings("bar", params.get("foo").?);
    try std.testing.expectEqualStrings("qux", params.get("baz").?);
}

test "Router - basic routing" {
    const allocator = std.testing.allocator;
    var router = Router.init(allocator);
    defer router.deinit();

    const dummyHandler = struct {
        fn handle(_: *RequestContext) !void {}
    }.handle;

    try router.get("/health", dummyHandler);
    try router.get("/api/v1/strategies/:id", dummyHandler);
    try router.post("/api/v1/orders", dummyHandler);

    // Test matching
    {
        const result = try router.match(allocator, .GET, "/health");
        try std.testing.expect(result != null);
        var r = result.?;
        defer r.params.deinit();
        try std.testing.expectEqualStrings("/health", r.route.pattern);
    }

    {
        const result = try router.match(allocator, .GET, "/api/v1/strategies/123");
        try std.testing.expect(result != null);
        var r = result.?;
        defer r.params.deinit();
        try std.testing.expectEqualStrings("123", r.params.get("id").?);
    }

    {
        const result = try router.match(allocator, .POST, "/api/v1/orders");
        try std.testing.expect(result != null);
        var r = result.?;
        defer r.params.deinit();
    }

    {
        const result = try router.match(allocator, .GET, "/nonexistent");
        try std.testing.expect(result == null);
    }
}
