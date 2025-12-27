//! PaperTradingEngine - 模拟交易引擎
//!
//! 使用真实市场数据进行模拟交易，不实际执行订单。
//! 为策略验证提供无风险的测试环境。
//!
//! ## 功能
//! - 连接真实市场数据
//! - 模拟订单执行
//! - 追踪账户余额和仓位
//! - 计算实时 PnL
//! - 生成交易统计报告

const std = @import("std");
const Allocator = std.mem.Allocator;

const Decimal = @import("../core/decimal.zig").Decimal;
const Timestamp = @import("../core/time.zig").Timestamp;
const MessageBus = @import("../core/message_bus.zig").MessageBus;
const Cache = @import("../core/cache.zig").Cache;
const Side = @import("../exchange/types.zig").Side;
const OrderType = @import("../exchange/types.zig").OrderType;

const execution_engine = @import("../core/execution_engine.zig");
const OrderRequest = execution_engine.OrderRequest;

const SimulatedAccount = @import("simulated_account.zig").SimulatedAccount;
const Stats = @import("simulated_account.zig").Stats;
const SimulatedExecutor = @import("simulated_executor.zig").SimulatedExecutor;
const SimulatedExecutorConfig = @import("simulated_executor.zig").SimulatedExecutorConfig;

/// Paper Trading 配置
pub const PaperTradingConfig = struct {
    /// 初始余额
    initial_balance: Decimal = Decimal.fromInt(10000),
    /// 手续费率 (默认 0.05%)
    commission_rate: Decimal = Decimal.fromFloat(0.0005),
    /// 滑点 (默认 0.01%)
    slippage: Decimal = Decimal.fromFloat(0.0001),
    /// 是否记录交易日志
    log_trades: bool = true,
    /// Tick 间隔 (毫秒)
    tick_interval_ms: u32 = 1000,
};

