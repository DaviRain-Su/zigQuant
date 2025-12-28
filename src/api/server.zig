//! API Server
//!
//! High-performance REST API server built on http.zig.
//!
//! Features:
//! - Health check endpoints (/health, /ready)
//! - JWT authentication
//! - CORS support
//! - Request logging
//! - Prometheus metrics export

const std = @import("std");
const httpz = @import("httpz");
const Allocator = std.mem.Allocator;

const config_mod = @import("config.zig");
const ApiConfig = config_mod.ApiConfig;
const ApiDependencies = config_mod.ApiDependencies;
const IExchange = config_mod.IExchange;
const handlers = @import("handlers/mod.zig");
const jwt_mod = @import("jwt.zig");
const cors = @import("middleware/cors.zig");

// ============================================================================
// Response Types for Multi-Exchange API
// ============================================================================

/// Exchange info for listing exchanges
pub const ExchangeInfo = struct {
    name: []const u8,
    status: []const u8,
    network: []const u8,
};

/// Position summary per exchange
pub const PositionSummary = struct {
    exchange: []const u8,
    position_count: usize,
    total_pnl: f64,
    total_margin: f64,
    status: []const u8,
};

/// Order summary per exchange
pub const OrderSummary = struct {
    exchange: []const u8,
    order_count: usize,
    status: []const u8,
};

/// Account info per exchange
pub const AccountInfo = struct {
    exchange: []const u8,
    account_id: []const u8,
    account_type: []const u8,
    network: []const u8,
    status: []const u8,
};

/// Balance summary per exchange
pub const BalanceSummary = struct {
    exchange: []const u8,
    total: f64,
    available: f64,
    locked: f64,
    status: []const u8,
};

/// API Server State
/// This is passed to all request handlers as context.
pub const ServerContext = struct {
    allocator: Allocator,
    config: ApiConfig,
    deps: ApiDependencies,
    start_time: i64,
    jwt_manager: jwt_mod.JwtManager,
    request_count: std.atomic.Value(u64),
    cors_config: cors.CorsConfig,

    /// Get server uptime in seconds
    pub fn uptime(self: *const ServerContext) i64 {
        return std.time.timestamp() - self.start_time;
    }

    /// Increment request counter
    pub fn incrementRequestCount(self: *ServerContext) void {
        _ = self.request_count.fetchAdd(1, .monotonic);
    }

    /// Get total request count
    pub fn getRequestCount(self: *const ServerContext) u64 {
        return self.request_count.load(.monotonic);
    }

    /// Add CORS headers to response
    pub fn addCorsHeaders(self: *const ServerContext, req: *httpz.Request, res: *httpz.Response) void {
        const origin = req.header("origin");
        cors.addCorsHeaders(res, origin, self.cors_config);
    }
};

