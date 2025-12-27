//! SimulatedExecutor - 模拟订单执行器
//!
//! 实现 IExecutionClient 接口，用于 Paper Trading。
//! 使用真实市场数据模拟订单执行，考虑滑点和手续费。

const std = @import("std");
const Allocator = std.mem.Allocator;

const Decimal = @import("../core/decimal.zig").Decimal;
const Timestamp = @import("../core/time.zig").Timestamp;
const MessageBus = @import("../core/message_bus.zig").MessageBus;
const Cache = @import("../core/cache.zig").Cache;
const Side = @import("../exchange/types.zig").Side;
const OrderType = @import("../exchange/types.zig").OrderType;
const OrderStatus = @import("../exchange/types.zig").OrderStatus;

const execution_engine = @import("../core/execution_engine.zig");
const IExecutionClient = execution_engine.IExecutionClient;
const OrderRequest = execution_engine.OrderRequest;
const OrderResult = execution_engine.OrderResult;
const PositionInfo = execution_engine.PositionInfo;
const BalanceInfo = execution_engine.BalanceInfo;

const simulated_account = @import("simulated_account.zig");
const SimulatedAccount = simulated_account.SimulatedAccount;
const OrderFill = simulated_account.OrderFill;
const Position = simulated_account.Position;

/// 模拟订单
const SimulatedOrder = struct {
    client_order_id: []const u8,
    symbol: []const u8,
    side: Side,
    order_type: OrderType,
    quantity: Decimal,
    price: ?Decimal,
    status: OrderStatus,
    filled_quantity: Decimal,
    avg_fill_price: ?Decimal,
    created_at: Timestamp,
    updated_at: Timestamp,
};

/// 模拟执行器配置
pub const SimulatedExecutorConfig = struct {
    /// 手续费率 (默认 0.05%)
    commission_rate: Decimal = Decimal.fromFloat(0.0005),
    /// 滑点 (默认 0.01%)
    slippage: Decimal = Decimal.fromFloat(0.0001),
    /// 模拟填充延迟 (毫秒)
    fill_delay_ms: u32 = 0,
    /// 是否记录交易日志
    log_trades: bool = true,
};