/// Paper Trading 引擎
pub const PaperTradingEngine = struct {
    allocator: Allocator,
    config: PaperTradingConfig,

    // 核心组件
    message_bus: MessageBus,
    cache: Cache,
    account: SimulatedAccount,
    executor: SimulatedExecutor,

    // 状态
    running: bool,
    start_time: ?Timestamp,
    tick_count: u64,

    const Self = @This();

    /// 初始化
    pub fn init(allocator: Allocator, config: PaperTradingConfig) Self {
        const message_bus = MessageBus.init(allocator);
        const cache = Cache.init(allocator, undefined, .{});
        const account = SimulatedAccount.init(allocator, config.initial_balance);

        const executor_config = SimulatedExecutorConfig{
            .commission_rate = config.commission_rate,
            .slippage = config.slippage,
            .log_trades = config.log_trades,
        };

        // Note: executor is initialized without valid pointers,
        // they will be set in connectComponents()
        const executor = SimulatedExecutor.init(
            allocator,
            undefined,
            null,
            null,
            executor_config,
        );

        return Self{
            .allocator = allocator,
            .config = config,
            .message_bus = message_bus,
            .cache = cache,
            .account = account,
            .executor = executor,
            .running = false,
            .start_time = null,
            .tick_count = 0,
        };
    }

    /// 连接内部组件 (初始化后必须调用)
    /// 由于 Zig 的值语义，init() 返回后结构体会被复制，
    /// 因此必须在接收结构体后调用此方法设置正确的指针。
    pub fn connectComponents(self: *Self) void {
        self.executor.account = &self.account;
        self.executor.cache = &self.cache;
        self.executor.message_bus = &self.message_bus;
        self.cache = Cache.init(self.allocator, &self.message_bus, .{});
    }

    /// 释放资源
    pub fn deinit(self: *Self) void {
        self.executor.deinit();
        self.account.deinit();
        self.cache.deinit();
        self.message_bus.deinit();
    }

    /// 启动 Paper Trading
    pub fn start(self: *Self) void {
        self.running = true;
        self.start_time = Timestamp.now();
        self.tick_count = 0;

        std.debug.print("\n", .{});
        std.debug.print("════════════════════════════════════════════════════\n", .{});
        std.debug.print("           Paper Trading Started\n", .{});
        std.debug.print("════════════════════════════════════════════════════\n", .{});
        std.debug.print("  Initial Balance: {d:.2} USDT\n", .{self.config.initial_balance.toFloat()});
        std.debug.print("  Commission Rate: {d:.4}%\n", .{self.config.commission_rate.toFloat() * 100});
        std.debug.print("  Slippage: {d:.4}%\n", .{self.config.slippage.toFloat() * 100});
        std.debug.print("════════════════════════════════════════════════════\n", .{});
        std.debug.print("\n", .{});
    }

    /// 停止 Paper Trading
    pub fn stop(self: *Self) void {
        self.running = false;
        self.printSummary();
    }

    /// 检查是否正在运行
    pub fn isRunning(self: *const Self) bool {
        return self.running;
    }

    /// 提交订单
    pub fn submitOrder(self: *Self, request: OrderRequest) !execution_engine.OrderResult {
        if (!self.running) {
            return execution_engine.OrderResult{
                .success = false,
                .error_code = 6001,
                .error_message = "Paper trading not running",
                .timestamp = Timestamp.now(),
            };
        }

        return self.executor.executeOrder(request);
    }

    /// 买入
    pub fn buy(self: *Self, symbol: []const u8, quantity: Decimal, price: ?Decimal) !execution_engine.OrderResult {
        const order_id = try self.generateOrderId();

        return self.submitOrder(.{
            .client_order_id = order_id,
            .symbol = symbol,
            .side = .buy,
            .order_type = if (price != null) .limit else .market,
            .quantity = quantity,
            .price = price,
        });
    }

    /// 卖出
    pub fn sell(self: *Self, symbol: []const u8, quantity: Decimal, price: ?Decimal) !execution_engine.OrderResult {
        const order_id = try self.generateOrderId();

        return self.submitOrder(.{
            .client_order_id = order_id,
            .symbol = symbol,
            .side = .sell,
            .order_type = if (price != null) .limit else .market,
            .quantity = quantity,
            .price = price,
        });
    }

    /// 更新价格 (用于更新仓位 PnL)
    pub fn updatePrice(self: *Self, symbol: []const u8, price: Decimal) void {
        self.account.updatePositionPnl(symbol, price);
    }

    /// Tick 处理 (定期调用)
    pub fn tick(self: *Self) void {
        if (!self.running) return;

        self.tick_count += 1;

        // 处理限价单
        self.executor.processLimitOrders() catch {};
    }

    /// 获取账户统计
    pub fn getStats(self: *const Self) Stats {
        return self.account.getStats();
    }

    /// 获取当前余额
    pub fn getBalance(self: *const Self) Decimal {
        return self.account.current_balance;
    }

    /// 获取可用余额
    pub fn getAvailableBalance(self: *const Self) Decimal {
        return self.account.available_balance;
    }

    /// 获取总权益
    pub fn getEquity(self: *const Self) Decimal {
        return self.account.calculateTotalEquity();
    }

    /// 获取仓位
    pub fn getPosition(self: *const Self, symbol: []const u8) ?@import("simulated_account.zig").Position {
        return self.account.getPosition(symbol);
    }

    /// 打印统计摘要
    pub fn printSummary(self: *const Self) void {
        const stats = self.account.getStats();
        const run_duration = if (self.start_time) |start_ts|
            @as(f64, @floatFromInt(Timestamp.now().millis - start_ts.millis)) / 1000.0
        else
            0;

        std.debug.print("\n", .{});
        std.debug.print("════════════════════════════════════════════════════\n", .{});
        std.debug.print("           Paper Trading Summary\n", .{});
        std.debug.print("════════════════════════════════════════════════════\n", .{});
        std.debug.print("  Run Duration:     {d:.1}s\n", .{run_duration});
        std.debug.print("  Ticks Processed:  {d}\n", .{self.tick_count});
        std.debug.print("────────────────────────────────────────────────────\n", .{});
        std.debug.print("  Initial Balance:  {d:.2} USDT\n", .{self.config.initial_balance.toFloat()});
        std.debug.print("  Final Balance:    {d:.2} USDT\n", .{stats.current_balance.toFloat()});
        std.debug.print("  Total PnL:        {d:.2} USDT ({d:.2}%)\n", .{
            stats.total_pnl.toFloat(),
            stats.total_return_pct,
        });
        std.debug.print("────────────────────────────────────────────────────\n", .{});
        std.debug.print("  Total Trades:     {d}\n", .{stats.total_trades});
        std.debug.print("  Winning Trades:   {d}\n", .{stats.winning_trades});
        std.debug.print("  Losing Trades:    {d}\n", .{stats.losing_trades});
        std.debug.print("  Win Rate:         {d:.1}%\n", .{stats.win_rate * 100});
        std.debug.print("────────────────────────────────────────────────────\n", .{});
        std.debug.print("  Avg Win:          {d:.2} USDT\n", .{stats.avg_win.toFloat()});
        std.debug.print("  Avg Loss:         {d:.2} USDT\n", .{stats.avg_loss.toFloat()});
        std.debug.print("  Profit Factor:    {d:.2}\n", .{stats.profit_factor});
        std.debug.print("  Max Drawdown:     {d:.2}%\n", .{stats.max_drawdown * 100});
        std.debug.print("────────────────────────────────────────────────────\n", .{});
        std.debug.print("  Total Commission: {d:.4} USDT\n", .{stats.total_commission.toFloat()});
        std.debug.print("════════════════════════════════════════════════════\n", .{});
        std.debug.print("\n", .{});
    }

    /// 重置引擎
    pub fn reset(self: *Self) void {
        self.running = false;
        self.start_time = null;
        self.tick_count = 0;
        self.account.reset();
    }

    // ========================================================================
    // 内部方法
    // ========================================================================

    fn generateOrderId(self: *Self) ![]const u8 {
        const order_num = self.executor.next_order_id;
        self.executor.next_order_id += 1;

        return std.fmt.allocPrint(self.allocator, "paper-{d}", .{order_num});
    }
};

