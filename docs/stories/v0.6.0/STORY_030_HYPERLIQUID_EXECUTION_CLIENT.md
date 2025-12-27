# Story 030: HyperliquidExecutionClient

**版本**: v0.6.0
**状态**: 规划中
**优先级**: P0
**预计时间**: 4-5 天
**前置条件**: v0.5.0 ExecutionEngine 完成, Story 029

---

## 目标

实现 `IExecutionClient` 接口的 Hyperliquid 适配器，将订单执行连接到 Hyperliquid DEX，支持订单提交、取消、查询和状态同步。

---

## 背景

### v0.5.0 架构回顾

```zig
// IExecutionClient 接口定义 (v0.5.0)
pub const IExecutionClient = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        submitOrder: *const fn (*anyopaque, Order) anyerror!OrderResult,
        cancelOrder: *const fn (*anyopaque, []const u8) anyerror!bool,
        cancelAllOrders: *const fn (*anyopaque) anyerror!u32,
        getOrderStatus: *const fn (*anyopaque, []const u8) anyerror!?OrderStatus,
        getPosition: *const fn (*anyopaque, []const u8) anyerror!?Position,
        getAccount: *const fn (*anyopaque) anyerror!Account,
    };
};
```

### Hyperliquid API

```
REST API:
- POST /exchange  - 下单、撤单
- POST /info      - 查询订单、仓位、账户

WebSocket:
- orderUpdates    - 订单状态更新
- userFills       - 成交通知
```

---

## 核心设计

### 架构图

```
┌─────────────────────────────────────────────────────────────┐
│              HyperliquidExecutionClient                      │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────────┐    ┌─────────────────┐                │
│  │   HttpClient    │    │  WebSocketClient │               │
│  │   (REST API)    │    │  (订单更新)      │               │
│  └────────┬────────┘    └────────┬────────┘                │
│           │                      │                          │
│           ↓                      ↓                          │
│  ┌──────────────────────────────────────────────────────┐  │
│  │                   OrderManager                        │  │
│  │      (订单状态追踪 + 本地缓存 + 同步验证)             │  │
│  └──────────────────────────────────────────────────────┘  │
│           │                      │                          │
│           ↓                      ↓                          │
│  ┌─────────────────┐    ┌─────────────────┐                │
│  │     Wallet      │    │   MessageBus    │                │
│  │   (签名)        │    │   (事件发布)    │                │
│  └─────────────────┘    └─────────────────┘                │
└─────────────────────────────────────────────────────────────┘
```

### 核心接口

```zig
pub const HyperliquidExecutionClient = struct {
    allocator: Allocator,
    config: Config,
    http_client: HttpClient,
    ws_client: *WebSocketClient,  // 共享 DataProvider 的连接
    wallet: Wallet,
    order_manager: OrderManager,
    message_bus: *MessageBus,

    pub const Config = struct {
        api_url: []const u8 = "https://api.hyperliquid.xyz",
        testnet: bool = false,
        private_key: []const u8,
        vault_address: ?[]const u8 = null,
    };

    // IExecutionClient VTable 实现
    pub const vtable = IExecutionClient.VTable{
        .submitOrder = submitOrder,
        .cancelOrder = cancelOrder,
        .cancelAllOrders = cancelAllOrders,
        .getOrderStatus = getOrderStatus,
        .getPosition = getPosition,
        .getAccount = getAccount,
    };

    /// 获取 IExecutionClient 接口
    pub fn asClient(self: *HyperliquidExecutionClient) IExecutionClient {
        return .{
            .ptr = self,
            .vtable = &vtable,
        };
    }

    /// 初始化
    pub fn init(
        allocator: Allocator,
        message_bus: *MessageBus,
        ws_client: *WebSocketClient,
        config: Config,
    ) !HyperliquidExecutionClient;
};
```

---

## 实现细节

### 1. 订单提交