/// 模拟执行器
pub const SimulatedExecutor = struct {
    allocator: Allocator,
    account: *SimulatedAccount,
    cache: ?*Cache,
    message_bus: ?*MessageBus,
    config: SimulatedExecutorConfig,

    // 订单管理
    open_orders: std.StringHashMap(SimulatedOrder),
    next_order_id: u64,

    const Self = @This();

    /// 初始化
    pub fn init(
        allocator: Allocator,
        account: *SimulatedAccount,
        cache: ?*Cache,
        message_bus: ?*MessageBus,
        config: SimulatedExecutorConfig,
    ) Self {
        return .{
            .allocator = allocator,
            .account = account,
            .cache = cache,
            .message_bus = message_bus,
            .config = config,
            .open_orders = std.StringHashMap(SimulatedOrder).init(allocator),
            .next_order_id = 1000,
        };
    }

    /// 释放资源
    pub fn deinit(self: *Self) void {
        var iter = self.open_orders.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.symbol);
        }
        self.open_orders.deinit();
    }

    /// 获取 IExecutionClient 接口
    pub fn asClient(self: *Self) IExecutionClient {
        return .{
            .ptr = self,
            .vtable = &vtable,
        };
    }

    /// VTable
    const vtable = IExecutionClient.VTable{
        .submit_order = submitOrder,
        .cancel_order = cancelOrder,
        .get_order_status = getOrderStatus,
        .get_position = getPosition,
        .get_balance = getBalance,
    };

    // ========================================================================
    // IExecutionClient 实现
    // ========================================================================

    fn submitOrder(ptr: *anyopaque, request: OrderRequest) anyerror!OrderResult {
        const self: *Self = @ptrCast(@alignCast(ptr));
        return self.executeOrder(request);
    }

    fn cancelOrder(ptr: *anyopaque, order_id: []const u8) anyerror!void {
        const self: *Self = @ptrCast(@alignCast(ptr));

        if (self.open_orders.fetchRemove(order_id)) |kv| {
            self.allocator.free(kv.key);
            self.allocator.free(kv.value.symbol);

            // 发布取消事件
            if (self.message_bus) |bus| {
                bus.publish("order.cancelled", .{
                    .order_cancelled = .{
                        .order_id = order_id,
                        .instrument_id = "",
                        .side = .buy,
                        .order_type = .limit,
                        .quantity = 0,
                        .status = .cancelled,
                        .timestamp = Timestamp.now().millis * 1_000_000,
                    },
                });
            }
        } else {
            return error.OrderNotFound;
        }
    }

    fn getOrderStatus(ptr: *anyopaque, order_id: []const u8) anyerror!?OrderStatus {
        const self: *Self = @ptrCast(@alignCast(ptr));

        if (self.open_orders.get(order_id)) |order| {
            return order.status;
        }
        return null;
    }

    fn getPosition(ptr: *anyopaque, symbol: []const u8) anyerror!?PositionInfo {
        const self: *Self = @ptrCast(@alignCast(ptr));

        if (self.account.getPosition(symbol)) |pos| {
            return PositionInfo{
                .symbol = symbol,
                .side = if (pos.side == .long) .long else .short,
                .quantity = pos.quantity,
                .entry_price = pos.entry_price,
                .mark_price = pos.entry_price,
                .unrealized_pnl = pos.unrealized_pnl,
                .realized_pnl = Decimal.ZERO,
                .leverage = 1,
                .liquidation_price = null,
                .timestamp = pos.timestamp,
            };
        }
        return null;
    }

    fn getBalance(ptr: *anyopaque) anyerror!BalanceInfo {
        const self: *Self = @ptrCast(@alignCast(ptr));

        return BalanceInfo{
            .total = self.account.current_balance,
            .available = self.account.available_balance,
            .locked = self.account.current_balance.sub(self.account.available_balance),
            .unrealized_pnl = Decimal.ZERO, // TODO: 计算未实现盈亏
            .timestamp = Timestamp.now(),
        };
    }

    // ========================================================================
    // 订单执行
    // ========================================================================

    /// 执行订单 (模拟)
    pub fn executeOrder(self: *Self, request: OrderRequest) !OrderResult {
        const now = Timestamp.now();

        // 获取当前价格
        var fill_price: Decimal = undefined;
        if (self.cache) |cache| {
            if (cache.getQuote(request.symbol)) |quote| {
                // 根据买卖方向选择价格
                const base_price = if (request.side == .buy) quote.ask else quote.bid;

                // 应用滑点
                const slippage_factor = if (request.side == .buy)
                    Decimal.ONE.add(self.config.slippage)
                else
                    Decimal.ONE.sub(self.config.slippage);

                fill_price = base_price.mul(slippage_factor);
            } else if (request.price) |price| {
                // 没有报价时使用订单价格
                fill_price = price;
            } else {
                return OrderResult{
                    .success = false,
                    .error_code = 5001,
                    .error_message = "No price available for market order",
                    .timestamp = now,
                };
            }
        } else if (request.price) |price| {
            // 没有 cache 时使用订单价格 (用于测试)
            fill_price = price;
        } else {
            return OrderResult{
                .success = false,
                .error_code = 5002,
                .error_message = "No price available",
                .timestamp = now,
            };
        }

        // 计算名义金额和手续费
        const notional = fill_price.mul(request.quantity);
        const commission = notional.mul(self.config.commission_rate);

        // 检查余额 (买入时)
        if (request.side == .buy) {
            const required = notional.add(commission);
            if (!self.account.hasAvailableBalance(required)) {
                return OrderResult{
                    .success = false,
                    .error_code = 5003,
                    .error_message = "Insufficient balance",
                    .timestamp = now,
                };
            }
        }

        // 模拟成交
        const fill = OrderFill{
            .order_id = request.client_order_id,
            .symbol = request.symbol,
            .side = request.side,
            .fill_price = fill_price,
            .fill_quantity = request.quantity,
            .commission = commission,
            .timestamp = now,
        };

        // 更新账户
        try self.account.applyFill(fill);

        // 生成订单 ID
        const exchange_order_id = self.next_order_id;
        self.next_order_id += 1;

        // 发布成交事件
        if (self.message_bus) |bus| {
            const side_event = if (request.side == .buy)
                @import("../core/message_bus.zig").OrderEvent.Side.buy
            else
                @import("../core/message_bus.zig").OrderEvent.Side.sell;

            const order_type_event = if (request.order_type == .market)
                @import("../core/message_bus.zig").OrderEvent.OrderType.market
            else
                @import("../core/message_bus.zig").OrderEvent.OrderType.limit;

            bus.publish("order.filled", .{
                .order_filled = .{
                    .order = .{
                        .order_id = request.client_order_id,
                        .instrument_id = request.symbol,
                        .side = side_event,
                        .order_type = order_type_event,
                        .quantity = request.quantity.toFloat(),
                        .price = fill_price.toFloat(),
                        .filled_quantity = request.quantity.toFloat(),
                        .status = .filled,
                        .timestamp = now.millis * 1_000_000,
                    },
                    .fill_price = fill_price.toFloat(),
                    .fill_quantity = request.quantity.toFloat(),
                    .timestamp = now.millis * 1_000_000,
                },
            });
        }

        // 日志
        if (self.config.log_trades) {
            const side_str = if (request.side == .buy) "BUY" else "SELL";
            std.debug.print("[PAPER] {s} {s} {d:.4} @ {d:.2} (commission: {d:.4})\n", .{
                side_str,
                request.symbol,
                request.quantity.toFloat(),
                fill_price.toFloat(),
                commission.toFloat(),
            });
        }

        return OrderResult{
            .success = true,
            .order_id = request.client_order_id,
            .exchange_order_id = exchange_order_id,
            .status = .filled,
            .filled_quantity = request.quantity,
            .avg_fill_price = fill_price,
            .timestamp = now,
        };
    }

    /// 处理限价单 (检查是否可以成交)
    pub fn processLimitOrders(self: *Self) !void {
        if (self.cache == null) return;

        var orders_to_fill = std.ArrayList([]const u8).init(self.allocator);
        defer orders_to_fill.deinit(self.allocator);

        // 检查所有挂单
        var iter = self.open_orders.iterator();
        while (iter.next()) |entry| {
            const order = entry.value_ptr.*;

            if (order.status != .open) continue;

            if (self.cache.?.getQuote(order.symbol)) |quote| {
                const should_fill = switch (order.side) {
                    .buy => quote.ask.cmp(order.price.?) != .gt, // ask <= limit_price
                    .sell => quote.bid.cmp(order.price.?) != .lt, // bid >= limit_price
                };

                if (should_fill) {
                    try orders_to_fill.append(self.allocator, entry.key_ptr.*);
                }
            }
        }

        // 执行可成交的订单
        for (orders_to_fill.items) |order_id| {
            if (self.open_orders.get(order_id)) |order| {
                const request = OrderRequest{
                    .client_order_id = order.client_order_id,
                    .symbol = order.symbol,
                    .side = order.side,
                    .order_type = order.order_type,
                    .quantity = order.quantity.sub(order.filled_quantity),
                    .price = order.price,
                };

                _ = self.executeOrder(request) catch {};

                // 移除已成交订单
                if (self.open_orders.fetchRemove(order_id)) |kv| {
                    self.allocator.free(kv.key);
                    self.allocator.free(kv.value.symbol);
                }
            }
        }
    }
};