// ============================================================================
// 测试
// ============================================================================

test "PaperTradingEngine: init and deinit" {
    const allocator = std.testing.allocator;

    var engine = PaperTradingEngine.init(allocator, .{
        .initial_balance = Decimal.fromInt(10000),
        .log_trades = false,
    });
    defer engine.deinit();

    try std.testing.expect(!engine.isRunning());
    try std.testing.expect(engine.getBalance().eql(Decimal.fromInt(10000)));
}

test "PaperTradingEngine: start and stop" {
    const allocator = std.testing.allocator;

    var engine = PaperTradingEngine.init(allocator, .{
        .initial_balance = Decimal.fromInt(10000),
        .log_trades = false,
    });
    defer engine.deinit();

    engine.start();
    try std.testing.expect(engine.isRunning());

    engine.stop();
    try std.testing.expect(!engine.isRunning());
}

test "PaperTradingEngine: buy and sell" {
    const allocator = std.testing.allocator;

    var engine = PaperTradingEngine.init(allocator, .{
        .initial_balance = Decimal.fromInt(10000),
        .log_trades = false,
    });
    defer engine.deinit();
    engine.connectComponents();

    engine.start();

    // 买入
    const buy_order_id = try engine.generateOrderId();
    defer allocator.free(buy_order_id);

    const buy_result = try engine.submitOrder(.{
        .client_order_id = buy_order_id,
        .symbol = "ETH",
        .side = .buy,
        .order_type = .market,
        .quantity = Decimal.fromInt(1),
        .price = Decimal.fromInt(2000),
    });

    try std.testing.expect(buy_result.success);

    // 验证仓位
    const pos = engine.getPosition("ETH").?;
    try std.testing.expect(pos.quantity.eql(Decimal.fromInt(1)));

    // 卖出
    const sell_order_id = try engine.generateOrderId();
    defer allocator.free(sell_order_id);

    const sell_result = try engine.submitOrder(.{
        .client_order_id = sell_order_id,
        .symbol = "ETH",
        .side = .sell,
        .order_type = .market,
        .quantity = Decimal.fromInt(1),
        .price = Decimal.fromInt(2100),
    });

    try std.testing.expect(sell_result.success);

    // 验证仓位已清空
    try std.testing.expect(engine.getPosition("ETH") == null);

    // 验证统计
    const stats = engine.getStats();
    try std.testing.expectEqual(@as(usize, 1), stats.total_trades);
    try std.testing.expectEqual(@as(usize, 1), stats.winning_trades);

    engine.stop();
}

test "PaperTradingEngine: getStats" {
    const allocator = std.testing.allocator;

    var engine = PaperTradingEngine.init(allocator, .{
        .initial_balance = Decimal.fromInt(10000),
        .log_trades = false,
    });
    defer engine.deinit();

    const stats = engine.getStats();

    try std.testing.expect(stats.current_balance.eql(Decimal.fromInt(10000)));
    try std.testing.expectEqual(@as(usize, 0), stats.total_trades);
}

test "PaperTradingEngine: reset" {
    const allocator = std.testing.allocator;

    var engine = PaperTradingEngine.init(allocator, .{
        .initial_balance = Decimal.fromInt(10000),
        .log_trades = false,
    });
    defer engine.deinit();
    engine.connectComponents();

    engine.start();

    // 买入
    const order_id = try engine.generateOrderId();
    defer allocator.free(order_id);

    _ = try engine.submitOrder(.{
        .client_order_id = order_id,
        .symbol = "ETH",
        .side = .buy,
        .order_type = .market,
        .quantity = Decimal.fromInt(1),
        .price = Decimal.fromInt(2000),
    });

    // 重置
    engine.reset();

    try std.testing.expect(!engine.isRunning());
    try std.testing.expect(engine.getBalance().eql(Decimal.fromInt(10000)));
    try std.testing.expect(engine.getPosition("ETH") == null);
}
