//! ExecutionEngine - 执行引擎
//!
//! 管理订单执行、仓位管理和交易所通信。
//!
//! ## 功能
//! - 订单提交和管理
//! - 订单状态追踪
//! - 仓位更新
//! - 与交易所 API 集成
//! - 通过 MessageBus 发布执行事件
//!
//! ## 设计原则
//! - 单线程事件驱动
//! - 与 Cache 和 MessageBus 集成
//! - 支持回测和实盘模式
//! - 风险控制前置检查

const std = @import("std");
const Allocator = std.mem.Allocator;
const Decimal = @import("decimal.zig").Decimal;
const Timestamp = @import("time.zig").Timestamp;
const MessageBus = @import("message_bus.zig").MessageBus;
const Event = @import("message_bus.zig").Event;
const OrderEvent = @import("message_bus.zig").OrderEvent;
const Cache = @import("cache.zig").Cache;
const TradingPair = @import("../exchange/types.zig").TradingPair;
const Side = @import("../exchange/types.zig").Side;
const OrderType = @import("../exchange/types.zig").OrderType;
const OrderStatus = @import("../exchange/types.zig").OrderStatus;
const Order = @import("../exchange/types.zig").Order;

// ============================================================================
// 执行客户端接口
// ============================================================================

/// 执行客户端接口 (用于与交易所通信)
pub const IExecutionClient = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        submit_order: *const fn (ptr: *anyopaque, request: OrderRequest) anyerror!OrderResult,
        cancel_order: *const fn (ptr: *anyopaque, order_id: []const u8) anyerror!void,
        get_order_status: *const fn (ptr: *anyopaque, order_id: []const u8) anyerror!?OrderStatus,
        get_position: *const fn (ptr: *anyopaque, symbol: []const u8) anyerror!?PositionInfo,
        get_balance: *const fn (ptr: *anyopaque) anyerror!BalanceInfo,
    };

    pub fn submitOrder(self: IExecutionClient, request: OrderRequest) !OrderResult {
        return self.vtable.submit_order(self.ptr, request);
    }

    pub fn cancelOrder(self: IExecutionClient, order_id: []const u8) !void {
        return self.vtable.cancel_order(self.ptr, order_id);
    }

    pub fn getOrderStatus(self: IExecutionClient, order_id: []const u8) !?OrderStatus {
        return self.vtable.get_order_status(self.ptr, order_id);
    }

    pub fn getPosition(self: IExecutionClient, symbol: []const u8) !?PositionInfo {
        return self.vtable.get_position(self.ptr, symbol);
    }

    pub fn getBalance(self: IExecutionClient) !BalanceInfo {
        return self.vtable.get_balance(self.ptr);
    }
};

// ============================================================================
// 数据类型
// ============================================================================

/// 订单请求
pub const OrderRequest = struct {
    client_order_id: []const u8,
    symbol: []const u8,
    side: Side,
    order_type: OrderType,
    quantity: Decimal,
    price: ?Decimal = null, // limit 订单需要
    stop_price: ?Decimal = null, // stop 订单需要
    time_in_force: TimeInForce = .gtc,
    reduce_only: bool = false,
    post_only: bool = false,

    pub const TimeInForce = enum {
        gtc, // Good Till Cancel
        ioc, // Immediate Or Cancel
        fok, // Fill Or Kill
    };
};

/// 订单结果
pub const OrderResult = struct {
    success: bool,
    order_id: ?[]const u8 = null,
    exchange_order_id: ?u64 = null,
    status: OrderStatus = .pending,
    filled_quantity: Decimal = Decimal.ZERO,
    avg_fill_price: ?Decimal = null,
    error_code: ?u32 = null,
    error_message: ?[]const u8 = null,
    timestamp: Timestamp,
};

/// 仓位信息
pub const PositionInfo = struct {
    symbol: []const u8,
    side: PositionSide,
    quantity: Decimal,
    entry_price: Decimal,
    mark_price: Decimal,
    unrealized_pnl: Decimal,
    realized_pnl: Decimal,
    leverage: u32,
    liquidation_price: ?Decimal = null,
    timestamp: Timestamp,

    pub const PositionSide = enum { long, short, flat };
};

/// 余额信息
pub const BalanceInfo = struct {
    total: Decimal,
    available: Decimal,
    locked: Decimal,
    unrealized_pnl: Decimal,
    timestamp: Timestamp,
};