// ============================================================================
// 测试
// ============================================================================

test "SimulatedExecutor: init and deinit" {
    const allocator = std.testing.allocator;

    var account = SimulatedAccount.init(allocator, Decimal.fromInt(10000));
    defer account.deinit();

    var executor = SimulatedExecutor.init(allocator, &account, null, null, .{});
    defer executor.deinit();

    try std.testing.expect(executor.next_order_id == 1000);
}

test "SimulatedExecutor: execute market order with price" {
    const allocator = std.testing.allocator;

    var account = SimulatedAccount.init(allocator, Decimal.fromInt(10000));
    defer account.deinit();

    var executor = SimulatedExecutor.init(allocator, &account, null, null, .{
        .log_trades = false,
    });
    defer executor.deinit();

    // 买入 1 ETH @ 2000
    const result = try executor.executeOrder(.{
        .client_order_id = "test-001",
        .symbol = "ETH",
        .side = .buy,
        .order_type = .market,
        .quantity = Decimal.fromInt(1),
        .price = Decimal.fromInt(2000),
    });

    try std.testing.expect(result.success);
    try std.testing.expectEqual(OrderStatus.filled, result.status);
    try std.testing.expect(result.filled_quantity.eql(Decimal.fromInt(1)));

    // 验证账户更新
    const pos = account.getPosition("ETH").?;
    try std.testing.expect(pos.quantity.eql(Decimal.fromInt(1)));
}

test "SimulatedExecutor: insufficient balance" {
    const allocator = std.testing.allocator;

    var account = SimulatedAccount.init(allocator, Decimal.fromInt(1000));
    defer account.deinit();

    var executor = SimulatedExecutor.init(allocator, &account, null, null, .{
        .log_trades = false,
    });
    defer executor.deinit();

    // 尝试买入 1 ETH @ 2000 (余额不足)
    const result = try executor.executeOrder(.{
        .client_order_id = "test-002",
        .symbol = "ETH",
        .side = .buy,
        .order_type = .market,
        .quantity = Decimal.fromInt(1),
        .price = Decimal.fromInt(2000),
    });

    try std.testing.expect(!result.success);
    try std.testing.expectEqual(@as(?u32, 5003), result.error_code);
}

test "SimulatedExecutor: asClient" {
    const allocator = std.testing.allocator;

    var account = SimulatedAccount.init(allocator, Decimal.fromInt(10000));
    defer account.deinit();

    var executor = SimulatedExecutor.init(allocator, &account, null, null, .{});
    defer executor.deinit();

    const client = executor.asClient();

    try std.testing.expect(client.vtable == &SimulatedExecutor.vtable);
    try std.testing.expect(@intFromPtr(client.ptr) != 0);
}

test "SimulatedExecutor: getBalance" {
    const allocator = std.testing.allocator;

    var account = SimulatedAccount.init(allocator, Decimal.fromInt(10000));
    defer account.deinit();

    var executor = SimulatedExecutor.init(allocator, &account, null, null, .{});
    defer executor.deinit();

    const client = executor.asClient();
    const balance = try client.getBalance();

    try std.testing.expect(balance.total.eql(Decimal.fromInt(10000)));
    try std.testing.expect(balance.available.eql(Decimal.fromInt(10000)));
}