/// API Server
pub const ApiServer = struct {
    allocator: Allocator,
    config: ApiConfig,
    deps: ApiDependencies,
    context: *ServerContext,
    server: HttpServer,

    const Self = @This();
    const HttpServer = httpz.Server(*ServerContext);

    /// Initialize the API server
    pub fn init(
        allocator: Allocator,
        config: ApiConfig,
        deps: ApiDependencies,
    ) !*Self {
        // Validate configuration
        try config.validate();

        // Create server context
        const context = try allocator.create(ServerContext);
        errdefer allocator.destroy(context);

        context.* = .{
            .allocator = allocator,
            .config = config,
            .deps = deps,
            .start_time = std.time.timestamp(),
            .jwt_manager = jwt_mod.JwtManager.init(
                allocator,
                config.jwt_secret,
                config.jwt_expiry_hours,
                "zigquant",
            ),
            .request_count = std.atomic.Value(u64).init(0),
            .cors_config = .{
                .allowed_origins = config.cors_origins,
            },
        };

        // Create HTTP server
        // Note: httpz.Config.address expects []const u8 or null (for 0.0.0.0)
        const address: ?[]const u8 = if (std.mem.eql(u8, config.host, "0.0.0.0"))
            null
        else
            config.host;

        var server = try HttpServer.init(allocator, .{
            .port = config.port,
            .address = address,
            .request = .{
                .max_body_size = config.max_body_size,
            },
        }, context);
        errdefer server.deinit();

        // Setup routes
        try setupRoutes(&server);

        // Create ApiServer instance
        const self = try allocator.create(Self);
        self.* = .{
            .allocator = allocator,
            .config = config,
            .deps = deps,
            .context = context,
            .server = server,
        };

        return self;
    }

    /// Setup all routes
    fn setupRoutes(server: *HttpServer) !void {
        var router = try server.router(.{});

        // CORS preflight handler for all routes
        router.options("/*", handleCorsPreflightWildcard, .{});

        // Health check endpoints (no auth required)
        router.get("/health", handleHealth, .{});
        router.get("/ready", handleReady, .{});
        router.get("/version", handleVersion, .{});

        // Authentication endpoints (no auth required)
        router.post("/api/v1/auth/login", handleLogin, .{});
        router.post("/api/v1/auth/refresh", handleRefresh, .{});
        router.get("/api/v1/auth/me", handleMe, .{});

        // API v1 routes (public for now, auth can be added per-handler)
        // Exchanges - Multi-exchange support
        router.get("/api/v1/exchanges", handleExchangesList, .{});
        router.get("/api/v1/exchanges/:name", handleExchangeGet, .{});

        // Strategies
        router.get("/api/v1/strategies", handleStrategiesList, .{});
        router.get("/api/v1/strategies/:id", handleStrategyGet, .{});
        router.post("/api/v1/strategies/:id/run", handleStrategyRun, .{});

        // Backtest
        router.post("/api/v1/backtest", handleBacktestCreate, .{});
        router.get("/api/v1/backtest/:id", handleBacktestGet, .{});

        // Positions
        router.get("/api/v1/positions", handlePositionsList, .{});

        // Orders
        router.get("/api/v1/orders", handleOrdersList, .{});
        router.post("/api/v1/orders", handleOrderCreate, .{});
        router.delete("/api/v1/orders/:id", handleOrderCancel, .{});

        // Account
        router.get("/api/v1/account", handleAccountGet, .{});
        router.get("/api/v1/account/balance", handleAccountBalance, .{});

        // Metrics endpoint (Prometheus format)
        router.get("/metrics", handleMetrics, .{});
    }

    /// Start the server (blocking)
    pub fn start(self: *Self) !void {
        std.log.info("Starting API server on {s}:{d}", .{ self.config.host, self.config.port });
        try self.server.listen();
    }

    /// Stop the server
    pub fn stop(self: *Self) void {
        self.server.stop();
    }

    /// Clean up resources
    pub fn deinit(self: *Self) void {
        self.server.deinit();
        self.allocator.destroy(self.context);
        self.allocator.destroy(self);
    }

    // ========================================================================
    // Route Handlers - CORS
    // ========================================================================

    fn handleCorsPreflightWildcard(ctx: *ServerContext, req: *httpz.Request, res: *httpz.Response) !void {
        const origin = req.header("origin");
        cors.handlePreflight(res, origin, ctx.cors_config);
    }

    // ========================================================================
    // Route Handlers - Health & Info
    // ========================================================================

    fn handleHealth(ctx: *ServerContext, req: *httpz.Request, res: *httpz.Response) !void {
        ctx.addCorsHeaders(req, res);
        ctx.incrementRequestCount();
        try res.json(.{
            .status = "healthy",
            .version = "1.0.0",
            .uptime_seconds = ctx.uptime(),
            .timestamp = std.time.timestamp(),
        }, .{});
    }

    fn handleReady(ctx: *ServerContext, req: *httpz.Request, res: *httpz.Response) !void {
        ctx.addCorsHeaders(req, res);
        ctx.incrementRequestCount();
        // Check dependencies - for now we check if JWT is configured
        const jwt_configured = ctx.config.jwt_secret.len >= 32;

        // In a full implementation, we would check:
        // - Database connection (if using one)
        // - Exchange API connectivity
        // - Required services availability

        const checks = .{
            .jwt_configured = jwt_configured,
            .server_running = true,
        };

        const all_ready = jwt_configured;

        if (all_ready) {
            try res.json(.{
                .ready = true,
                .checks = checks,
            }, .{});
        } else {
            res.setStatus(.service_unavailable);
            try res.json(.{
                .ready = false,
                .checks = checks,
            }, .{});
        }
    }

    fn handleVersion(ctx: *ServerContext, req: *httpz.Request, res: *httpz.Response) !void {
        ctx.addCorsHeaders(req, res);
        ctx.incrementRequestCount();
        try res.json(.{
            .name = "zigQuant",
            .version = "1.0.0",
            .api_version = "v1",
            .zig_version = @import("builtin").zig_version_string,
        }, .{});
    }

    // ========================================================================
    // Route Handlers - Exchanges (Multi-Exchange Support)
    // ========================================================================

    fn handleExchangesList(ctx: *ServerContext, req: *httpz.Request, res: *httpz.Response) !void {
        ctx.addCorsHeaders(req, res);
        ctx.incrementRequestCount();

        // Build list of connected exchanges
        var exchanges_list: std.ArrayListUnmanaged(ExchangeInfo) = .empty;
        defer exchanges_list.deinit(ctx.allocator);

        var iter = ctx.deps.iterator();
        while (iter.next()) |entry| {
            const exchange_entry = entry.value_ptr.*;
            const network = if (exchange_entry.config.testnet) "testnet" else "mainnet";
            const status = if (exchange_entry.interface.isConnected()) "connected" else "disconnected";

            try exchanges_list.append(ctx.allocator, .{
                .name = entry.key_ptr.*,
                .status = status,
                .network = network,
            });
        }

        try res.json(.{
            .exchanges = exchanges_list.items,
            .total = ctx.deps.exchangeCount(),
            .note = "Use ?exchange=<name> parameter to filter by exchange",
        }, .{});
    }

    fn handleExchangeGet(ctx: *ServerContext, req: *httpz.Request, res: *httpz.Response) !void {
        ctx.addCorsHeaders(req, res);
        ctx.incrementRequestCount();

        const name = req.param("name") orelse {
            res.setStatus(.bad_request);
            try res.json(.{ .@"error" = "Missing exchange name" }, .{});
            return;
        };

        if (ctx.deps.getExchange(name)) |exchange_entry| {
            const network = if (exchange_entry.config.testnet) "testnet" else "mainnet";
            const status = if (exchange_entry.interface.isConnected()) "connected" else "disconnected";

            try res.json(.{
                .name = name,
                .status = status,
                .network = network,
                .api_key = exchange_entry.config.api_key,
                .features = .{
                    .spot = false,
                    .futures = true,
                    .margin = false,
                },
            }, .{});
        } else {
            res.setStatus(.not_found);
            try res.json(.{ .@"error" = "Exchange not found", .name = name }, .{});
        }
    }

    // ========================================================================
    // Route Handlers - Authentication
    // ========================================================================

    fn handleLogin(ctx: *ServerContext, req: *httpz.Request, res: *httpz.Response) !void {
        ctx.addCorsHeaders(req, res);
        ctx.incrementRequestCount();

        // Parse request body
        const body = req.body() orelse {
            res.setStatus(.bad_request);
            try res.json(.{ .@"error" = "Missing request body" }, .{});
            return;
        };

        const LoginRequest = struct {
            username: []const u8,
            password: []const u8,
        };

        const parsed = std.json.parseFromSlice(LoginRequest, req.arena, body, .{}) catch {
            res.setStatus(.bad_request);
            try res.json(.{
                .@"error" = "Invalid JSON format",
                .expected = "{ \"username\": \"...\", \"password\": \"...\" }",
            }, .{});
            return;
        };

        const login_req = parsed.value;

        // Validate credentials (demo users - in production use proper auth)
        if (!validateCredentials(login_req.username, login_req.password)) {
            res.setStatus(.unauthorized);
            try res.json(.{ .@"error" = "Invalid credentials" }, .{});
            return;
        }

        // Generate JWT token
        const token = ctx.jwt_manager.generateToken(login_req.username) catch |err| {
            std.log.err("Failed to generate token: {}", .{err});
            res.setStatus(.internal_server_error);
            try res.json(.{ .@"error" = "Failed to generate token" }, .{});
            return;
        };

        try res.json(.{
            .token = token,
            .expires_in = ctx.jwt_manager.expiry_seconds,
            .token_type = "Bearer",
        }, .{});
    }

    fn handleRefresh(ctx: *ServerContext, req: *httpz.Request, res: *httpz.Response) !void {
        ctx.addCorsHeaders(req, res);
        ctx.incrementRequestCount();

        const auth_header = req.header("authorization") orelse {
            res.setStatus(.unauthorized);
            try res.json(.{ .@"error" = "Missing Authorization header" }, .{});
            return;
        };

        const prefix = "Bearer ";
        if (!std.mem.startsWith(u8, auth_header, prefix)) {
            res.setStatus(.unauthorized);
            try res.json(.{ .@"error" = "Invalid Authorization format" }, .{});
            return;
        }

        const token = auth_header[prefix.len..];
        const new_token = ctx.jwt_manager.refreshToken(token) catch |err| {
            const err_msg = switch (err) {
                error.TokenExpired => "Token has expired. Please login again.",
                error.InvalidSignature => "Invalid token signature.",
                else => "Invalid token.",
            };
            res.setStatus(.unauthorized);
            try res.json(.{ .@"error" = err_msg }, .{});
            return;
        };

        try res.json(.{
            .token = new_token,
            .expires_in = ctx.jwt_manager.expiry_seconds,
            .token_type = "Bearer",
        }, .{});
    }

    fn handleMe(ctx: *ServerContext, req: *httpz.Request, res: *httpz.Response) !void {
        ctx.addCorsHeaders(req, res);
        ctx.incrementRequestCount();

        const auth_header = req.header("authorization") orelse {
            res.setStatus(.unauthorized);
            try res.json(.{ .@"error" = "Missing Authorization header" }, .{});
            return;
        };

        const prefix = "Bearer ";
        if (!std.mem.startsWith(u8, auth_header, prefix)) {
            res.setStatus(.unauthorized);
            try res.json(.{ .@"error" = "Invalid Authorization format" }, .{});
            return;
        }

        const token = auth_header[prefix.len..];
        const payload = ctx.jwt_manager.verifyToken(token) catch |err| {
            const err_msg = switch (err) {
                error.TokenExpired => "Token has expired",
                error.InvalidSignature => "Invalid token signature",
                else => "Invalid token",
            };
            res.setStatus(.unauthorized);
            try res.json(.{ .@"error" = err_msg }, .{});
            return;
        };

        try res.json(.{
            .user_id = payload.sub,
            .issued_at = payload.iat,
            .expires_at = payload.exp,
            .issuer = payload.iss,
        }, .{});
    }

    // ========================================================================
    // Route Handlers - Strategies
    // ========================================================================

    fn handleStrategiesList(ctx: *ServerContext, req: *httpz.Request, res: *httpz.Response) !void {
        ctx.addCorsHeaders(req, res);
        ctx.incrementRequestCount();

        // Built-in strategies available in zigQuant
        // These are the actual strategies implemented in src/strategy/
        try res.json(.{
            .strategies = &[_]struct {
                id: []const u8,
                name: []const u8,
                description: []const u8,
                status: []const u8,
            }{
                .{
                    .id = "dual_ma",
                    .name = "Dual MA Crossover",
                    .description = "Trend following strategy using fast/slow moving average crossovers",
                    .status = "available",
                },
                .{
                    .id = "rsi_mean_reversion",
                    .name = "RSI Mean Reversion",
                    .description = "Mean reversion strategy based on RSI oversold/overbought levels",
                    .status = "available",
                },
                .{
                    .id = "bollinger_breakout",
                    .name = "Bollinger Breakout",
                    .description = "Breakout strategy using Bollinger Bands volatility signals",
                    .status = "available",
                },
            },
            .total = 3,
        }, .{});
    }

    fn handleStrategyGet(ctx: *ServerContext, req: *httpz.Request, res: *httpz.Response) !void {
        ctx.addCorsHeaders(req, res);
        ctx.incrementRequestCount();

        const id = req.param("id") orelse {
            res.setStatus(.bad_request);
            try res.json(.{ .@"error" = "Missing strategy ID" }, .{});
            return;
        };

        // Strategy details based on ID
        if (std.mem.eql(u8, id, "dual_ma")) {
            try res.json(.{
                .id = "dual_ma",
                .name = "Dual MA Crossover",
                .description = "Trend following strategy using fast/slow moving average crossovers",
                .status = "available",
                .parameters = .{
                    .fast_period = .{ .type = "integer", .default = 10, .min = 2, .max = 50 },
                    .slow_period = .{ .type = "integer", .default = 20, .min = 5, .max = 200 },
                },
            }, .{});
        } else if (std.mem.eql(u8, id, "rsi_mean_reversion")) {
            try res.json(.{
                .id = "rsi_mean_reversion",
                .name = "RSI Mean Reversion",
                .description = "Mean reversion strategy based on RSI oversold/overbought levels",
                .status = "available",
                .parameters = .{
                    .rsi_period = .{ .type = "integer", .default = 14, .min = 2, .max = 50 },
                    .oversold = .{ .type = "float", .default = 30.0, .min = 0.0, .max = 50.0 },
                    .overbought = .{ .type = "float", .default = 70.0, .min = 50.0, .max = 100.0 },
                },
            }, .{});
        } else if (std.mem.eql(u8, id, "bollinger_breakout")) {
            try res.json(.{
                .id = "bollinger_breakout",
                .name = "Bollinger Breakout",
                .description = "Breakout strategy using Bollinger Bands volatility signals",
                .status = "available",
                .parameters = .{
                    .period = .{ .type = "integer", .default = 20, .min = 5, .max = 100 },
                    .std_dev = .{ .type = "float", .default = 2.0, .min = 0.5, .max = 4.0 },
                },
            }, .{});
        } else {
            res.setStatus(.not_found);
            try res.json(.{ .@"error" = "Strategy not found", .id = id }, .{});
        }
    }

    fn handleStrategyRun(ctx: *ServerContext, req: *httpz.Request, res: *httpz.Response) !void {
        ctx.addCorsHeaders(req, res);
        ctx.incrementRequestCount();

        const id = req.param("id") orelse {
            res.setStatus(.bad_request);
            try res.json(.{ .@"error" = "Missing strategy ID" }, .{});
            return;
        };

        // Validate strategy exists
        const valid_strategies = [_][]const u8{ "dual_ma", "rsi_mean_reversion", "bollinger_breakout" };
        var strategy_found = false;
        for (valid_strategies) |valid_id| {
            if (std.mem.eql(u8, id, valid_id)) {
                strategy_found = true;
                break;
            }
        }

        if (!strategy_found) {
            res.setStatus(.not_found);
            try res.json(.{ .@"error" = "Strategy not found", .id = id }, .{});
            return;
        }

        // In a real implementation, this would start the strategy
        // For now, return a simulated response
        const timestamp = std.time.timestamp();
        res.setStatus(.accepted);
        try res.json(.{
            .id = id,
            .status = "starting",
            .message = "Strategy run initiated",
            .run_id = timestamp,
        }, .{});
    }

    // ========================================================================
    // Route Handlers - Backtest
    // ========================================================================

    fn handleBacktestCreate(ctx: *ServerContext, req: *httpz.Request, res: *httpz.Response) !void {
        ctx.addCorsHeaders(req, res);
        ctx.incrementRequestCount();

        const body = req.body() orelse {
            res.setStatus(.bad_request);
            try res.json(.{ .@"error" = "Missing request body" }, .{});
            return;
        };

        const BacktestRequest = struct {
            strategy_id: []const u8,
            start_date: []const u8,
            end_date: []const u8,
            initial_capital: f64 = 10000.0,
            pair: []const u8 = "BTC-USDT",
        };

        const parsed = std.json.parseFromSlice(BacktestRequest, req.arena, body, .{}) catch {
            res.setStatus(.bad_request);
            try res.json(.{
                .@"error" = "Invalid JSON format",
                .expected = "{ \"strategy_id\": \"...\", \"start_date\": \"YYYY-MM-DD\", \"end_date\": \"YYYY-MM-DD\" }",
            }, .{});
            return;
        };

        const backtest_req = parsed.value;

        // Validate strategy exists
        const valid_strategies = [_][]const u8{ "dual_ma", "rsi_mean_reversion", "bollinger_breakout" };
        var strategy_found = false;
        for (valid_strategies) |valid_id| {
            if (std.mem.eql(u8, backtest_req.strategy_id, valid_id)) {
                strategy_found = true;
                break;
            }
        }

        if (!strategy_found) {
            res.setStatus(.not_found);
            try res.json(.{ .@"error" = "Strategy not found", .strategy_id = backtest_req.strategy_id }, .{});
            return;
        }

        // Generate a backtest ID based on timestamp
        const timestamp = std.time.timestamp();

        // In a real implementation, this would queue the backtest
        res.setStatus(.accepted);
        try res.json(.{
            .id = timestamp,
            .strategy_id = backtest_req.strategy_id,
            .start_date = backtest_req.start_date,
            .end_date = backtest_req.end_date,
            .initial_capital = backtest_req.initial_capital,
            .pair = backtest_req.pair,
            .status = "pending",
            .message = "Backtest submitted successfully",
        }, .{});
    }

    fn handleBacktestGet(ctx: *ServerContext, req: *httpz.Request, res: *httpz.Response) !void {
        ctx.addCorsHeaders(req, res);
        ctx.incrementRequestCount();

        const id = req.param("id") orelse {
            res.setStatus(.bad_request);
            try res.json(.{ .@"error" = "Missing backtest ID" }, .{});
            return;
        };

        // In a real implementation, this would lookup the backtest result
        // For demo, return a simulated completed backtest
        try res.json(.{
            .id = id,
            .status = "completed",
            .strategy_id = "dual_ma",
            .start_date = "2024-01-01",
            .end_date = "2024-12-31",
            .initial_capital = 10000.0,
            .final_capital = 12500.0,
            .metrics = .{
                .total_return = 0.25,
                .total_return_pct = 25.0,
                .sharpe_ratio = 1.85,
                .sortino_ratio = 2.1,
                .max_drawdown = 0.12,
                .max_drawdown_pct = 12.0,
                .win_rate = 0.58,
                .profit_factor = 1.65,
                .total_trades = 156,
                .winning_trades = 90,
                .losing_trades = 66,
                .avg_trade_return = 0.0016,
            },
        }, .{});
    }

    // ========================================================================
    // Route Handlers - Positions (Multi-Exchange)
    // ========================================================================

    fn handlePositionsList(ctx: *ServerContext, req: *httpz.Request, res: *httpz.Response) !void {
        ctx.addCorsHeaders(req, res);
        ctx.incrementRequestCount();

        // Check for exchange filter via query string
        const query_map = req.query() catch null;
        const exchange_filter: ?[]const u8 = if (query_map) |qm| qm.get("exchange") else null;

        if (!ctx.deps.hasExchanges()) {
            try returnMockPositions(res);
            return;
        }

        // Build response with positions from all or specific exchange(s)
        var all_positions: std.ArrayListUnmanaged(PositionSummary) = .empty;
        defer all_positions.deinit(ctx.allocator);

        var grand_total_pnl: f64 = 0;
        var grand_total_margin: f64 = 0;
        var grand_total_positions: usize = 0;

        var iter = ctx.deps.iterator();
        while (iter.next()) |entry| {
            const name = entry.key_ptr.*;

            // Skip if filtering by specific exchange
            if (exchange_filter) |filter| {
                if (!std.mem.eql(u8, filter, "all") and !std.mem.eql(u8, name, filter)) {
                    continue;
                }
            }

            const exchange_entry = entry.value_ptr.*;
            const positions = exchange_entry.interface.getPositions() catch |err| {
                try all_positions.append(ctx.allocator, .{
                    .exchange = name,
                    .position_count = 0,
                    .total_pnl = 0,
                    .total_margin = 0,
                    .status = @errorName(err),
                });
                continue;
            };
            defer ctx.allocator.free(positions);

            var total_pnl: f64 = 0;
            var total_margin: f64 = 0;
            for (positions) |pos| {
                total_pnl += pos.unrealized_pnl.toFloat();
                total_margin += pos.margin_used.toFloat();
            }

            try all_positions.append(ctx.allocator, .{
                .exchange = name,
                .position_count = positions.len,
                .total_pnl = total_pnl,
                .total_margin = total_margin,
                .status = "ok",
            });

            grand_total_pnl += total_pnl;
            grand_total_margin += total_margin;
            grand_total_positions += positions.len;
        }

        try res.json(.{
            .positions_by_exchange = all_positions.items,
            .summary = .{
                .total_positions = grand_total_positions,
                .total_unrealized_pnl = grand_total_pnl,
                .total_margin_used = grand_total_margin,
                .exchanges_queried = all_positions.items.len,
            },
            .filter = exchange_filter orelse "all",
        }, .{});
    }

    fn returnMockPositions(res: *httpz.Response) !void {
        try res.json(.{
            .positions = &[_]struct {
                id: []const u8,
                pair: []const u8,
                side: []const u8,
                size: f64,
                entry_price: f64,
                unrealized_pnl: f64,
                leverage: f64,
                margin: f64,
                liquidation_price: f64,
            }{
                .{
                    .id = "pos_001",
                    .pair = "BTC-USDT",
                    .side = "long",
                    .size = 0.5,
                    .entry_price = 42000.0,
                    .unrealized_pnl = 750.0,
                    .leverage = 5.0,
                    .margin = 4200.0,
                    .liquidation_price = 35000.0,
                },
            },
            .total = 1,
            .total_unrealized_pnl = 750.0,
            .total_margin_used = 4200.0,
            .source = "mock",
        }, .{});
    }

    // ========================================================================
    // Route Handlers - Orders (Multi-Exchange)
    // ========================================================================

    fn handleOrdersList(ctx: *ServerContext, req: *httpz.Request, res: *httpz.Response) !void {
        ctx.addCorsHeaders(req, res);
        ctx.incrementRequestCount();

        // Check for exchange filter via query string
        const query_map = req.query() catch null;
        const exchange_filter: ?[]const u8 = if (query_map) |qm| qm.get("exchange") else null;

        if (!ctx.deps.hasExchanges()) {
            try returnMockOrders(res);
            return;
        }

        // Build response with orders from all or specific exchange(s)
        var all_orders: std.ArrayListUnmanaged(OrderSummary) = .empty;
        defer all_orders.deinit(ctx.allocator);

        var grand_total_orders: usize = 0;

        var iter = ctx.deps.iterator();
        while (iter.next()) |entry| {
            const name = entry.key_ptr.*;

            // Skip if filtering by specific exchange
            if (exchange_filter) |filter| {
                if (!std.mem.eql(u8, filter, "all") and !std.mem.eql(u8, name, filter)) {
                    continue;
                }
            }

            const exchange_entry = entry.value_ptr.*;
            const orders = exchange_entry.interface.getOpenOrders(null) catch |err| {
                try all_orders.append(ctx.allocator, .{
                    .exchange = name,
                    .order_count = 0,
                    .status = @errorName(err),
                });
                continue;
            };
            defer ctx.allocator.free(orders);

            try all_orders.append(ctx.allocator, .{
                .exchange = name,
                .order_count = orders.len,
                .status = "ok",
            });

            grand_total_orders += orders.len;
        }

        try res.json(.{
            .orders_by_exchange = all_orders.items,
            .summary = .{
                .total_orders = grand_total_orders,
                .exchanges_queried = all_orders.items.len,
            },
            .filter = exchange_filter orelse "all",
        }, .{});
    }

    fn returnMockOrders(res: *httpz.Response) !void {
        try res.json(.{
            .orders = &[_]struct {
                id: []const u8,
                pair: []const u8,
                side: []const u8,
                order_type: []const u8,
                size: f64,
                price: f64,
                status: []const u8,
            }{
                .{
                    .id = "ord_001",
                    .pair = "BTC-USDT",
                    .side = "buy",
                    .order_type = "limit",
                    .size = 0.1,
                    .price = 41000.0,
                    .status = "open",
                },
            },
            .total = 1,
            .source = "mock",
        }, .{});
    }

    fn handleOrderCreate(ctx: *ServerContext, req: *httpz.Request, res: *httpz.Response) !void {
        ctx.addCorsHeaders(req, res);
        ctx.incrementRequestCount();

        const body = req.body() orelse {
            res.setStatus(.bad_request);
            try res.json(.{ .@"error" = "Missing request body" }, .{});
            return;
        };

        const OrderRequestJson = struct {
            pair: []const u8,
            side: []const u8,
            order_type: []const u8 = "limit",
            size: f64,
            price: ?f64 = null,
            exchange: ?[]const u8 = null, // Optional exchange filter
        };

        const parsed = std.json.parseFromSlice(OrderRequestJson, req.arena, body, .{}) catch {
            res.setStatus(.bad_request);
            try res.json(.{
                .@"error" = "Invalid JSON format",
                .expected = "{ \"pair\": \"BTC-USDT\", \"side\": \"buy\", \"size\": 0.1, \"price\": 42000, \"exchange\": \"hyperliquid\" }",
            }, .{});
            return;
        };

        const order_req = parsed.value;

        // Validate side
        const side = config_mod.Side.fromString(order_req.side) catch {
            res.setStatus(.bad_request);
            try res.json(.{ .@"error" = "Invalid side, must be 'buy' or 'sell'" }, .{});
            return;
        };

        // Validate order type
        const order_type = config_mod.OrderType.fromString(order_req.order_type) catch {
            res.setStatus(.bad_request);
            try res.json(.{ .@"error" = "Invalid order_type, must be 'market' or 'limit'" }, .{});
            return;
        };

        // Limit orders require price
        if (order_type == .limit and order_req.price == null) {
            res.setStatus(.bad_request);
            try res.json(.{ .@"error" = "Limit orders require a price" }, .{});
            return;
        }

        // Parse trading pair
        const pair = config_mod.TradingPair.fromSymbol(order_req.pair) catch {
            res.setStatus(.bad_request);
            try res.json(.{ .@"error" = "Invalid pair format, use 'BTC-USDT' or 'BTC/USDT'" }, .{});
            return;
        };

        // Check if exchange is configured
        if (!ctx.deps.hasExchanges()) {
            res.setStatus(.service_unavailable);
            try res.json(.{ .@"error" = "No exchange configured" }, .{});
            return;
        }

        // Get exchange (use specified or first available)
        const exchange_name = order_req.exchange orelse blk: {
            var iter = ctx.deps.iterator();
            if (iter.next()) |entry| {
                break :blk entry.key_ptr.*;
            }
            res.setStatus(.service_unavailable);
            try res.json(.{ .@"error" = "No exchange available" }, .{});
            return;
        };

        const exchange_entry = ctx.deps.getExchange(exchange_name) orelse {
            res.setStatus(.not_found);
            try res.json(.{ .@"error" = "Exchange not found", .exchange = exchange_name }, .{});
            return;
        };

        // Create order request
        const exchange_order_req = config_mod.OrderRequest{
            .pair = pair,
            .side = side,
            .order_type = order_type,
            .amount = config_mod.Decimal.fromFloat(order_req.size),
            .price = if (order_req.price) |p| config_mod.Decimal.fromFloat(p) else null,
        };

        // Submit order to exchange
        const order = exchange_entry.interface.createOrder(exchange_order_req) catch |err| {
            res.setStatus(.internal_server_error);
            try res.json(.{
                .@"error" = "Failed to create order",
                .details = @errorName(err),
                .exchange = exchange_name,
            }, .{});
            return;
        };

        res.setStatus(.created);
        try res.json(.{
            .id = order.exchange_order_id,
            .pair = order_req.pair,
            .side = order_req.side,
            .order_type = order_req.order_type,
            .size = order_req.size,
            .price = order_req.price,
            .filled_size = order.filled_amount.toFloat(),
            .status = order.status.toString(),
            .exchange = exchange_name,
            .created_at = @divFloor(order.created_at.millis, 1000),
            .message = "Order created successfully",
        }, .{});
    }

    fn handleOrderCancel(ctx: *ServerContext, req: *httpz.Request, res: *httpz.Response) !void {
        ctx.addCorsHeaders(req, res);
        ctx.incrementRequestCount();

        const id_str = req.param("id") orelse {
            res.setStatus(.bad_request);
            try res.json(.{ .@"error" = "Missing order ID" }, .{});
            return;
        };

        // Parse order ID
        const order_id = std.fmt.parseInt(u64, id_str, 10) catch {
            res.setStatus(.bad_request);
            try res.json(.{ .@"error" = "Invalid order ID format" }, .{});
            return;
        };

        // Check for exchange query param
        const query_map = req.query() catch null;
        const exchange_filter: ?[]const u8 = if (query_map) |qm| qm.get("exchange") else null;

        // Check if exchange is configured
        if (!ctx.deps.hasExchanges()) {
            res.setStatus(.service_unavailable);
            try res.json(.{ .@"error" = "No exchange configured" }, .{});
            return;
        }

        // Get exchange (use specified or first available)
        const exchange_name = exchange_filter orelse blk: {
            var iter = ctx.deps.iterator();
            if (iter.next()) |entry| {
                break :blk entry.key_ptr.*;
            }
            res.setStatus(.service_unavailable);
            try res.json(.{ .@"error" = "No exchange available" }, .{});
            return;
        };

        const exchange_entry = ctx.deps.getExchange(exchange_name) orelse {
            res.setStatus(.not_found);
            try res.json(.{ .@"error" = "Exchange not found", .exchange = exchange_name }, .{});
            return;
        };

        // Cancel order on exchange
        exchange_entry.interface.cancelOrder(order_id) catch |err| {
            res.setStatus(.internal_server_error);
            try res.json(.{
                .@"error" = "Failed to cancel order",
                .details = @errorName(err),
                .order_id = order_id,
                .exchange = exchange_name,
            }, .{});
            return;
        };

        try res.json(.{
            .id = order_id,
            .status = "cancelled",
            .exchange = exchange_name,
            .cancelled_at = std.time.timestamp(),
            .message = "Order cancelled successfully",
        }, .{});
    }

    // ========================================================================
    // Route Handlers - Account (Multi-Exchange)
    // ========================================================================

    fn handleAccountGet(ctx: *ServerContext, req: *httpz.Request, res: *httpz.Response) !void {
        ctx.addCorsHeaders(req, res);
        ctx.incrementRequestCount();

        if (!ctx.deps.hasExchanges()) {
            try res.json(.{
                .accounts = &[_]AccountInfo{},
                .total = 0,
                .note = "No exchanges configured",
            }, .{});
            return;
        }

        // Build list of all accounts
        var accounts: std.ArrayListUnmanaged(AccountInfo) = .empty;
        defer accounts.deinit(ctx.allocator);

        var iter = ctx.deps.iterator();
        while (iter.next()) |entry| {
            const name = entry.key_ptr.*;
            const exchange_entry = entry.value_ptr.*;
            const network = if (exchange_entry.config.testnet) "testnet" else "mainnet";
            const status = if (exchange_entry.interface.isConnected()) "connected" else "disconnected";

            try accounts.append(ctx.allocator, .{
                .exchange = name,
                .account_id = exchange_entry.config.api_key,
                .account_type = "futures",
                .network = network,
                .status = status,
            });
        }

        try res.json(.{
            .accounts = accounts.items,
            .total = accounts.items.len,
        }, .{});
    }

    fn handleAccountBalance(ctx: *ServerContext, req: *httpz.Request, res: *httpz.Response) !void {
        ctx.addCorsHeaders(req, res);
        ctx.incrementRequestCount();

        // Check for exchange filter via query string
        const query_map = req.query() catch null;
        const exchange_filter: ?[]const u8 = if (query_map) |qm| qm.get("exchange") else null;

        if (!ctx.deps.hasExchanges()) {
            try returnMockBalance(res);
            return;
        }

        // Build response with balances from all or specific exchange(s)
        var all_balances: std.ArrayListUnmanaged(BalanceSummary) = .empty;
        defer all_balances.deinit(ctx.allocator);

        var grand_total: f64 = 0;
        var grand_available: f64 = 0;
        var grand_locked: f64 = 0;

        var iter = ctx.deps.iterator();
        while (iter.next()) |entry| {
            const name = entry.key_ptr.*;

            // Skip if filtering by specific exchange
            if (exchange_filter) |filter| {
                if (!std.mem.eql(u8, filter, "all") and !std.mem.eql(u8, name, filter)) {
                    continue;
                }
            }

            const exchange_entry = entry.value_ptr.*;
            const balances = exchange_entry.interface.getBalance() catch |err| {
                try all_balances.append(ctx.allocator, .{
                    .exchange = name,
                    .total = 0,
                    .available = 0,
                    .locked = 0,
                    .status = @errorName(err),
                });
                continue;
            };
            defer ctx.allocator.free(balances);

            // Sum up all balances for this exchange
            var exchange_total: f64 = 0;
            var exchange_available: f64 = 0;
            var exchange_locked: f64 = 0;
            for (balances) |bal| {
                exchange_total += bal.total.toFloat();
                exchange_available += bal.available.toFloat();
                exchange_locked += bal.locked.toFloat();
            }

            try all_balances.append(ctx.allocator, .{
                .exchange = name,
                .total = exchange_total,
                .available = exchange_available,
                .locked = exchange_locked,
                .status = "ok",
            });

            grand_total += exchange_total;
            grand_available += exchange_available;
            grand_locked += exchange_locked;
        }

        try res.json(.{
            .balances_by_exchange = all_balances.items,
            .summary = .{
                .total_value = grand_total,
                .total_available = grand_available,
                .total_locked = grand_locked,
                .exchanges_queried = all_balances.items.len,
            },
            .filter = exchange_filter orelse "all",
        }, .{});
    }

    fn returnMockBalance(res: *httpz.Response) !void {
        try res.json(.{
            .balances = &[_]struct {
                asset: []const u8,
                free: f64,
                locked: f64,
                total: f64,
            }{
                .{ .asset = "USDT", .free = 8500.0, .locked = 5666.67, .total = 14166.67 },
            },
            .account_value = 14166.67,
            .withdrawable = 8500.0,
            .margin_used = 5666.67,
            .unrealized_pnl = 750.0,
            .source = "mock",
        }, .{});
    }

    // ========================================================================
    // Route Handlers - Metrics
    // ========================================================================

    fn handleMetrics(ctx: *ServerContext, req: *httpz.Request, res: *httpz.Response) !void {
        ctx.addCorsHeaders(req, res);
        res.content_type = httpz.ContentType.TEXT;

        const writer = res.writer();

        // ====================================================================
        // System Metrics
        // ====================================================================

        // Uptime metric
        try writer.writeAll("# HELP zigquant_uptime_seconds Server uptime in seconds\n");
        try writer.writeAll("# TYPE zigquant_uptime_seconds gauge\n");
        try writer.print("zigquant_uptime_seconds {d}\n\n", .{ctx.uptime()});

        // Request count metric
        try writer.writeAll("# HELP zigquant_api_requests_total Total API requests\n");
        try writer.writeAll("# TYPE zigquant_api_requests_total counter\n");
        try writer.print("zigquant_api_requests_total {d}\n\n", .{ctx.getRequestCount()});

        // Server info
        try writer.writeAll("# HELP zigquant_info Server information\n");
        try writer.writeAll("# TYPE zigquant_info gauge\n");
        try writer.writeAll("zigquant_info{version=\"1.0.0\",api_version=\"v1\"} 1\n\n");

        // ====================================================================
        // Exchange Metrics
        // ====================================================================

        // Exchange connection status
        try writer.writeAll("# HELP zigquant_exchange_connected Exchange connection status (1=connected, 0=disconnected)\n");
        try writer.writeAll("# TYPE zigquant_exchange_connected gauge\n");

        var total_exchanges: usize = 0;
        var connected_exchanges: usize = 0;

        var iter = ctx.deps.iterator();
        while (iter.next()) |entry| {
            const name = entry.key_ptr.*;
            const exchange_entry = entry.value_ptr.*;
            const is_connected: u8 = if (exchange_entry.interface.isConnected()) 1 else 0;
            const network = if (exchange_entry.config.testnet) "testnet" else "mainnet";

            try writer.print("zigquant_exchange_connected{{exchange=\"{s}\",network=\"{s}\"}} {d}\n", .{ name, network, is_connected });

            total_exchanges += 1;
            if (is_connected == 1) connected_exchanges += 1;
        }
        try writer.writeAll("\n");

        // Exchanges summary
        try writer.writeAll("# HELP zigquant_exchanges_total Total number of configured exchanges\n");
        try writer.writeAll("# TYPE zigquant_exchanges_total gauge\n");
        try writer.print("zigquant_exchanges_total {d}\n\n", .{total_exchanges});

        try writer.writeAll("# HELP zigquant_exchanges_connected Number of connected exchanges\n");
        try writer.writeAll("# TYPE zigquant_exchanges_connected gauge\n");
        try writer.print("zigquant_exchanges_connected {d}\n\n", .{connected_exchanges});

        // ====================================================================
        // Trading Metrics (from exchanges)
        // ====================================================================

        // Positions
        try writer.writeAll("# HELP zigquant_positions_count Number of open positions per exchange\n");
        try writer.writeAll("# TYPE zigquant_positions_count gauge\n");

        try writer.writeAll("# HELP zigquant_positions_pnl_total Total unrealized PnL per exchange\n");
        try writer.writeAll("# TYPE zigquant_positions_pnl_total gauge\n");

        try writer.writeAll("# HELP zigquant_positions_margin_total Total margin used per exchange\n");
        try writer.writeAll("# TYPE zigquant_positions_margin_total gauge\n");

        var iter2 = ctx.deps.iterator();
        while (iter2.next()) |entry| {
            const name = entry.key_ptr.*;
            const exchange_entry = entry.value_ptr.*;

            if (exchange_entry.interface.getPositions()) |positions| {
                defer ctx.allocator.free(positions);

                var total_pnl: f64 = 0;
                var total_margin: f64 = 0;
                for (positions) |pos| {
                    total_pnl += pos.unrealized_pnl.toFloat();
                    total_margin += pos.margin_used.toFloat();
                }

                try writer.print("zigquant_positions_count{{exchange=\"{s}\"}} {d}\n", .{ name, positions.len });
                try writer.print("zigquant_positions_pnl_total{{exchange=\"{s}\"}} {d:.4}\n", .{ name, total_pnl });
                try writer.print("zigquant_positions_margin_total{{exchange=\"{s}\"}} {d:.4}\n", .{ name, total_margin });
            } else |_| {
                try writer.print("zigquant_positions_count{{exchange=\"{s}\"}} 0\n", .{name});
            }
        }
        try writer.writeAll("\n");

        // Orders
        try writer.writeAll("# HELP zigquant_orders_open_count Number of open orders per exchange\n");
        try writer.writeAll("# TYPE zigquant_orders_open_count gauge\n");

        var iter3 = ctx.deps.iterator();
        while (iter3.next()) |entry| {
            const name = entry.key_ptr.*;
            const exchange_entry = entry.value_ptr.*;

            if (exchange_entry.interface.getOpenOrders(null)) |orders| {
                defer ctx.allocator.free(orders);
                try writer.print("zigquant_orders_open_count{{exchange=\"{s}\"}} {d}\n", .{ name, orders.len });
            } else |_| {
                try writer.print("zigquant_orders_open_count{{exchange=\"{s}\"}} 0\n", .{name});
            }
        }
        try writer.writeAll("\n");

        // Balance
        try writer.writeAll("# HELP zigquant_balance_total Total account balance per exchange (in quote currency)\n");
        try writer.writeAll("# TYPE zigquant_balance_total gauge\n");

        try writer.writeAll("# HELP zigquant_balance_available Available balance per exchange\n");
        try writer.writeAll("# TYPE zigquant_balance_available gauge\n");

        var iter4 = ctx.deps.iterator();
        while (iter4.next()) |entry| {
            const name = entry.key_ptr.*;
            const exchange_entry = entry.value_ptr.*;

            if (exchange_entry.interface.getBalance()) |balances| {
                defer ctx.allocator.free(balances);

                var total: f64 = 0;
                var available: f64 = 0;
                for (balances) |bal| {
                    total += bal.total.toFloat();
                    available += bal.available.toFloat();
                }

                try writer.print("zigquant_balance_total{{exchange=\"{s}\"}} {d:.4}\n", .{ name, total });
                try writer.print("zigquant_balance_available{{exchange=\"{s}\"}} {d:.4}\n", .{ name, available });
            } else |_| {
                try writer.print("zigquant_balance_total{{exchange=\"{s}\"}} 0\n", .{name});
                try writer.print("zigquant_balance_available{{exchange=\"{s}\"}} 0\n", .{name});
            }
        }
    }

    // ========================================================================
    // Helper Functions
    // ========================================================================

    /// Validate user credentials (demo implementation)
    /// In production, use proper password hashing and database lookup
    fn validateCredentials(username: []const u8, password: []const u8) bool {
        const demo_users = [_]struct { user: []const u8, pass: []const u8 }{
            .{ .user = "admin", .pass = "admin123" },
            .{ .user = "trader", .pass = "trader123" },
        };

        for (demo_users) |u| {
            if (std.mem.eql(u8, username, u.user) and std.mem.eql(u8, password, u.pass)) {
                return true;
            }
        }
        return false;
    }
};

test "ApiServer: basic initialization" {
    // Basic compile test - full tests require httpz mock
}