```zig
fn submitOrder(ctx: *anyopaque, order: Order) !OrderResult {
    const self = @ptrCast(*HyperliquidExecutionClient, ctx);

    // 1. 构建订单请求
    const request = self.buildOrderRequest(order);

    // 2. 签名
    const signed = try self.wallet.signAction(request);

    // 3. 发送请求
    const response = try self.http_client.post("/exchange", signed);

    // 4. 解析响应
    const result = try self.parseOrderResponse(response);

    // 5. 更新本地状态
    try self.order_manager.trackOrder(order.client_order_id, result.exchange_order_id);

    // 6. 发布事件
    self.message_bus.publish("order.submitted", .{
        .order_submitted = .{
            .order_id = order.client_order_id,
            .instrument_id = order.symbol,
            .side = order.side,
            .order_type = order.order_type,
            .quantity = order.quantity.toFloat(),
            .price = if (order.price) |p| p.toFloat() else null,
            .status = .submitted,
            .timestamp = std.time.milliTimestamp() * 1_000_000,
        },
    });

    return result;
}

fn buildOrderRequest(self: *HyperliquidExecutionClient, order: Order) OrderRequest {
    return .{
        .action = .{
            .type = "order",
            .orders = &[_]OrderSpec{.{
                .a = self.getAssetIndex(order.symbol),
                .b = order.side == .buy,
                .p = order.price.?.toString(),
                .s = order.quantity.toString(),
                .r = false,  // reduce only
                .t = .{
                    .limit = .{
                        .tif = "Gtc",
                    },
                },
            }},
            .grouping = "na",
        },
        .nonce = std.time.milliTimestamp(),
        .signature = null,  // 将被签名填充
    };
}
```

### 2. 订单取消

```zig
fn cancelOrder(ctx: *anyopaque, order_id: []const u8) !bool {
    const self = @ptrCast(*HyperliquidExecutionClient, ctx);

    // 获取交易所订单 ID
    const exchange_oid = self.order_manager.getExchangeOrderId(order_id) orelse
        return error.OrderNotFound;

    // 构建取消请求
    const request = .{
        .action = .{
            .type = "cancel",
            .cancels = &[_]CancelSpec{.{
                .a = self.getAssetIndex(order.symbol),
                .o = exchange_oid,
            }},
        },
        .nonce = std.time.milliTimestamp(),
    };

    // 签名并发送
    const signed = try self.wallet.signAction(request);
    const response = try self.http_client.post("/exchange", signed);

    // 解析响应
    const success = try self.parseCancelResponse(response);

    if (success) {
        // 更新本地状态
        self.order_manager.markCancelled(order_id);

        // 发布事件
        self.message_bus.publish("order.cancelled", .{
            .order_cancelled = .{
                .order_id = order_id,
                .timestamp = std.time.milliTimestamp() * 1_000_000,
            },
        });
    }

    return success;
}
```

### 3. 订单状态同步 (WebSocket)

```zig
fn handleOrderUpdate(self: *HyperliquidExecutionClient, update: OrderUpdateMessage) void {
    const order_id = self.order_manager.getClientOrderId(update.oid) orelse {
        log.warn("Received update for unknown order: {}", .{update.oid});
        return;
    };

    // 更新本地状态
    self.order_manager.updateStatus(order_id, update.status);

    // 发布事件
    switch (update.status) {
        .filled => {
            self.message_bus.publish("order.filled", .{
                .order_filled = .{
                    .order = .{
                        .order_id = order_id,
                        .instrument_id = update.coin,
                        .side = update.side,
                        .price = update.px,
                        .filled_quantity = update.sz,
                        .status = .filled,
                    },
                    .fill_price = update.px,
                    .fill_quantity = update.sz,
                    .timestamp = update.time * 1_000_000,
                },
            });
        },
        .partial => {
            self.message_bus.publish("order.partial_fill", .{
                .order_partial = .{
                    .order_id = order_id,
                    .filled_quantity = update.sz,
                    .remaining_quantity = update.remaining,
                    .fill_price = update.px,
                    .timestamp = update.time * 1_000_000,
                },
            });
        },
        .cancelled => {
            self.message_bus.publish("order.cancelled", .{
                .order_cancelled = .{
                    .order_id = order_id,
                    .timestamp = update.time * 1_000_000,
                },
            });
        },
        else => {},
    }
}
```

### 4. 钱包签名

```zig
pub const Wallet = struct {
    private_key: [32]u8,
    address: [20]u8,

    pub fn init(private_key_hex: []const u8) !Wallet {
        var key: [32]u8 = undefined;
        _ = try std.fmt.hexToBytes(&key, private_key_hex);

        return .{
            .private_key = key,
            .address = deriveAddress(key),
        };
    }

    /// 签名交易动作
    pub fn signAction(self: *Wallet, action: anytype) !SignedAction {
        // 1. 序列化 action
        const payload = try std.json.stringifyAlloc(allocator, action, .{});

        // 2. 计算 EIP-712 类型哈希
        const hash = computeTypedDataHash(payload);

        // 3. ECDSA 签名
        const signature = try secp256k1.sign(self.private_key, hash);

        return .{
            .action = action,
            .signature = .{
                .r = signature.r,
                .s = signature.s,
                .v = signature.recovery_id + 27,
            },
            .nonce = action.nonce,
            .vaultAddress = null,
        };
    }
};
```

