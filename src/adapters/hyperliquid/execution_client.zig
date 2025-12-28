//! HyperliquidExecutionClient - Hyperliquid 执行客户端
//!
//! 实现 IExecutionClient 接口，封装 Hyperliquid Exchange API。
//! 支持订单提交、取消、状态查询和账户/仓位查询。

const std = @import("std");
const Allocator = std.mem.Allocator;

// Core types
const Decimal = @import("../../core/decimal.zig").Decimal;
const Timestamp = @import("../../core/time.zig").Timestamp;
const Logger = @import("../../core/logger.zig").Logger;
const MessageBus = @import("../../core/message_bus.zig").MessageBus;

// Execution engine types
const execution_engine = @import("../../core/execution_engine.zig");
const IExecutionClient = execution_engine.IExecutionClient;
const OrderRequest = execution_engine.OrderRequest;
const OrderResult = execution_engine.OrderResult;
const PositionInfo = execution_engine.PositionInfo;
const BalanceInfo = execution_engine.BalanceInfo;
const ExecOrderStatus = @import("../../exchange/types.zig").OrderStatus;

// Hyperliquid types
const HttpClient = @import("../../exchange/hyperliquid/http.zig").HttpClient;
const ExchangeAPI = @import("../../exchange/hyperliquid/exchange_api.zig").ExchangeAPI;
const InfoAPI = @import("../../exchange/hyperliquid/info_api.zig").InfoAPI;
const Signer = @import("../../exchange/hyperliquid/auth.zig").Signer;
const hl_types = @import("../../exchange/hyperliquid/types.zig");