// ============================================================================
// ExecutionEngine 错误
// ============================================================================

pub const ExecutionError = error{
    NotConnected,
    OrderRejected,
    InsufficientBalance,
    InvalidOrder,
    RiskLimitExceeded,
    OrderNotFound,
    OutOfMemory,
    ClientError,
};

// ============================================================================
// 风险检查配置
// ============================================================================

pub const RiskConfig = struct {
    max_position_size: ?Decimal = null, // 最大仓位
    max_order_size: ?Decimal = null, // 单笔最大订单
    max_daily_loss: ?Decimal = null, // 日最大亏损
    max_open_orders: u32 = 100, // 最大挂单数
    min_order_interval_ms: u64 = 0, // 最小下单间隔
    allowed_symbols: ?[]const []const u8 = null, // 允许的交易对
};

// ============================================================================
// ExecutionEngine 主结构
// ============================================================================

pub const ExecutionEngine = struct {
    allocator: Allocator,
    bus: *MessageBus,
    cache: *Cache,

    // 执行客户端
    client: ?IExecutionClient,

    // 订单追踪
    pending_orders: std.StringHashMap(OrderRequest),
    active_orders: std.StringHashMap(OrderInfo),

    // 风险配置
    risk_config: RiskConfig,

    // 状态
    state: State,
    stats: Stats,

    // 内部状态
    last_order_time: ?Timestamp,
    daily_pnl: Decimal,

    pub const State = enum {
        stopped,
        running,
        paused,
    };

    pub const OrderInfo = struct {
        request: OrderRequest,
        result: OrderResult,
        created_at: Timestamp,
        updated_at: Timestamp,
    };

    pub const Stats = struct {
        orders_submitted: u64 = 0,
        orders_filled: u64 = 0,
        orders_cancelled: u64 = 0,
        orders_rejected: u64 = 0,
        total_volume: Decimal = Decimal.ZERO,
        total_commission: Decimal = Decimal.ZERO,
    };

    // ========================================================================
    // 初始化和清理
    // ========================================================================

    /// 初始化 ExecutionEngine
    pub fn init(
        allocator: Allocator,
        bus: *MessageBus,
        cache: *Cache,
        risk_config: RiskConfig,
    ) ExecutionEngine {
        return .{
            .allocator = allocator,
            .bus = bus,
            .cache = cache,
            .client = null,
            .pending_orders = std.StringHashMap(OrderRequest).init(allocator),
            .active_orders = std.StringHashMap(OrderInfo).init(allocator),
            .risk_config = risk_config,
            .state = .stopped,
            .stats = .{},
            .last_order_time = null,
            .daily_pnl = Decimal.ZERO,
        };
    }

    /// 释放资源
    pub fn deinit(self: *ExecutionEngine) void {
        // 释放待处理订单
        var pending_iter = self.pending_orders.iterator();
        while (pending_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.pending_orders.deinit();

        // 释放活跃订单
        var active_iter = self.active_orders.iterator();
        while (active_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.active_orders.deinit();
    }

    // ========================================================================
    // 客户端管理
    // ========================================================================

    /// 设置执行客户端
    pub fn setClient(self: *ExecutionEngine, client: IExecutionClient) void {
        self.client = client;
    }

    // ========================================================================
    // 生命周期管理
    // ========================================================================

    /// 启动执行引擎
    pub fn start(self: *ExecutionEngine) !void {
        if (self.client == null) {
            return ExecutionError.NotConnected;
        }

        self.state = .running;

        // 发布启动事件
        self.bus.publish("execution_engine.started", .{
            .tick = .{
                .timestamp = Timestamp.now().millis * 1_000_000,
                .tick_number = 0,
            },
        });
    }

    /// 停止执行引擎
    pub fn stop(self: *ExecutionEngine) void {
        self.state = .stopped;

        // 发布停止事件
        self.bus.publish("execution_engine.stopped", .{
            .shutdown = .{
                .reason = .user_request,
                .message = "ExecutionEngine stopped",
            },
        });
    }

    /// 暂停执行引擎
    pub fn pause(self: *ExecutionEngine) void {
        self.state = .paused;
    }

    /// 恢复执行引擎
    pub fn unpause(self: *ExecutionEngine) void {
        self.state = .running;
    }

    // ========================================================================
    // 订单操作
    // ========================================================================

    /// 提交订单
    pub fn submitOrder(self: *ExecutionEngine, request: OrderRequest) !OrderResult {
        if (self.state != .running) {
            return OrderResult{
                .success = false,
                .error_code = 1001,
                .error_message = "Engine not running",
                .timestamp = Timestamp.now(),
            };
        }

        if (self.client == null) {
            return ExecutionError.NotConnected;
        }

        // 风险检查
        try self.checkRisk(request);

        // 记录待处理订单
        const owned_id = try self.allocator.dupe(u8, request.client_order_id);
        errdefer self.allocator.free(owned_id);

        const put_result = try self.pending_orders.getOrPut(owned_id);
        if (put_result.found_existing) {
            self.allocator.free(owned_id);
            return OrderResult{
                .success = false,
                .error_code = 1002,
                .error_message = "Duplicate order ID",
                .timestamp = Timestamp.now(),
            };
        }
        put_result.key_ptr.* = owned_id;
        put_result.value_ptr.* = request;

        // 提交到客户端
        const result = self.client.?.submitOrder(request) catch |err| {
            _ = self.pending_orders.remove(request.client_order_id);
            self.allocator.free(owned_id);
            self.stats.orders_rejected += 1;

            return OrderResult{
                .success = false,
                .error_code = 1003,
                .error_message = @errorName(err),
                .timestamp = Timestamp.now(),
            };
        };

        // 更新统计
        self.stats.orders_submitted += 1;
        self.last_order_time = Timestamp.now();

        // 移动到活跃订单
        _ = self.pending_orders.remove(request.client_order_id);

        if (result.success) {
            const active_result = try self.active_orders.getOrPut(owned_id);
            active_result.key_ptr.* = owned_id;
            active_result.value_ptr.* = .{
                .request = request,
                .result = result,
                .created_at = Timestamp.now(),
                .updated_at = Timestamp.now(),
            };
        } else {
            self.allocator.free(owned_id);
            self.stats.orders_rejected += 1;
        }

        // 发布订单事件
        self.publishOrderEvent(request, result);

        return result;
    }

    /// 取消订单
    pub fn cancelOrder(self: *ExecutionEngine, order_id: []const u8) !void {
        if (self.client == null) {
            return ExecutionError.NotConnected;
        }

        try self.client.?.cancelOrder(order_id);

        // 从活跃订单移除
        if (self.active_orders.fetchRemove(order_id)) |kv| {
            self.allocator.free(kv.key);
            self.stats.orders_cancelled += 1;
        }

        // 发布取消事件
        self.bus.publish("order.cancelled", .{
            .order_cancelled = .{
                .order_id = order_id,
                .instrument_id = "",
                .side = .buy,
                .order_type = .market,
                .quantity = 0,
                .status = .cancelled,
                .timestamp = Timestamp.now().millis * 1_000_000,
            },
        });
    }

    /// 取消所有订单
    pub fn cancelAllOrders(self: *ExecutionEngine) !void {
        var orders_to_cancel: std.ArrayList([]const u8) = .{};
        defer orders_to_cancel.deinit(self.allocator);

        var iter = self.active_orders.iterator();
        while (iter.next()) |entry| {
            try orders_to_cancel.append(self.allocator, entry.key_ptr.*);
        }

        for (orders_to_cancel.items) |order_id| {
            self.cancelOrder(order_id) catch {};
        }
    }

    // ========================================================================
    // 风险检查
    // ========================================================================

    fn checkRisk(self: *ExecutionEngine, request: OrderRequest) !void {
        // 检查订单间隔
        if (self.risk_config.min_order_interval_ms > 0) {
            if (self.last_order_time) |last_time| {
                const elapsed = Timestamp.now().millis - last_time.millis;
                if (elapsed < @as(i64, @intCast(self.risk_config.min_order_interval_ms))) {
                    return ExecutionError.RiskLimitExceeded;
                }
            }
        }

        // 检查最大订单量
        if (self.risk_config.max_order_size) |max_size| {
            if (request.quantity.cmp(max_size) == .gt) {
                return ExecutionError.RiskLimitExceeded;
            }
        }

        // 检查挂单数量
        if (self.active_orders.count() >= self.risk_config.max_open_orders) {
            return ExecutionError.RiskLimitExceeded;
        }

        // 检查允许的交易对
        if (self.risk_config.allowed_symbols) |allowed| {
            var found = false;
            for (allowed) |symbol| {
                if (std.mem.eql(u8, symbol, request.symbol)) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                return ExecutionError.InvalidOrder;
            }
        }
    }

    // ========================================================================
    // 事件发布
    // ========================================================================

    fn publishOrderEvent(self: *ExecutionEngine, request: OrderRequest, result: OrderResult) void {
        const side: OrderEvent.Side = if (request.side == .buy) .buy else .sell;
        const order_type: OrderEvent.OrderType = switch (request.order_type) {
            .market => .market,
            .limit => .limit,
        };

        if (result.success) {
            self.bus.publish("order.submitted", .{
                .order_submitted = .{
                    .order_id = request.client_order_id,
                    .instrument_id = request.symbol,
                    .side = side,
                    .order_type = order_type,
                    .quantity = request.quantity.toFloat(),
                    .price = if (request.price) |p| p.toFloat() else null,
                    .status = .submitted,
                    .timestamp = result.timestamp.millis * 1_000_000,
                },
            });
        } else {
            self.bus.publish("order.rejected", .{
                .order_rejected = .{
                    .order = .{
                        .order_id = request.client_order_id,
                        .instrument_id = request.symbol,
                        .side = side,
                        .order_type = order_type,
                        .quantity = request.quantity.toFloat(),
                        .status = .rejected,
                        .timestamp = result.timestamp.millis * 1_000_000,
                    },
                    .reason = result.error_message orelse "Unknown error",
                    .timestamp = result.timestamp.millis * 1_000_000,
                },
            });
        }
    }

    // ========================================================================
    // 查询方法
    // ========================================================================

    /// 获取订单状态
    pub fn getOrderStatus(self: *ExecutionEngine, order_id: []const u8) ?OrderStatus {
        if (self.active_orders.get(order_id)) |info| {
            return info.result.status;
        }
        return null;
    }

    /// 获取活跃订单数量
    pub fn activeOrderCount(self: *const ExecutionEngine) usize {
        return self.active_orders.count();
    }

    /// 获取统计信息
    pub fn getStats(self: *const ExecutionEngine) Stats {
        return self.stats;
    }

    /// 是否正在运行
    pub fn isRunning(self: *const ExecutionEngine) bool {
        return self.state == .running;
    }

    // ========================================================================
    // 订单恢复
    // ========================================================================

    /// 从交易所恢复活跃订单
    /// 用于程序重启后恢复订单状态
    pub fn recoverOrders(self: *ExecutionEngine) !RecoveryResult {
        if (self.client == null) {
            return ExecutionError.NotConnected;
        }

        var result = RecoveryResult{};
        const start_time = std.time.milliTimestamp();

        // 获取所有活跃订单的 ID
        var order_ids: std.ArrayList([]const u8) = .{};
        defer order_ids.deinit(self.allocator);

        var iter = self.active_orders.iterator();
        while (iter.next()) |entry| {
            try order_ids.append(self.allocator, entry.key_ptr.*);
        }

        // 查询每个订单的最新状态
        for (order_ids.items) |order_id| {
            const status = self.client.?.getOrderStatus(order_id) catch {
                result.errors += 1;
                continue;
            };

            if (status) |s| {
                // 更新本地状态
                if (self.active_orders.getPtr(order_id)) |info| {
                    const old_status = info.result.status;
                    info.result.status = s;
                    info.updated_at = Timestamp.now();

                    // 如果订单已完成，从活跃列表移除
                    if (s == .filled or s == .cancelled or s == .rejected) {
                        if (self.active_orders.fetchRemove(order_id)) |kv| {
                            self.allocator.free(kv.key);
                            result.orders_closed += 1;
                        }
                    } else if (old_status != s) {
                        result.orders_updated += 1;
                    }
                }
                result.orders_checked += 1;
            }
        }

        result.duration_ms = @intCast(std.time.milliTimestamp() - start_time);

        // 发布恢复完成事件
        self.bus.publish("execution_engine.recovery_complete", .{
            .tick = .{
                .timestamp = Timestamp.now().millis * 1_000_000,
                .tick_number = result.orders_checked,
            },
        });

        return result;
    }

    /// 订单恢复结果
    pub const RecoveryResult = struct {
        orders_checked: u64 = 0,
        orders_updated: u64 = 0,
        orders_closed: u64 = 0,
        errors: u64 = 0,
        duration_ms: u64 = 0,
    };

    // ========================================================================
    // 订单超时检查
    // ========================================================================

    /// 超时订单检查配置
    pub const TimeoutConfig = struct {
        /// 订单超时时间 (毫秒)
        timeout_ms: u64 = 60000,
        /// 是否自动取消超时订单
        auto_cancel: bool = false,
    };

    /// 检查并处理超时订单
    pub fn checkTimeoutOrders(self: *ExecutionEngine, config: TimeoutConfig) !TimeoutResult {
        var result = TimeoutResult{};
        const now = Timestamp.now();

        var orders_to_cancel: std.ArrayList([]const u8) = .{};
        defer orders_to_cancel.deinit(self.allocator);

        // 检查所有活跃订单
        var iter = self.active_orders.iterator();
        while (iter.next()) |entry| {
            const info = entry.value_ptr.*;
            const age_ms: u64 = @intCast(now.millis - info.created_at.millis);

            if (age_ms > config.timeout_ms) {
                result.timeout_orders += 1;

                if (config.auto_cancel) {
                    try orders_to_cancel.append(self.allocator, entry.key_ptr.*);
                }
            }
        }

        // 取消超时订单
        for (orders_to_cancel.items) |order_id| {
            self.cancelOrder(order_id) catch {
                result.cancel_errors += 1;
                continue;
            };
            result.orders_cancelled += 1;
        }

        // 发布超时检查事件
        if (result.timeout_orders > 0) {
            self.bus.publish("execution_engine.timeout_check", .{
                .tick = .{
                    .timestamp = now.millis * 1_000_000,
                    .tick_number = result.timeout_orders,
                },
            });
        }

        return result;
    }

    /// 超时检查结果
    pub const TimeoutResult = struct {
        timeout_orders: u64 = 0,
        orders_cancelled: u64 = 0,
        cancel_errors: u64 = 0,
    };

    /// 获取订单详情
    pub fn getOrderInfo(self: *const ExecutionEngine, order_id: []const u8) ?OrderInfo {
        return self.active_orders.get(order_id);
    }

    /// 获取所有活跃订单
    pub fn getActiveOrders(self: *ExecutionEngine) ![]OrderInfo {
        var orders: std.ArrayList(OrderInfo) = .{};
        errdefer orders.deinit(self.allocator);

        var iter = self.active_orders.iterator();
        while (iter.next()) |entry| {
            try orders.append(self.allocator, entry.value_ptr.*);
        }

        return orders.toOwnedSlice(self.allocator);
    }
};

// ============================================================================
// Mock 执行客户端 (用于测试)
// ============================================================================

pub const MockExecutionClient = struct {
    allocator: Allocator,
    orders: std.StringHashMap(MockOrder),
    balance: BalanceInfo,
    should_reject: bool,
    next_exchange_id: u64,

    const MockOrder = struct {
        request: OrderRequest,
        status: OrderStatus,
        filled: Decimal,
    };

    pub fn init(allocator: Allocator) MockExecutionClient {
        return .{
            .allocator = allocator,
            .orders = std.StringHashMap(MockOrder).init(allocator),
            .balance = .{
                .total = Decimal.fromInt(10000),
                .available = Decimal.fromInt(10000),
                .locked = Decimal.ZERO,
                .unrealized_pnl = Decimal.ZERO,
                .timestamp = Timestamp.now(),
            },
            .should_reject = false,
            .next_exchange_id = 1000,
        };
    }

    pub fn deinit(self: *MockExecutionClient) void {
        var iter = self.orders.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.orders.deinit();
    }

    /// 设置是否拒绝订单 (用于测试)
    pub fn setRejectOrders(self: *MockExecutionClient, reject: bool) void {
        self.should_reject = reject;
    }

    /// 获取 IExecutionClient 接口
    pub fn asClient(self: *MockExecutionClient) IExecutionClient {
        return .{
            .ptr = self,
            .vtable = &.{
                .submit_order = submitOrder,
                .cancel_order = cancelOrder,
                .get_order_status = getOrderStatus,
                .get_position = getPosition,
                .get_balance = getBalance,
            },
        };
    }

    fn submitOrder(ptr: *anyopaque, request: OrderRequest) anyerror!OrderResult {
        const self: *MockExecutionClient = @ptrCast(@alignCast(ptr));

        if (self.should_reject) {
            return OrderResult{
                .success = false,
                .error_code = 2001,
                .error_message = "Order rejected by mock",
                .timestamp = Timestamp.now(),
            };
        }

        // 模拟成功
        const order_id = try self.allocator.dupe(u8, request.client_order_id);
        errdefer self.allocator.free(order_id);

        const result = try self.orders.getOrPut(order_id);
        if (result.found_existing) {
            self.allocator.free(order_id);
        } else {
            result.key_ptr.* = order_id;
        }
        result.value_ptr.* = .{
            .request = request,
            .status = .filled, // 模拟立即成交
            .filled = request.quantity,
        };

        const exchange_id = self.next_exchange_id;
        self.next_exchange_id += 1;

        return OrderResult{
            .success = true,
            .order_id = request.client_order_id,
            .exchange_order_id = exchange_id,
            .status = .filled,
            .filled_quantity = request.quantity,
            .avg_fill_price = request.price,
            .timestamp = Timestamp.now(),
        };
    }

    fn cancelOrder(ptr: *anyopaque, order_id: []const u8) anyerror!void {
        const self: *MockExecutionClient = @ptrCast(@alignCast(ptr));

        if (self.orders.fetchRemove(order_id)) |kv| {
            self.allocator.free(kv.key);
        }
    }

    fn getOrderStatus(ptr: *anyopaque, order_id: []const u8) anyerror!?OrderStatus {
        const self: *MockExecutionClient = @ptrCast(@alignCast(ptr));

        if (self.orders.get(order_id)) |order| {
            return order.status;
        }
        return null;
    }

    fn getPosition(_: *anyopaque, _: []const u8) anyerror!?PositionInfo {
        return null;
    }

    fn getBalance(ptr: *anyopaque) anyerror!BalanceInfo {
        const self: *MockExecutionClient = @ptrCast(@alignCast(ptr));
        return self.balance;
    }
};

// ============================================================================
// 测试
// ============================================================================

test "ExecutionEngine: init and deinit" {
    var bus = MessageBus.init(std.testing.allocator);
    defer bus.deinit();

    var cache = Cache.init(std.testing.allocator, &bus, .{});
    defer cache.deinit();

    var engine = ExecutionEngine.init(std.testing.allocator, &bus, &cache, .{});
    defer engine.deinit();

    try std.testing.expectEqual(ExecutionEngine.State.stopped, engine.state);
    try std.testing.expect(!engine.isRunning());
}

test "ExecutionEngine: with mock client" {
    var bus = MessageBus.init(std.testing.allocator);
    defer bus.deinit();

    var cache = Cache.init(std.testing.allocator, &bus, .{});
    defer cache.deinit();

    var engine = ExecutionEngine.init(std.testing.allocator, &bus, &cache, .{});
    defer engine.deinit();

    var mock = MockExecutionClient.init(std.testing.allocator);
    defer mock.deinit();

    engine.setClient(mock.asClient());
    try engine.start();

    try std.testing.expect(engine.isRunning());
}

test "ExecutionEngine: submit order" {
    var bus = MessageBus.init(std.testing.allocator);
    defer bus.deinit();

    var cache = Cache.init(std.testing.allocator, &bus, .{});
    defer cache.deinit();

    var engine = ExecutionEngine.init(std.testing.allocator, &bus, &cache, .{});
    defer engine.deinit();

    var mock = MockExecutionClient.init(std.testing.allocator);
    defer mock.deinit();

    engine.setClient(mock.asClient());
    try engine.start();

    const result = try engine.submitOrder(.{
        .client_order_id = "test-001",
        .symbol = "BTC-USDT",
        .side = .buy,
        .order_type = .market,
        .quantity = Decimal.fromInt(1),
    });

    try std.testing.expect(result.success);
    try std.testing.expectEqual(@as(u64, 1), engine.stats.orders_submitted);
}

test "ExecutionEngine: risk check - max order size" {
    var bus = MessageBus.init(std.testing.allocator);
    defer bus.deinit();

    var cache = Cache.init(std.testing.allocator, &bus, .{});
    defer cache.deinit();

    var engine = ExecutionEngine.init(std.testing.allocator, &bus, &cache, .{
        .max_order_size = Decimal.fromInt(10),
    });
    defer engine.deinit();

    var mock = MockExecutionClient.init(std.testing.allocator);
    defer mock.deinit();

    engine.setClient(mock.asClient());
    try engine.start();

    // 订单超过最大限制
    const result = engine.submitOrder(.{
        .client_order_id = "test-002",
        .symbol = "BTC-USDT",
        .side = .buy,
        .order_type = .market,
        .quantity = Decimal.fromInt(100), // > max 10
    });

    try std.testing.expectError(ExecutionError.RiskLimitExceeded, result);
}

test "ExecutionEngine: order rejection" {
    var bus = MessageBus.init(std.testing.allocator);
    defer bus.deinit();

    var cache = Cache.init(std.testing.allocator, &bus, .{});
    defer cache.deinit();

    var engine = ExecutionEngine.init(std.testing.allocator, &bus, &cache, .{});
    defer engine.deinit();

    var mock = MockExecutionClient.init(std.testing.allocator);
    defer mock.deinit();
    mock.setRejectOrders(true);

    engine.setClient(mock.asClient());
    try engine.start();

    const result = try engine.submitOrder(.{
        .client_order_id = "test-003",
        .symbol = "BTC-USDT",
        .side = .buy,
        .order_type = .market,
        .quantity = Decimal.fromInt(1),
    });

    try std.testing.expect(!result.success);
    try std.testing.expectEqual(@as(u64, 1), engine.stats.orders_rejected);
}

test "MockExecutionClient: basic operations" {
    var mock = MockExecutionClient.init(std.testing.allocator);
    defer mock.deinit();

    const client = mock.asClient();

    const result = try client.submitOrder(.{
        .client_order_id = "mock-001",
        .symbol = "ETH-USDT",
        .side = .sell,
        .order_type = .limit,
        .quantity = Decimal.fromInt(5),
        .price = Decimal.fromInt(2000),
    });

    try std.testing.expect(result.success);
    try std.testing.expectEqual(OrderStatus.filled, result.status);

    const balance = try client.getBalance();
    try std.testing.expectEqual(Decimal.fromInt(10000), balance.total);
}

test "ExecutionEngine: recover orders" {
    var bus = MessageBus.init(std.testing.allocator);
    defer bus.deinit();

    var cache = Cache.init(std.testing.allocator, &bus, .{});
    defer cache.deinit();

    var engine = ExecutionEngine.init(std.testing.allocator, &bus, &cache, .{});
    defer engine.deinit();

    var mock = MockExecutionClient.init(std.testing.allocator);
    defer mock.deinit();

    engine.setClient(mock.asClient());
    try engine.start();

    // 提交一个订单
    _ = try engine.submitOrder(.{
        .client_order_id = "recover-001",
        .symbol = "BTC-USDT",
        .side = .buy,
        .order_type = .market,
        .quantity = Decimal.fromInt(1),
    });

    // 恢复订单
    const result = try engine.recoverOrders();
    try std.testing.expect(result.orders_checked > 0);
}

test "ExecutionEngine: timeout check" {
    var bus = MessageBus.init(std.testing.allocator);
    defer bus.deinit();

    var cache = Cache.init(std.testing.allocator, &bus, .{});
    defer cache.deinit();

    var engine = ExecutionEngine.init(std.testing.allocator, &bus, &cache, .{});
    defer engine.deinit();

    var mock = MockExecutionClient.init(std.testing.allocator);
    defer mock.deinit();

    engine.setClient(mock.asClient());
    try engine.start();

    // 检查超时订单 (没有订单应该不会有超时)
    const result = try engine.checkTimeoutOrders(.{
        .timeout_ms = 60000,
        .auto_cancel = false,
    });

    try std.testing.expectEqual(@as(u64, 0), result.timeout_orders);
}

test "ExecutionEngine: TimeoutConfig defaults" {
    const config = ExecutionEngine.TimeoutConfig{};
    try std.testing.expectEqual(@as(u64, 60000), config.timeout_ms);
    try std.testing.expect(!config.auto_cancel);
}

test "ExecutionEngine: RecoveryResult defaults" {
    const result = ExecutionEngine.RecoveryResult{};
    try std.testing.expectEqual(@as(u64, 0), result.orders_checked);
    try std.testing.expectEqual(@as(u64, 0), result.errors);
}