### 5. 仓位查询

```zig
fn getPosition(ctx: *anyopaque, symbol: []const u8) !?Position {
    const self = @ptrCast(*HyperliquidExecutionClient, ctx);

    const request = .{
        .type = "clearinghouseState",
        .user = self.wallet.address,
    };

    const response = try self.http_client.post("/info", request);
    const state = try std.json.parseFromSlice(ClearingHouseState, self.allocator, response, .{});

    // 查找指定交易对的仓位
    for (state.assetPositions) |pos| {
        if (std.mem.eql(u8, pos.coin, symbol)) {
            return .{
                .symbol = symbol,
                .side = if (pos.szi > 0) .long else .short,
                .quantity = Decimal.fromFloat(@abs(pos.szi)),
                .entry_price = Decimal.fromFloat(pos.entryPx),
                .unrealized_pnl = Decimal.fromFloat(pos.unrealizedPnl),
                .leverage = Decimal.fromFloat(pos.leverage),
            };
        }
    }

    return null;
}

fn getAccount(ctx: *anyopaque) !Account {
    const self = @ptrCast(*HyperliquidExecutionClient, ctx);

    const request = .{
        .type = "clearinghouseState",
        .user = self.wallet.address,
    };

    const response = try self.http_client.post("/info", request);
    const state = try std.json.parseFromSlice(ClearingHouseState, self.allocator, response, .{});

    return .{
        .balance = Decimal.fromFloat(state.marginSummary.accountValue),
        .available = Decimal.fromFloat(state.withdrawable),
        .margin_used = Decimal.fromFloat(state.marginSummary.totalMarginUsed),
        .unrealized_pnl = Decimal.fromFloat(state.marginSummary.totalUnrealizedPnl),
    };
}
```

---

## 测试计划

### 单元测试

```zig
test "order request building" {
    const order = Order{
        .client_order_id = "test-001",
        .symbol = "BTC",
        .side = .buy,
        .order_type = .limit,
        .quantity = Decimal.fromFloat(0.1),
        .price = Decimal.fromFloat(50000),
    };

    const request = client.buildOrderRequest(order);
    try testing.expect(request.action.orders[0].b == true);
}

test "wallet signature" {
    const wallet = try Wallet.init("0x...");
    const action = .{ .type = "test", .nonce = 12345 };
    const signed = try wallet.signAction(action);

    try testing.expect(signed.signature.v >= 27);
}
```

### 集成测试 (Testnet)

```zig
test "integration: submit and cancel order" {
    if (!std.os.getenv("RUN_TESTNET_TESTS")) return error.SkipTest;

    var client = try HyperliquidExecutionClient.init(allocator, .{
        .testnet = true,
        .private_key = std.os.getenv("TESTNET_PRIVATE_KEY") orelse return error.NoKey,
    });
    defer client.deinit();

    // 提交订单
    const result = try client.submitOrder(.{
        .symbol = "BTC",
        .side = .buy,
        .order_type = .limit,
        .quantity = Decimal.fromFloat(0.001),
        .price = Decimal.fromFloat(40000),  // 远离市价
    });

    try testing.expect(result.exchange_order_id != null);

    // 取消订单
    const cancelled = try client.cancelOrder(result.order_id);
    try testing.expect(cancelled);
}
```

---

## 成功指标

| 指标 | 目标 | 说明 |
|------|------|------|
| 下单延迟 | < 100ms | REST API 往返 |
| 状态同步延迟 | < 50ms | WebSocket 更新 |
| 签名速度 | < 1ms | ECDSA 签名 |
| 订单追踪准确率 | 100% | 本地状态与链上一致 |

---

## 文件结构

```
src/adapters/hyperliquid/
├── execution_client.zig        # HyperliquidExecutionClient
├── wallet.zig                  # 钱包和签名
├── order_manager.zig           # 订单状态管理
├── http_client.zig             # HTTP 客户端
└── tests/
    └── execution_test.zig      # 测试
```

---

**Story**: 030
**状态**: 规划中
**创建时间**: 2025-12-27