/// 订单追踪器
const OrderTracker = struct {
    allocator: Allocator,
    /// client_order_id -> exchange_order_id 映射
    client_to_exchange: std.StringHashMap(u64),
    /// exchange_order_id -> client_order_id 映射
    exchange_to_client: std.AutoHashMap(u64, []const u8),
    /// 订单状态
    order_status: std.StringHashMap(ExecOrderStatus),

    pub fn init(allocator: Allocator) OrderTracker {
        return .{
            .allocator = allocator,
            .client_to_exchange = std.StringHashMap(u64).init(allocator),
            .exchange_to_client = std.AutoHashMap(u64, []const u8).init(allocator),
            .order_status = std.StringHashMap(ExecOrderStatus).init(allocator),
        };
    }

    pub fn deinit(self: *OrderTracker) void {
        // 释放所有分配的字符串
        var client_iter = self.client_to_exchange.iterator();
        while (client_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.client_to_exchange.deinit();

        var exchange_iter = self.exchange_to_client.iterator();
        while (exchange_iter.next()) |entry| {
            self.allocator.free(entry.value_ptr.*);
        }
        self.exchange_to_client.deinit();

        var status_iter = self.order_status.iterator();
        while (status_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.order_status.deinit();
    }

    /// 追踪订单
    pub fn track(self: *OrderTracker, client_order_id: []const u8, exchange_order_id: u64) !void {
        const client_id_copy = try self.allocator.dupe(u8, client_order_id);
        errdefer self.allocator.free(client_id_copy);

        const client_id_copy2 = try self.allocator.dupe(u8, client_order_id);
        errdefer self.allocator.free(client_id_copy2);

        const client_id_copy3 = try self.allocator.dupe(u8, client_order_id);
        errdefer self.allocator.free(client_id_copy3);

        try self.client_to_exchange.put(client_id_copy, exchange_order_id);
        try self.exchange_to_client.put(exchange_order_id, client_id_copy2);
        try self.order_status.put(client_id_copy3, .pending);
    }

    /// 获取交易所订单 ID
    pub fn getExchangeOrderId(self: *const OrderTracker, client_order_id: []const u8) ?u64 {
        return self.client_to_exchange.get(client_order_id);
    }

    /// 获取客户订单 ID
    pub fn getClientOrderId(self: *const OrderTracker, exchange_order_id: u64) ?[]const u8 {
        return self.exchange_to_client.get(exchange_order_id);
    }

    /// 更新订单状态
    pub fn updateStatus(self: *OrderTracker, client_order_id: []const u8, status: ExecOrderStatus) void {
        if (self.order_status.getPtr(client_order_id)) |ptr| {
            ptr.* = status;
        }
    }

    /// 获取订单状态
    pub fn getStatus(self: *const OrderTracker, client_order_id: []const u8) ?ExecOrderStatus {
        return self.order_status.get(client_order_id);
    }

    /// 移除订单追踪
    pub fn remove(self: *OrderTracker, client_order_id: []const u8) void {
        if (self.client_to_exchange.fetchRemove(client_order_id)) |kv| {
            const exchange_id = kv.value;
            self.allocator.free(kv.key);

            if (self.exchange_to_client.fetchRemove(exchange_id)) |ekv| {
                self.allocator.free(ekv.value);
            }
        }

        if (self.order_status.fetchRemove(client_order_id)) |kv| {
            self.allocator.free(kv.key);
        }
    }
};

/// 资产索引缓存
const AssetIndexCache = struct {
    allocator: Allocator,
    /// symbol -> asset_index 映射
    symbol_to_index: std.StringHashMap(u64),
    /// asset_index -> symbol 映射
    index_to_symbol: std.AutoHashMap(u64, []const u8),

    pub fn init(allocator: Allocator) AssetIndexCache {
        return .{
            .allocator = allocator,
            .symbol_to_index = std.StringHashMap(u64).init(allocator),
            .index_to_symbol = std.AutoHashMap(u64, []const u8).init(allocator),
        };
    }

    pub fn deinit(self: *AssetIndexCache) void {
        var iter = self.symbol_to_index.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.symbol_to_index.deinit();

        var idx_iter = self.index_to_symbol.iterator();
        while (idx_iter.next()) |entry| {
            self.allocator.free(entry.value_ptr.*);
        }
        self.index_to_symbol.deinit();
    }

    pub fn put(self: *AssetIndexCache, symbol: []const u8, index: u64) !void {
        const symbol_copy = try self.allocator.dupe(u8, symbol);
        errdefer self.allocator.free(symbol_copy);

        const symbol_copy2 = try self.allocator.dupe(u8, symbol);
        errdefer self.allocator.free(symbol_copy2);

        try self.symbol_to_index.put(symbol_copy, index);
        try self.index_to_symbol.put(index, symbol_copy2);
    }

    pub fn getIndex(self: *const AssetIndexCache, symbol: []const u8) ?u64 {
        return self.symbol_to_index.get(symbol);
    }

    pub fn getSymbol(self: *const AssetIndexCache, index: u64) ?[]const u8 {
        return self.index_to_symbol.get(index);
    }
};

/// Hyperliquid 执行客户端
pub const HyperliquidExecutionClient = struct {
    allocator: Allocator,
    config: Config,
    logger: Logger,

    // API 客户端
    http_client: HttpClient,
    exchange_api: ExchangeAPI,
    info_api: InfoAPI,
    signer: ?Signer,

    // 订单追踪
    order_tracker: OrderTracker,

    // 资产索引缓存
    asset_cache: AssetIndexCache,

    // MessageBus (可选)
    message_bus: ?*MessageBus,

    pub const Config = struct {
        /// 是否使用测试网
        testnet: bool = false,
        /// 私钥 (32 字节)
        private_key: ?[32]u8 = null,
    };

    const Self = @This();

    /// 初始化
    pub fn init(
        allocator: Allocator,
        config: Config,
        logger: Logger,
        message_bus: ?*MessageBus,
    ) !Self {
        var http_client = HttpClient.init(allocator, config.testnet, logger);

        // 初始化签名器 (如果提供了私钥)
        var signer: ?Signer = null;
        if (config.private_key) |pk| {
            signer = try Signer.init(allocator, pk, config.testnet);
        }

        var signer_ptr: ?*Signer = null;
        if (signer != null) {
            signer_ptr = &signer.?;
        }

        const exchange_api = ExchangeAPI.init(allocator, &http_client, signer_ptr, logger);
        const info_api = InfoAPI.init(allocator, &http_client, logger);

        return .{
            .allocator = allocator,
            .config = config,
            .logger = logger,
            .http_client = http_client,
            .exchange_api = exchange_api,
            .info_api = info_api,
            .signer = signer,
            .order_tracker = OrderTracker.init(allocator),
            .asset_cache = AssetIndexCache.init(allocator),
            .message_bus = message_bus,
        };
    }

    /// 释放资源
    pub fn deinit(self: *Self) void {
        self.order_tracker.deinit();
        self.asset_cache.deinit();
        if (self.signer) |*s| {
            s.deinit();
        }
        self.http_client.deinit();
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

        self.logger.info("Submitting order", .{
            .symbol = request.symbol,
            .side = @tagName(request.side),
            .quantity = request.quantity.toFloat(),
        }) catch {};

        // 检查签名器
        if (self.signer == null) {
            return OrderResult{
                .success = false,
                .error_code = 4001,
                .error_message = "Signer not configured",
                .timestamp = Timestamp.now(),
            };
        }

        // 获取资产索引
        var asset_index = self.asset_cache.getIndex(request.symbol);

        if (asset_index == null) {
            // 尝试加载资产元数据
            self.loadAssetMeta() catch {
                return OrderResult{
                    .success = false,
                    .error_code = 4002,
                    .error_message = "Failed to load asset metadata",
                    .timestamp = Timestamp.now(),
                };
            };

            asset_index = self.asset_cache.getIndex(request.symbol);
            if (asset_index == null) {
                return OrderResult{
                    .success = false,
                    .error_code = 4003,
                    .error_message = "Unknown asset symbol",
                    .timestamp = Timestamp.now(),
                };
            }
        }

        const final_asset_index = asset_index.?;

        // 构建 Hyperliquid 订单请求
        const price_str = if (request.price) |p|
            p.toString(self.allocator) catch "0"
        else
            "0";
        defer if (request.price != null) self.allocator.free(price_str);

        const size_str = request.quantity.toString(self.allocator) catch "0";
        defer self.allocator.free(size_str);

        const hl_order_type: hl_types.HyperliquidOrderType = switch (request.order_type) {
            .limit => .{ .limit = .{ .tif = "Gtc" } },
            .market => .{ .market = .{} },
        };

        const hl_request = hl_types.OrderRequest{
            .asset_index = final_asset_index,
            .coin = request.symbol,
            .is_buy = request.side == .buy,
            .sz = size_str,
            .limit_px = price_str,
            .order_type = hl_order_type,
            .reduce_only = request.reduce_only,
        };

        // 调用 Exchange API
        const response = self.exchange_api.placeOrder(hl_request) catch |err| {
            self.logger.err("Order submission failed: {s}", .{@errorName(err)}) catch {};
            return OrderResult{
                .success = false,
                .error_code = 4004,
                .error_message = @errorName(err),
                .timestamp = Timestamp.now(),
            };
        };

        // 解析响应
        if (!std.mem.eql(u8, response.status, "ok")) {
            return OrderResult{
                .success = false,
                .error_code = 4005,
                .error_message = "Order rejected by exchange",
                .timestamp = Timestamp.now(),
            };
        }

        // 提取订单 ID
        var exchange_order_id: ?u64 = null;
        var filled_quantity = Decimal.ZERO;
        var avg_fill_price: ?Decimal = null;
        var status = ExecOrderStatus.pending;

        if (response.response.data) |data| {
            if (data.statuses.len > 0) {
                const first_status = data.statuses[0];
                if (first_status.resting) |resting| {
                    exchange_order_id = resting.oid;
                    status = .open;
                } else if (first_status.filled) |filled| {
                    exchange_order_id = filled.oid;
                    status = .filled;
                    filled_quantity = Decimal.fromString(filled.totalSz) catch Decimal.ZERO;
                    avg_fill_price = Decimal.fromString(filled.avgPx) catch null;
                }
            }
        }

        // 追踪订单
        if (exchange_order_id) |oid| {
            self.order_tracker.track(request.client_order_id, oid) catch {};
        }

        // 发布事件
        if (self.message_bus) |bus| {
            bus.publish("order.submitted", .{
                .order_submitted = .{
                    .order_id = request.client_order_id,
                    .instrument_id = request.symbol,
                    .side = if (request.side == .buy) .buy else .sell,
                    .order_type = if (request.order_type == .market) .market else .limit,
                    .quantity = request.quantity.toFloat(),
                    .price = if (request.price) |p| p.toFloat() else null,
                    .status = .submitted,
                    .timestamp = Timestamp.now().millis * 1_000_000,
                },
            });
        }

        self.logger.info("Order submitted successfully", .{
            .order_id = request.client_order_id,
            .exchange_order_id = exchange_order_id,
        }) catch {};

        return OrderResult{
            .success = true,
            .order_id = request.client_order_id,
            .exchange_order_id = exchange_order_id,
            .status = status,
            .filled_quantity = filled_quantity,
            .avg_fill_price = avg_fill_price,
            .timestamp = Timestamp.now(),
        };
    }

    fn cancelOrder(ptr: *anyopaque, order_id: []const u8) anyerror!void {
        const self: *Self = @ptrCast(@alignCast(ptr));

        self.logger.info("Cancelling order", .{ .order_id = order_id }) catch {};

        // 获取交易所订单 ID
        const exchange_order_id = self.order_tracker.getExchangeOrderId(order_id) orelse {
            return error.OrderNotFound;
        };

        // 获取资产索引 (需要从订单中获取，这里简化处理)
        // TODO: 需要解决 存储订单的 symbol 以便查询资产索引
        const asset_index: u64 = 0; // 默认使用 0 (ETH)

        // 调用 Exchange API
        _ = self.exchange_api.cancelOrder(asset_index, exchange_order_id) catch |err| {
            self.logger.err("Cancel order failed: {s}", .{@errorName(err)}) catch {};
            return err;
        };

        // 更新追踪状态
        self.order_tracker.updateStatus(order_id, .cancelled);

        // 发布事件
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

        self.logger.info("Order cancelled successfully", .{ .order_id = order_id }) catch {};
    }

    fn getOrderStatus(ptr: *anyopaque, order_id: []const u8) anyerror!?ExecOrderStatus {
        const self: *Self = @ptrCast(@alignCast(ptr));

        // 首先检查本地缓存
        if (self.order_tracker.getStatus(order_id)) |status| {
            return status;
        }

        // 如果有签名器，可以查询交易所
        if (self.signer) |*s| {
            // 查询用户的 open orders
            const response = self.info_api.getOpenOrders(s.address) catch {
                return null;
            };
            defer response.deinit();

            // 查找订单
            for (response.value) |order| {
                if (order.cloid) |cloid| {
                    if (std.mem.eql(u8, cloid, order_id)) {
                        return .open;
                    }
                }
            }
        }

        return null;
    }

    fn getPosition(ptr: *anyopaque, symbol: []const u8) anyerror!?PositionInfo {
        const self: *Self = @ptrCast(@alignCast(ptr));

        if (self.signer == null) {
            return null;
        }

        // 查询用户状态
        const response = self.info_api.getUserState(self.signer.?.address) catch {
            return null;
        };
        defer response.deinit();

        // 查找指定交易对的仓位
        for (response.value.assetPositions) |ap| {
            if (std.mem.eql(u8, ap.position.coin, symbol)) {
                const szi = Decimal.fromString(ap.position.szi) catch Decimal.ZERO;
                const entry_px = if (ap.position.entryPx) |px|
                    Decimal.fromString(px) catch Decimal.ZERO
                else
                    Decimal.ZERO;
                const unrealized_pnl = Decimal.fromString(ap.position.unrealizedPnl) catch Decimal.ZERO;

                const side: PositionInfo.PositionSide = if (szi.toFloat() > 0)
                    .long
                else if (szi.toFloat() < 0)
                    .short
                else
                    .flat;

                return PositionInfo{
                    .symbol = symbol,
                    .side = side,
                    .quantity = Decimal.fromFloat(@abs(szi.toFloat())),
                    .entry_price = entry_px,
                    .mark_price = entry_px, // TODO: 获取 mark price
                    .unrealized_pnl = unrealized_pnl,
                    .realized_pnl = Decimal.ZERO,
                    .leverage = ap.position.leverage.value,
                    .liquidation_price = if (ap.position.liquidationPx) |px|
                        Decimal.fromString(px) catch null
                    else
                        null,
                    .timestamp = Timestamp.now(),
                };
            }
        }

        return null;
    }

    fn getBalance(ptr: *anyopaque) anyerror!BalanceInfo {
        const self: *Self = @ptrCast(@alignCast(ptr));

        if (self.signer == null) {
            return BalanceInfo{
                .total = Decimal.ZERO,
                .available = Decimal.ZERO,
                .locked = Decimal.ZERO,
                .unrealized_pnl = Decimal.ZERO,
                .timestamp = Timestamp.now(),
            };
        }

        // 查询用户状态
        const response = self.info_api.getUserState(self.signer.?.address) catch {
            return BalanceInfo{
                .total = Decimal.ZERO,
                .available = Decimal.ZERO,
                .locked = Decimal.ZERO,
                .unrealized_pnl = Decimal.ZERO,
                .timestamp = Timestamp.now(),
            };
        };
        defer response.deinit();

        const total = Decimal.fromString(response.value.marginSummary.accountValue) catch Decimal.ZERO;
        const available = Decimal.fromString(response.value.withdrawable) catch Decimal.ZERO;
        const margin_used = Decimal.fromString(response.value.marginSummary.totalMarginUsed) catch Decimal.ZERO;

        return BalanceInfo{
            .total = total,
            .available = available,
            .locked = margin_used,
            .unrealized_pnl = Decimal.ZERO, // TODO: 计算未实现盈亏
            .timestamp = Timestamp.now(),
        };
    }

    // ========================================================================
    // 辅助方法
    // ========================================================================

    /// 加载资产元数据
    fn loadAssetMeta(self: *Self) !void {
        const response = try self.info_api.getMeta();
        defer response.deinit();

        for (response.value.universe, 0..) |asset, i| {
            try self.asset_cache.put(asset.name, i);
        }

        self.logger.debug("Loaded asset metadata", .{
            .count = response.value.universe.len,
        }) catch {};
    }

    /// 获取钱包地址
    pub fn getAddress(self: *const Self) ?[]const u8 {
        if (self.signer) |*s| {
            return s.address;
        }
        return null;
    }

    /// 检查是否已配置私钥
    pub fn hasPrivateKey(self: *const Self) bool {
        return self.signer != null;
    }
};

// ============================================================================
// 测试
// ============================================================================

test "HyperliquidExecutionClient: init without private key" {
    const allocator = std.testing.allocator;

    // 创建 dummy logger
    const DummyWriter = struct {
        fn write(_: *anyopaque, _: @import("../../core/logger.zig").LogRecord) anyerror!void {}
        fn flush(_: *anyopaque) anyerror!void {}
        fn close(_: *anyopaque) void {}
    };

    const writer = @import("../../core/logger.zig").LogWriter{
        .ptr = @ptrCast(@constCast(&struct {}{})),
        .writeFn = DummyWriter.write,
        .flushFn = DummyWriter.flush,
        .closeFn = DummyWriter.close,
    };

    const logger = @import("../../core/logger.zig").Logger.init(allocator, writer, .debug);

    var client = try HyperliquidExecutionClient.init(allocator, .{ .testnet = true }, logger, null);
    defer client.deinit();

    try std.testing.expect(!client.hasPrivateKey());
    try std.testing.expect(client.getAddress() == null);
}

test "OrderTracker: basic operations" {
    const allocator = std.testing.allocator;

    var tracker = OrderTracker.init(allocator);
    defer tracker.deinit();

    // 追踪订单
    try tracker.track("order-001", 12345);

    // 验证映射
    try std.testing.expectEqual(@as(u64, 12345), tracker.getExchangeOrderId("order-001").?);
    try std.testing.expectEqualStrings("order-001", tracker.getClientOrderId(12345).?);
    try std.testing.expectEqual(ExecOrderStatus.pending, tracker.getStatus("order-001").?);

    // 更新状态
    tracker.updateStatus("order-001", .filled);
    try std.testing.expectEqual(ExecOrderStatus.filled, tracker.getStatus("order-001").?);

    // 移除订单
    tracker.remove("order-001");
    try std.testing.expect(tracker.getExchangeOrderId("order-001") == null);
}

test "AssetIndexCache: basic operations" {
    const allocator = std.testing.allocator;

    var cache = AssetIndexCache.init(allocator);
    defer cache.deinit();

    // 添加资产
    try cache.put("ETH", 0);
    try cache.put("BTC", 3);

    // 验证查询
    try std.testing.expectEqual(@as(u64, 0), cache.getIndex("ETH").?);
    try std.testing.expectEqual(@as(u64, 3), cache.getIndex("BTC").?);
    try std.testing.expectEqualStrings("ETH", cache.getSymbol(0).?);
    try std.testing.expectEqualStrings("BTC", cache.getSymbol(3).?);
    try std.testing.expect(cache.getIndex("UNKNOWN") == null);
}

test "HyperliquidExecutionClient: asClient" {
    const allocator = std.testing.allocator;

    // 创建 dummy logger
    const DummyWriter = struct {
        fn write(_: *anyopaque, _: @import("../../core/logger.zig").LogRecord) anyerror!void {}
        fn flush(_: *anyopaque) anyerror!void {}
        fn close(_: *anyopaque) void {}
    };

    const writer = @import("../../core/logger.zig").LogWriter{
        .ptr = @ptrCast(@constCast(&struct {}{})),
        .writeFn = DummyWriter.write,
        .flushFn = DummyWriter.flush,
        .closeFn = DummyWriter.close,
    };

    const logger = @import("../../core/logger.zig").Logger.init(allocator, writer, .debug);

    var client = try HyperliquidExecutionClient.init(allocator, .{ .testnet = true }, logger, null);
    defer client.deinit();

    const exec_client = client.asClient();

    // 验证接口
    try std.testing.expect(exec_client.vtable == &HyperliquidExecutionClient.vtable);
    try std.testing.expect(@intFromPtr(exec_client.ptr) != 0);
}
