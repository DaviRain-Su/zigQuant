//! zigQuant CLI - Command Line Interface
//!
//! 提供命令行界面用于：
//! - 查询市场数据
//! - 执行交易操作
//! - 管理账户和仓位
//! - 交互式 REPL 模式

const std = @import("std");
const zigQuant = @import("zigQuant");
const format = @import("format.zig");

const Config = zigQuant.Config;
const Logger = zigQuant.Logger;
const IExchange = zigQuant.IExchange;
const ExchangeRegistry = zigQuant.ExchangeRegistry;
const HyperliquidConnector = zigQuant.HyperliquidConnector;
const OrderManager = zigQuant.OrderManager;
const PositionTracker = zigQuant.PositionTracker;

// ============================================================================
// CLI Context
// ============================================================================

/// CLI application context
pub const CLI = struct {
    allocator: std.mem.Allocator,
    config: Config.AppConfig,
    config_parsed: std.json.Parsed(zigQuant.AppConfig), // Store parsed config for cleanup
    console_writer: zigQuant.ConsoleWriter(std.fs.File),
    logger: Logger,
    registry: ExchangeRegistry,
    connector: ?*HyperliquidConnector = null, // Store connector for cleanup
    order_manager: ?OrderManager = null,
    position_tracker: ?PositionTracker = null,
    stdout_buffer: []u8,
    stderr_buffer: []u8,
    stdout: std.fs.File.Writer,
    stderr: std.fs.File.Writer,

    pub fn init(
        allocator: std.mem.Allocator,
        config_path: ?[]const u8,
    ) !*CLI {
        const self = try allocator.create(CLI);
        errdefer allocator.destroy(self);

        // Load config
        const path = config_path orelse "config.json";
        const file_content = std.fs.cwd().readFileAlloc(
            allocator,
            path,
            1024 * 1024, // 1MB max
        ) catch |err| {
            std.debug.print("Failed to read config file '{s}': {}\n", .{ path, err });
            return error.ConfigLoadFailed;
        };
        defer allocator.free(file_content);

        const config_parsed = Config.ConfigLoader.loadFromJSON(allocator, file_content, zigQuant.AppConfig) catch |err| {
            std.debug.print("Failed to parse config from '{s}': {}\n", .{ path, err });
            return error.ConfigLoadFailed;
        };
        errdefer config_parsed.deinit();

        // Allocate buffers for stdout/stderr
        const stdout_buffer = try allocator.alloc(u8, 4096);
        errdefer allocator.free(stdout_buffer);
        const stderr_buffer = try allocator.alloc(u8, 4096);
        errdefer allocator.free(stderr_buffer);

        // Initialize struct with basic fields first
        self.* = .{
            .allocator = allocator,
            .config = config_parsed.value,
            .config_parsed = config_parsed,
            .console_writer = undefined, // Will initialize next
            .logger = undefined, // Will initialize after console_writer
            .registry = undefined, // Will initialize after logger
            .stdout_buffer = stdout_buffer,
            .stderr_buffer = stderr_buffer,
            .stdout = std.fs.File.stdout().writer(stdout_buffer),
            .stderr = std.fs.File.stderr().writer(stderr_buffer),
        };

        // Now initialize console_writer, logger, and registry
        const ConsoleWriterType = zigQuant.ConsoleWriter(std.fs.File);
        self.console_writer = ConsoleWriterType.init(allocator, std.fs.File.stderr());
        self.logger = Logger.init(allocator, self.console_writer.writer(), .info);

        // Create exchange registry
        self.registry = ExchangeRegistry.init(allocator, self.logger);

        return self;
    }

    pub fn deinit(self: *CLI) void {
        if (self.position_tracker) |*pt| {
            pt.deinit();
        }
        if (self.order_manager) |*om| {
            om.deinit();
        }
        self.registry.deinit();
        // Destroy connector if it was created
        if (self.connector) |connector| {
            connector.destroy();
        }
        self.logger.deinit();
        self.allocator.free(self.stdout_buffer);
        self.allocator.free(self.stderr_buffer);
        // Free config_parsed arena
        self.config_parsed.deinit();
        self.allocator.destroy(self);
    }

    /// Connect to exchange
    pub fn connect(self: *CLI) !void {
        // Get first exchange config
        if (self.config.exchanges.len == 0) {
            return error.NoExchangeConfigured;
        }

        const exchange_config = self.config.exchanges[0];

        // Create Hyperliquid connector
        const connector = try HyperliquidConnector.create(
            self.allocator,
            exchange_config,
            self.logger,
        );
        // Store connector for cleanup
        self.connector = connector;

        // Register exchange
        const exchange = connector.interface();
        try self.registry.setExchange(exchange, exchange_config);

        // Connect
        try self.logger.info("Connecting to {s}...", .{exchange_config.name});
        try self.registry.connectAll();
        try self.logger.info("Connected successfully", .{});

        // Initialize trading components
        const ex = try self.registry.getExchange();
        self.order_manager = OrderManager.init(self.allocator, ex, self.logger);
        self.position_tracker = PositionTracker.init(self.allocator, ex, self.logger);
    }

    /// Execute a command
    pub fn executeCommand(self: *CLI, args: []const []const u8) anyerror!void {
        if (args.len == 0) {
            try printHelp(&self.stdout.interface);
            return;
        }

        const command = args[0];

        if (std.mem.eql(u8, command, "help") or std.mem.eql(u8, command, "--help") or std.mem.eql(u8, command, "-h")) {
            try printHelp(&self.stdout.interface);
        } else if (std.mem.eql(u8, command, "price")) {
            try self.cmdPrice(args[1..]);
        } else if (std.mem.eql(u8, command, "book")) {
            try self.cmdBook(args[1..]);
        } else if (std.mem.eql(u8, command, "balance")) {
            try self.cmdBalance(args[1..]);
        } else if (std.mem.eql(u8, command, "positions")) {
            try self.cmdPositions(args[1..]);
        } else if (std.mem.eql(u8, command, "orders")) {
            try self.cmdOrders(args[1..]);
        } else if (std.mem.eql(u8, command, "buy")) {
            try self.cmdBuy(args[1..]);
        } else if (std.mem.eql(u8, command, "sell")) {
            try self.cmdSell(args[1..]);
        } else if (std.mem.eql(u8, command, "cancel")) {
            try self.cmdCancel(args[1..]);
        } else if (std.mem.eql(u8, command, "cancel-all")) {
            try self.cmdCancelAll(args[1..]);
        } else if (std.mem.eql(u8, command, "repl")) {
            const repl = @import("repl.zig");
            try repl.run(self);
        } else {
            try format.printError(&self.stderr.interface, "Unknown command: {s}", .{command});
            try (&self.stderr.interface).writeAll("Use 'help' to see available commands\n");
        }
    }

    // ========================================================================
    // Commands - Market Data
    // ========================================================================

    fn cmdPrice(self: *CLI, args: []const []const u8) !void {
        if (args.len < 1) {
            try format.printError(&self.stderr.interface, "Usage: price <pair>", .{});
            try (&self.stderr.interface).writeAll("Example: price BTC-USDC\n");
            return;
        }

        const pair_str = args[0];
        var parts = std.mem.splitScalar(u8, pair_str, '-');
        const base = parts.next() orelse return error.InvalidPair;
        const quote = parts.next() orelse "USDC";

        const pair = zigQuant.TradingPair{ .base = base, .quote = quote };

        try format.printHeader(&self.stdout.interface, "Market Price");

        const exchange = try self.registry.getExchange();
        const ticker = try exchange.getTicker(pair);

        const bid_str = try format.formatPrice(self.allocator, ticker.bid.toFloat());
        defer self.allocator.free(bid_str);
        const ask_str = try format.formatPrice(self.allocator, ticker.ask.toFloat());
        defer self.allocator.free(ask_str);
        const last_str = try format.formatPrice(self.allocator, ticker.last.toFloat());
        defer self.allocator.free(last_str);

        try (&self.stdout.interface).print("  Symbol:    {s}-{s}\n", .{ pair.base, pair.quote });
        try format.printColored(&self.stdout.interface, .green, "  Bid:       ${s}\n", .{bid_str});
        try format.printColored(&self.stdout.interface, .red, "  Ask:       ${s}\n", .{ask_str});
        try format.printColored(&self.stdout.interface, .cyan, "  Last:      ${s}\n", .{last_str});

        const mid = ticker.bid.add(ticker.ask).div(zigQuant.Decimal.fromInt(2)) catch unreachable;
        const mid_str = try format.formatPrice(self.allocator, mid.toFloat());
        defer self.allocator.free(mid_str);
        try (&self.stdout.interface).print("  Mid:       ${s}\n\n", .{mid_str});
    }

    fn cmdBook(self: *CLI, args: []const []const u8) !void {
        if (args.len < 1) {
            try format.printError(&self.stderr.interface, "Usage: book <pair> [depth]", .{});
            try (&self.stderr.interface).writeAll("Example: book BTC-USDC 10\n");
            return;
        }

        const pair_str = args[0];
        var parts = std.mem.splitScalar(u8, pair_str, '-');
        const base = parts.next() orelse return error.InvalidPair;
        const quote = parts.next() orelse "USDC";

        const depth: u32 = if (args.len > 1)
            std.fmt.parseInt(u32, args[1], 10) catch 10
        else
            10;

        const pair = zigQuant.TradingPair{ .base = base, .quote = quote };

        try format.printHeader(&self.stdout.interface, "Order Book");
        try (&self.stdout.interface).print("  Symbol: {s}-{s}  Depth: {d}\n\n", .{ pair.base, pair.quote, depth });

        const exchange = try self.registry.getExchange();
        const book = try exchange.getOrderbook(pair, depth);
        defer self.allocator.free(book.bids);
        defer self.allocator.free(book.asks);

        // Print Asks (from high to low)
        try format.printColored(&self.stdout.interface, .red, "  ASKS\n", .{});
        try format.printSeparator(&self.stdout.interface);

        const ask_count = @min(depth, @as(u32, @intCast(book.asks.len)));
        if (ask_count > 0) {
            var i: usize = ask_count;
            while (i > 0) {
                i -= 1;
                const ask = book.asks[i];
                const price_str = try format.formatPrice(self.allocator, ask.price.toFloat());
                defer self.allocator.free(price_str);
                const size_str = try format.formatQuantity(self.allocator, ask.quantity.toFloat());
                defer self.allocator.free(size_str);
                try (&self.stdout.interface).print("  ${s:<12}  {s:>12}\n", .{ price_str, size_str });
            }
        }

        try (&self.stdout.interface).writeAll("\n");

        // Print Bids (from high to low)
        try format.printColored(&self.stdout.interface, .green, "  BIDS\n", .{});
        try format.printSeparator(&self.stdout.interface);

        const bid_count = @min(depth, @as(u32, @intCast(book.bids.len)));
        for (book.bids[0..bid_count]) |bid| {
            const price_str = try format.formatPrice(self.allocator, bid.price.toFloat());
            defer self.allocator.free(price_str);
            const size_str = try format.formatQuantity(self.allocator, bid.quantity.toFloat());
            defer self.allocator.free(size_str);
            try (&self.stdout.interface).print("  ${s:<12}  {s:>12}\n", .{ price_str, size_str });
        }

        try (&self.stdout.interface).writeAll("\n");
    }

    // ========================================================================
    // Commands - Account
    // ========================================================================

    fn cmdBalance(self: *CLI, _: []const []const u8) !void {
        try format.printHeader(&self.stdout.interface, "Account Balance");

        const exchange = try self.registry.getExchange();
        const balances = try exchange.getBalance();
        defer self.allocator.free(balances);

        if (balances.len == 0) {
            try (&self.stdout.interface).writeAll("  No balances found\n\n");
            return;
        }

        for (balances) |balance| {
            const total_str = try format.formatPrice(self.allocator, balance.total.toFloat());
            defer self.allocator.free(total_str);
            const available_str = try format.formatPrice(self.allocator, balance.available.toFloat());
            defer self.allocator.free(available_str);
            const locked_str = try format.formatPrice(self.allocator, balance.locked.toFloat());
            defer self.allocator.free(locked_str);

            try (&self.stdout.interface).print("  {s}:\n", .{balance.asset});
            try (&self.stdout.interface).print("    Total:     {s}\n", .{total_str});
            try (&self.stdout.interface).print("    Available: {s}\n", .{available_str});
            try (&self.stdout.interface).print("    Locked:    {s}\n", .{locked_str});
        }

        try (&self.stdout.interface).writeAll("\n");
    }

    fn cmdPositions(self: *CLI, _: []const []const u8) !void {
        try format.printHeader(&self.stdout.interface, "Positions");

        const exchange = try self.registry.getExchange();
        const positions = try exchange.getPositions();
        defer self.allocator.free(positions);

        if (positions.len == 0) {
            try (&self.stdout.interface).writeAll("  No open positions\n\n");
            return;
        }

        for (positions) |pos| {
            const side_color: format.Color = if (pos.side == .buy) .green else .red;
            const size_str = try format.formatQuantity(self.allocator, pos.size.toFloat());
            defer self.allocator.free(size_str);

            try (&self.stdout.interface).print("  {s}-{s}  ", .{ pos.pair.base, pos.pair.quote });
            try format.printColored(&self.stdout.interface, side_color, "{s}", .{@tagName(pos.side)});
            try (&self.stdout.interface).print("  {s}\n", .{size_str});

            const entry_str = try format.formatPrice(self.allocator, pos.entry_price.toFloat());
            defer self.allocator.free(entry_str);
            try (&self.stdout.interface).print("    Entry:  ${s}\n", .{entry_str});

            if (pos.mark_price) |mark| {
                const mark_str = try format.formatPrice(self.allocator, mark.toFloat());
                defer self.allocator.free(mark_str);
                try (&self.stdout.interface).print("    Mark:   ${s}\n", .{mark_str});
            }

            const pnl_color: format.Color = if (pos.unrealized_pnl.isPositive()) .green else .red;
            const pnl_str = try format.formatPrice(self.allocator, pos.unrealized_pnl.toFloat());
            defer self.allocator.free(pnl_str);
            try (&self.stdout.interface).writeAll("    PnL:    ");
            try format.printColoredLine(&self.stdout.interface, pnl_color, "${s}", .{pnl_str});
        }

        try (&self.stdout.interface).writeAll("\n");
    }

    fn cmdOrders(self: *CLI, _: []const []const u8) !void {
        try format.printHeader(&self.stdout.interface, "Open Orders");

        const exchange = try self.registry.getExchange();
        const orders = try exchange.getOpenOrders(null); // Get all open orders
        defer self.allocator.free(orders);

        if (orders.len == 0) {
            try (&self.stdout.interface).writeAll("  No open orders\n\n");
            return;
        }

        // Print header
        try (&self.stdout.interface).writeAll("  ID        | Pair      | Side | Type   | Price      | Amount     | Filled\n");
        try (&self.stdout.interface).writeAll("  ──────────┼───────────┼──────┼────────┼────────────┼────────────┼────────\n");

        for (orders) |order| {
            const price_str = if (order.price) |p|
                try format.formatPrice(self.allocator, p.toFloat())
            else
                try self.allocator.dupe(u8, "MARKET");
            defer self.allocator.free(price_str);

            const amount_str = try format.formatQuantity(self.allocator, order.amount.toFloat());
            defer self.allocator.free(amount_str);
            const filled_str = try format.formatQuantity(self.allocator, order.filled_amount.toFloat());
            defer self.allocator.free(filled_str);

            const side_str = @tagName(order.side);
            const type_str = @tagName(order.order_type);

            const order_id = order.exchange_order_id orelse 0;

            try (&self.stdout.interface).print("  {d:<9} | {s:<4}-{s:<4} | {s:<4} | {s:<6} | ${s:<9} | {s:<10} | {s}\n", .{
                order_id,
                order.pair.base,
                order.pair.quote,
                side_str,
                type_str,
                price_str,
                amount_str,
                filled_str,
            });
        }

        try (&self.stdout.interface).writeAll("\n");
    }

    // ========================================================================
    // Commands - Trading
    // ========================================================================

    fn cmdBuy(self: *CLI, args: []const []const u8) !void {
        if (args.len < 3) {
            try format.printError(&self.stderr.interface, "Usage: buy <pair> <size> <price>", .{});
            try (&self.stderr.interface).writeAll("Example: buy BTC-USDC 0.01 50000\n");
            return;
        }

        const pair_str = args[0];
        var parts = std.mem.splitScalar(u8, pair_str, '-');
        const base = parts.next() orelse return error.InvalidPair;
        const quote = parts.next() orelse "USDC";

        const size = try zigQuant.Decimal.fromString(args[1]);
        const price = try zigQuant.Decimal.fromString(args[2]);

        const pair = zigQuant.TradingPair{ .base = base, .quote = quote };

        const order_request = zigQuant.OrderRequest{
            .pair = pair,
            .side = .buy,
            .order_type = .limit,
            .amount = size,
            .price = price,
            .time_in_force = .gtc,
            .reduce_only = false,
        };

        try format.printInfo(&self.stdout.interface, "Placing BUY order...", .{});
        const exchange = try self.registry.getExchange();
        const order = try exchange.createOrder(order_request);

        try format.printSuccess(&self.stdout.interface, "Order placed successfully!", .{});
        try (&self.stdout.interface).print("  Order ID: {?}\n", .{order.exchange_order_id});
        try (&self.stdout.interface).print("  Status:   {s}\n\n", .{@tagName(order.status)});
    }

    fn cmdSell(self: *CLI, args: []const []const u8) !void {
        if (args.len < 3) {
            try format.printError(&self.stderr.interface, "Usage: sell <pair> <size> <price>", .{});
            try (&self.stderr.interface).writeAll("Example: sell BTC-USDC 0.01 51000\n");
            return;
        }

        const pair_str = args[0];
        var parts = std.mem.splitScalar(u8, pair_str, '-');
        const base = parts.next() orelse return error.InvalidPair;
        const quote = parts.next() orelse "USDC";

        const size = try zigQuant.Decimal.fromString(args[1]);
        const price = try zigQuant.Decimal.fromString(args[2]);

        const pair = zigQuant.TradingPair{ .base = base, .quote = quote };

        const order_request = zigQuant.OrderRequest{
            .pair = pair,
            .side = .sell,
            .order_type = .limit,
            .amount = size,
            .price = price,
            .time_in_force = .gtc,
            .reduce_only = false,
        };

        try format.printInfo(&self.stdout.interface, "Placing SELL order...", .{});
        const exchange = try self.registry.getExchange();
        const order = try exchange.createOrder(order_request);

        try format.printSuccess(&self.stdout.interface, "Order placed successfully!", .{});
        try (&self.stdout.interface).print("  Order ID: {?}\n", .{order.exchange_order_id});
        try (&self.stdout.interface).print("  Status:   {s}\n\n", .{@tagName(order.status)});
    }

    fn cmdCancel(self: *CLI, args: []const []const u8) !void {
        if (args.len < 1) {
            try format.printError(&self.stderr.interface, "Usage: cancel <order_id>", .{});
            try (&self.stderr.interface).writeAll("Example: cancel 123456\n");
            return;
        }

        const order_id = try std.fmt.parseInt(u64, args[0], 10);

        try format.printInfo(&self.stdout.interface, "Cancelling order {d}...", .{order_id});
        const exchange = try self.registry.getExchange();
        try exchange.cancelOrder(order_id);

        try format.printSuccess(&self.stdout.interface, "Order cancelled successfully!", .{});
    }

    fn cmdCancelAll(self: *CLI, args: []const []const u8) !void {
        const pair: ?zigQuant.TradingPair = if (args.len > 0) blk: {
            const pair_str = args[0];
            var parts = std.mem.splitScalar(u8, pair_str, '-');
            const base = parts.next() orelse return error.InvalidPair;
            const quote = parts.next() orelse "USDC";
            break :blk zigQuant.TradingPair{ .base = base, .quote = quote };
        } else null;

        if (pair) |p| {
            try format.printInfo(&self.stdout.interface, "Cancelling all orders for {s}-{s}...", .{ p.base, p.quote });
        } else {
            try format.printInfo(&self.stdout.interface, "Cancelling all orders...", .{});
        }

        const exchange = try self.registry.getExchange();
        const count = try exchange.cancelAllOrders(pair);

        try format.printSuccess(&self.stdout.interface, "Cancelled {d} orders", .{count});
    }
};

// ============================================================================
// Help
// ============================================================================

fn printHelp(writer: anytype) !void {
    try format.printHeader(writer, "zigQuant CLI");

    try writer.writeAll(
        \\Usage: zigquant [options] <command> [args]
        \\
        \\Commands:
        \\  price <pair>                    查询价格
        \\  book <pair> [depth]             查询订单簿
        \\  balance                         查询余额
        \\  positions                       查询持仓
        \\  orders                          查询订单
        \\  buy <pair> <size> <price>       买入
        \\  sell <pair> <size> <price>      卖出
        \\  cancel <order_id>               撤单
        \\  cancel-all [pair]               撤销所有订单
        \\  repl                            交互式模式
        \\  help                            显示帮助
        \\
        \\Examples:
        \\  zigquant price BTC-USDC
        \\  zigquant book ETH-USDC 10
        \\  zigquant buy BTC-USDC 0.01 50000
        \\  zigquant positions
        \\  zigquant repl
        \\
        \\
    );
}
