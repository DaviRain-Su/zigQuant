# Story: Hyperliquid HTTP 客户端实现

> **更新日期**: 2025-12-23
> **更新内容**: 基于 Hyperliquid 真实 API 规范更新（参考: [API Research](HYPERLIQUID_API_RESEARCH.md)）

**ID**: `STORY-006`
**版本**: `v0.2`
**创建日期**: 2025-12-23
**状态**: 📋 计划中
**优先级**: P0 (必须)
**预计工时**: 5 天

---

## 📋 需求描述

### 用户故事
作为**量化交易开发者**，我希望**有一个可靠的 Hyperliquid HTTP 客户端**，以便**获取市场数据并执行交易操作**。

### 背景
Hyperliquid 是一个高性能的 L1 区块链 DEX，提供完整的 REST API 支持。我们需要实现：
- **Info API**: 获取市场数据（订单簿、交易历史、账户信息）
- **Exchange API**: 执行交易操作（下单、撤单、查询订单）
- **Ed25519 签名**: 用于请求认证

> 决策依据：[ADR-002: 选择 Hyperliquid 作为首个支持的交易所](../../docs/decisions/002-hyperliquid-first-exchange.md)

### 范围
- **包含**:
  - Ed25519 签名生成
  - HTTP 客户端封装（基于 `std.http.Client`）
  - Info API 端点（市场数据）
  - Exchange API 端点（交易操作）
  - 请求/响应序列化（JSON）
  - 错误处理和重试机制
  - 速率限制管理

- **不包含**:
  - WebSocket 实时数据流（见 Story 007）
  - 订单簿维护（见 Story 008）
  - 高级订单类型（TP/SL）（后续 Story）

---

## 🎯 验收标准

- [ ] Ed25519 签名生成正确
- [ ] 成功连接 Hyperliquid 测试网
- [ ] Info API 所有端点实现并测试通过
- [ ] Exchange API 核心端点实现（下单、撤单、查询）
- [ ] 错误处理完整，网络故障能自动重试
- [ ] 速率限制正确实现，避免被封禁
- [ ] 所有测试用例通过
- [ ] 集成测试通过（实际连接测试网）

---

## 🔧 技术设计

### 架构概览

```
src/exchange/hyperliquid/
├── http.zig              # HTTP 客户端核心
├── auth.zig              # Ed25519 签名认证
├── info_api.zig          # Info API 端点
├── exchange_api.zig      # Exchange API 端点
├── types.zig             # 数据类型定义
├── rate_limit.zig        # 速率限制器
└── http_test.zig         # 测试
```

### 核心数据结构

#### 1. HTTP 客户端

```zig
// src/exchange/hyperliquid/http.zig

const std = @import("std");
const Decimal = @import("../../core/decimal.zig").Decimal;
const Timestamp = @import("../../core/time.zig").Timestamp;
const Error = @import("../../core/error.zig").Error;
const Logger = @import("../../core/logger.zig").Logger;

pub const HyperliquidConfig = struct {
    base_url: []const u8,
    api_key: ?[]const u8,
    secret_key: ?[]const u8,
    testnet: bool,
    timeout_ms: u64,
    max_retries: u8,

    pub const DEFAULT_MAINNET_URL = "https://api.hyperliquid.xyz";
    pub const DEFAULT_TESTNET_URL = "https://api.hyperliquid-testnet.xyz";
};

pub const HyperliquidClient = struct {
    allocator: std.mem.Allocator,
    config: HyperliquidConfig,
    http_client: std.http.Client,
    auth: Auth,
    rate_limiter: RateLimiter,
    logger: Logger,

    pub fn init(
        allocator: std.mem.Allocator,
        config: HyperliquidConfig,
        logger: Logger,
    ) !HyperliquidClient {
        return .{
            .allocator = allocator,
            .config = config,
            .http_client = std.http.Client{ .allocator = allocator },
            .auth = try Auth.init(allocator, config.secret_key),
            .rate_limiter = RateLimiter.init(),
            .logger = logger,
        };
    }

    pub fn deinit(self: *HyperliquidClient) void {
        self.http_client.deinit();
        self.auth.deinit();
    }

    /// 发送 GET 请求
    pub fn get(
        self: *HyperliquidClient,
        endpoint: []const u8,
        params: ?std.json.Value,
    ) !std.json.Value {
        // 实现 GET 请求
    }

    /// 发送 POST 请求（需要签名）
    pub fn post(
        self: *HyperliquidClient,
        endpoint: []const u8,
        body: std.json.Value,
    ) !std.json.Value {
        // 实现 POST 请求
    }

    /// 重试逻辑
    fn retryRequest(
        self: *HyperliquidClient,
        request_fn: anytype,
    ) !std.json.Value {
        var retries: u8 = 0;
        while (retries < self.config.max_retries) : (retries += 1) {
            const result = request_fn() catch |err| {
                if (retries == self.config.max_retries - 1) {
                    return err;
                }
                self.logger.warn("Request failed, retrying... ({}/{})", .{
                    retries + 1, self.config.max_retries,
                });
                std.time.sleep(std.time.ns_per_s * @as(u64, @intCast(retries + 1)));
                continue;
            };
            return result;
        }
        unreachable;
    }
};
```

#### 2. Ed25519 认证 (基于真实 API)

```zig
// src/exchange/hyperliquid/auth.zig
// 基于真实 API: Ed25519 签名，使用 nonce (毫秒时间戳) 和 connection_id

const std = @import("std");

pub const Auth = struct {
    allocator: std.mem.Allocator,
    secret_key: ?[]const u8,
    keypair: ?std.crypto.sign.Ed25519.KeyPair,

    pub fn init(allocator: std.mem.Allocator, secret_key: ?[]const u8) !Auth {
        var keypair: ?std.crypto.sign.Ed25519.KeyPair = null;

        if (secret_key) |key| {
            // 从 hex 字符串解析私钥
            var seed: [32]u8 = undefined;
            _ = try std.fmt.hexToBytes(&seed, key);
            keypair = try std.crypto.sign.Ed25519.KeyPair.create(seed);
        }

        return .{
            .allocator = allocator,
            .secret_key = secret_key,
            .keypair = keypair,
        };
    }

    pub fn deinit(self: *Auth) void {
        _ = self;
    }

    /// 生成 nonce (基于真实 API: 使用毫秒时间戳)
    pub fn generateNonce() i64 {
        return std.time.milliTimestamp();
    }

    /// 生成请求签名 (基于真实 API: sign_l1_action)
    /// 签名消息格式: action 的 msgpack 序列化 + nonce
    pub fn signL1Action(
        self: *Auth,
        action: []const u8,  // action 的 JSON/msgpack
        nonce: i64,
    ) !Signature {
        if (self.keypair == null) {
            return error.NoSecretKey;
        }

        // 构造签名消息
        // 注意: 实际实现需要使用 msgpack 而非 JSON
        var msg_buffer: [4096]u8 = undefined;
        const msg = try std.fmt.bufPrint(&msg_buffer, "{s}{d}", .{
            action, nonce,
        });

        // Ed25519 签名
        const signature = try self.keypair.?.sign(msg, null);

        // 转换为签名结构 (r, s, v 格式)
        return Signature{
            .r = signature.toBytes()[0..32].*,
            .s = signature.toBytes()[32..64].*,
            .v = 27,  // 或 28，取决于恢复 ID
        };
    }

    /// 获取用户地址 (基于公钥派生)
    pub fn getUserAddress(self: *Auth) ![]const u8 {
        if (self.keypair == null) {
            return error.NoSecretKey;
        }

        // 从 Ed25519 公钥派生以太坊地址
        // 注意: 实际实现需要 Keccak256 哈希
        const pub_key = self.keypair.?.public_key;
        var address: [42]u8 = undefined;
        _ = try std.fmt.bufPrint(&address, "0x{x}", .{pub_key.bytes[0..20]});

        return try self.allocator.dupe(u8, &address);
    }
};

/// 签名结构 (基于真实 API)
pub const Signature = struct {
    r: [32]u8,
    s: [32]u8,
    v: u8,

    pub fn toHex(self: Signature, allocator: std.mem.Allocator) ![]u8 {
        return try std.fmt.allocPrint(allocator, "0x{x}{x}", .{
            self.r, self.s,
        });
    }
};
```

#### 3. Info API

```zig
// src/exchange/hyperliquid/info_api.zig
// 基于真实 API: 所有 Info API 使用 POST /info，通过 type 字段区分端点

const std = @import("std");
const HyperliquidClient = @import("http.zig").HyperliquidClient;
const Decimal = @import("../../core/decimal.zig").Decimal;
const Timestamp = @import("../../core/time.zig").Timestamp;

/// 获取所有币种中间价 (基于真实 API: allMids)
pub fn getAllMids(client: *HyperliquidClient) !std.StringHashMap(Decimal) {
    const body = .{
        .type = "allMids",
        .dex = "",  // 空字符串表示第一个 perp DEX
    };
    const result = try client.post("/info", body);
    return try parseAllMids(client.allocator, result);
}

/// 获取资产元数据 (基于真实 API: meta)
pub fn getMeta(client: *HyperliquidClient) !Meta {
    const body = .{
        .type = "meta",
    };
    const result = try client.post("/info", body);
    return try parseMeta(client.allocator, result);
}

/// 获取订单簿快照 (基于真实 API: l2Book)
pub fn getL2Book(
    client: *HyperliquidClient,
    coin: []const u8,
) !OrderBook {
    const body = .{
        .type = "l2Book",
        .coin = coin,
    };
    const result = try client.post("/info", body);
    return try parseOrderBook(client.allocator, result);
}

/// 获取用户账户状态 (基于真实 API: clearinghouseState / userState)
pub fn getUserState(
    client: *HyperliquidClient,
    user_address: []const u8,
) !UserState {
    const body = .{
        .type = "clearinghouseState",
        .user = user_address,  // 主账户或子账户地址，非 API wallet 地址
    };
    const result = try client.post("/info", body);
    return try parseUserState(client.allocator, result);
}

/// 获取用户成交历史 (基于真实 API: userFills)
pub fn getUserFills(
    client: *HyperliquidClient,
    user_address: []const u8,
) ![]Fill {
    const body = .{
        .type = "userFills",
        .user = user_address,
    };
    const result = try client.post("/info", body);
    return try parseFills(client.allocator, result);
}

/// 获取未完成订单 (基于真实 API: openOrders)
pub fn getOpenOrders(
    client: *HyperliquidClient,
    user_address: []const u8,
) ![]OpenOrder {
    const body = .{
        .type = "openOrders",
        .user = user_address,
    };
    const result = try client.post("/info", body);
    return try parseOpenOrders(client.allocator, result);
}

// 数据类型 (基于真实 API 响应格式)

/// Meta 响应
pub const Meta = struct {
    universe: []AssetInfo,
};

pub const AssetInfo = struct {
    name: []const u8,
    szDecimals: u8,
    maxLeverage: u32,
    onlyIsolated: bool,
};

/// L2 订单簿 (基于真实 API 响应)
pub const OrderBook = struct {
    coin: []const u8,
    time: Timestamp,
    levels: [2][]Level,  // [0]=bids, [1]=asks

    pub const Level = struct {
        px: Decimal,   // 价格
        sz: Decimal,   // 数量
        n: u32,        // 订单数量
    };
};

/// 用户状态 (基于真实 API: clearinghouseState 响应)
pub const UserState = struct {
    assetPositions: []AssetPosition,
    marginSummary: MarginSummary,
    crossMarginSummary: MarginSummary,
    crossMaintenanceMarginUsed: Decimal,
    withdrawable: Decimal,
    time: Timestamp,

    pub const MarginSummary = struct {
        accountValue: Decimal,       // 账户总价值
        totalMarginUsed: Decimal,    // 总已用保证金
        totalNtlPos: Decimal,        // 总名义仓位价值
        totalRawUsd: Decimal,        // 总原始 USD
    };

    pub const AssetPosition = struct {
        position: Position,
        type_: []const u8,  // "oneWay" 或 "hedge"
    };
};

/// 仓位信息 (基于真实 API)
pub const Position = struct {
    coin: []const u8,
    szi: Decimal,                    // 仓位大小（有符号: +多头, -空头）
    entryPx: Decimal,                // 开仓均价
    leverage: Leverage,
    liquidationPx: ?Decimal,         // 清算价格
    marginUsed: Decimal,             // 已用保证金
    maxLeverage: u32,
    positionValue: Decimal,
    returnOnEquity: Decimal,
    unrealizedPnl: Decimal,          // 未实现盈亏
    cumFunding: CumFunding,

    pub const Leverage = struct {
        type_: []const u8,           // "cross" 或 "isolated"
        value: u32,                  // 杠杆倍数
        rawUsd: Decimal,
    };

    pub const CumFunding = struct {
        allTime: Decimal,
        sinceChange: Decimal,
        sinceOpen: Decimal,
    };
};

/// 成交记录 (基于真实 API: userFills)
pub const Fill = struct {
    coin: []const u8,
    px: Decimal,                     // 成交价格
    sz: Decimal,                     // 成交数量
    side: []const u8,                // "B" (买) 或 "A" (卖)
    time: Timestamp,
    startPosition: Decimal,
    dir: []const u8,                 // "Open Long", "Close Short", 等
    closedPnl: Decimal,              // 已实现盈亏
    hash: []const u8,
    oid: u64,                        // 订单 ID
    crossed: bool,
    fee: Decimal,
    feeToken: []const u8,            // 手续费币种 (如 "USDC")
    tid: u64,                        // 成交 ID
};
```

#### 4. Exchange API (基于真实 API)

```zig
// src/exchange/hyperliquid/exchange_api.zig
// 基于真实 API: 所有交易操作使用 POST /exchange，需要 Ed25519 签名

const std = @import("std");
const HyperliquidClient = @import("http.zig").HyperliquidClient;
const Auth = @import("auth.zig").Auth;
const Decimal = @import("../../core/decimal.zig").Decimal;

/// 下单 (基于真实 API: order action)
pub fn placeOrder(
    client: *HyperliquidClient,
    order: OrderRequest,
) !OrderResponse {
    // 生成 nonce
    const nonce = Auth.generateNonce();

    // 构造 action
    const action = .{
        .type = "order",
        .orders = &[_]Order{order.toApiFormat()},
        .grouping = "na",
    };

    // 签名
    const action_json = try std.json.stringifyAlloc(client.allocator, action, .{});
    defer client.allocator.free(action_json);

    const signature = try client.auth.signL1Action(action_json, nonce);

    // 构造请求体
    const body = .{
        .action = action,
        .nonce = nonce,
        .signature = signature,
        .vaultAddress = null,
    };

    const result = try client.post("/exchange", body);
    return try parseOrderResponse(client.allocator, result);
}

/// 撤单 (基于真实 API: cancel action)
pub fn cancelOrder(
    client: *HyperliquidClient,
    coin: []const u8,
    oid: u64,
) !CancelResponse {
    const nonce = Auth.generateNonce();

    const action = .{
        .type = "cancel",
        .cancels = &[_]Cancel{.{
            .a = try getAssetIndex(client, coin),  // 资产索引
            .o = oid,
        }},
    };

    const action_json = try std.json.stringifyAlloc(client.allocator, action, .{});
    defer client.allocator.free(action_json);

    const signature = try client.auth.signL1Action(action_json, nonce);

    const body = .{
        .action = action,
        .nonce = nonce,
        .signature = signature,
        .vaultAddress = null,
    };

    const result = try client.post("/exchange", body);
    return try parseCancelResponse(client.allocator, result);
}

/// 批量撤单 (基于真实 API: bulk_cancel)
pub fn bulkCancel(
    client: *HyperliquidClient,
    cancels: []CancelRequest,
) !CancelResponse {
    // 类似 cancelOrder，但传递多个 cancels
    // ...
}

/// 修改订单 (基于真实 API: modify action)
pub fn modifyOrder(
    client: *HyperliquidClient,
    oid: u64,
    order: OrderRequest,
) !OrderResponse {
    // 实现类似 placeOrder，但 action.type = "modify"
    // ...
}

/// 市价开仓 (基于真实 API: 使用 IOC 限价单模拟)
pub fn marketOpen(
    client: *HyperliquidClient,
    coin: []const u8,
    is_buy: bool,
    sz: Decimal,
    slippage: Decimal,
) !OrderResponse {
    // 获取当前市价
    const mids = try client.getAllMids();
    const mid_price = mids.get(coin) orelse return error.NoPriceData;

    // 计算限价（带滑点保护）
    const limit_px = if (is_buy)
        mid_price.mul(Decimal.ONE.add(slippage))
    else
        mid_price.mul(Decimal.ONE.sub(slippage));

    // 下 IOC 限价单
    return try placeOrder(client, .{
        .coin = coin,
        .is_buy = is_buy,
        .sz = sz,
        .limit_px = limit_px,
        .order_type = .{ .limit = .{ .tif = "Ioc" } },
        .reduce_only = false,
    });
}

// 数据类型 (基于真实 API)

/// 订单请求 (基于真实 API 格式)
pub const OrderRequest = struct {
    coin: []const u8,
    is_buy: bool,
    sz: Decimal,
    limit_px: Decimal,
    order_type: OrderType,
    reduce_only: bool,
    cloid: ?[]const u8 = null,  // 客户端订单 ID (可选)

    /// 转换为 API 格式
    pub fn toApiFormat(self: OrderRequest) Order {
        return .{
            .a = getAssetIndex(self.coin),  // 资产索引
            .b = self.is_buy,
            .p = self.limit_px.toString(),
            .s = self.sz.toString(),
            .r = self.reduce_only,
            .t = self.order_type,
            .c = self.cloid,
        };
    }
};

/// API 订单格式 (基于真实 API)
pub const Order = struct {
    a: u32,              // 资产索引 (asset index)
    b: bool,             // 买/卖 (true=买, false=卖)
    p: []const u8,       // 限价 (字符串，保留精度)
    s: []const u8,       // 数量 (字符串)
    r: bool,             // 仅减仓 (reduce-only)
    t: OrderType,        // 订单类型
    c: ?[]const u8,      // 客户端订单 ID (可选)
};

/// 订单类型 (基于真实 API: 只有 Gtc, Ioc, Alo)
pub const OrderType = struct {
    limit: ?LimitOrder = null,
    trigger: ?TriggerOrder = null,

    pub const LimitOrder = struct {
        tif: []const u8,  // "Gtc", "Ioc", "Alo" (无 FOK)
    };

    pub const TriggerOrder = struct {
        triggerPx: []const u8,
        isMarket: bool,
        tpsl: []const u8,  // "tp" 或 "sl"
    };
};

/// 订单响应 (基于真实 API)
pub const OrderResponse = struct {
    status: []const u8,  // "ok" or "err"
    response: Response,

    pub const Response = struct {
        type_: []const u8,  // "order"
        data: Data,

        pub const Data = struct {
            statuses: []Status,
        };
    };

    pub const Status = union(enum) {
        resting: RestingOrder,
        filled: FilledOrder,
        error: []const u8,

        pub const RestingOrder = struct {
            oid: u64,
        };

        pub const FilledOrder = struct {
            totalSz: []const u8,
            avgPx: []const u8,
            oid: u64,
        };
    };
};

/// 撤单请求 (基于真实 API)
pub const Cancel = struct {
    a: u32,  // 资产索引
    o: u64,  // 订单 ID
};

pub const CancelRequest = struct {
    coin: []const u8,
    oid: u64,
};

/// 撤单响应 (基于真实 API)
pub const CancelResponse = struct {
    status: []const u8,
    response: ?Response,

    pub const Response = struct {
        type_: []const u8,  // "cancel"
        data: Data,

        pub const Data = struct {
            statuses: [][]const u8,  // "success" 或错误消息
        };
    };
};

/// 获取资产索引 (基于真实 API: 从 meta.universe)
fn getAssetIndex(client: *HyperliquidClient, coin: []const u8) !u32 {
    const meta = try client.getMeta();
    for (meta.universe, 0..) |asset, idx| {
        if (std.mem.eql(u8, asset.name, coin)) {
            return @intCast(idx);
        }
    }
    return error.AssetNotFound;
}
```

#### 5. 速率限制器

```zig
// src/exchange/hyperliquid/rate_limit.zig

const std = @import("std");

pub const RateLimiter = struct {
    last_request_time: i64,
    min_interval_ms: u64,

    pub fn init() RateLimiter {
        return .{
            .last_request_time = 0,
            .min_interval_ms = 50, // Hyperliquid: 20 req/s
        };
    }

    /// 等待直到可以发送下一个请求
    pub fn wait(self: *RateLimiter) void {
        const now = std.time.milliTimestamp();
        const elapsed = now - self.last_request_time;

        if (elapsed < self.min_interval_ms) {
            const sleep_time = self.min_interval_ms - @as(u64, @intCast(elapsed));
            std.time.sleep(sleep_time * std.time.ns_per_ms);
        }

        self.last_request_time = std.time.milliTimestamp();
    }
};
```

---

## 📝 任务分解

### Phase 1: 基础设施 📋
- [ ] 任务 1.1: 搭建项目结构
- [ ] 任务 1.2: 实现 HTTP 客户端基础类
- [ ] 任务 1.3: 实现 Ed25519 签名认证
- [ ] 任务 1.4: 实现速率限制器
- [ ] 任务 1.5: 实现错误处理和重试逻辑

### Phase 2: Info API 📋
- [ ] 任务 2.1: 实现 getAllAssets
- [ ] 任务 2.2: 实现 getOrderBook
- [ ] 任务 2.3: 实现 getAccountState
- [ ] 任务 2.4: 实现 getRecentTrades
- [ ] 任务 2.5: 实现数据解析器

### Phase 3: Exchange API 📋
- [ ] 任务 3.1: 实现 placeOrder
- [ ] 任务 3.2: 实现 cancelOrder
- [ ] 任务 3.3: 实现 cancelOrders (批量)
- [ ] 任务 3.4: 实现 getOrderStatus
- [ ] 任务 3.5: 实现请求序列化

### Phase 4: 测试与文档 📋
- [ ] 任务 4.1: 编写单元测试（模拟 HTTP）
- [ ] 任务 4.2: 编写集成测试（连接测试网）
- [ ] 任务 4.3: 编写使用示例
- [ ] 任务 4.4: 更新 API 文档
- [ ] 任务 4.5: 性能测试和优化
- [ ] 任务 4.6: 代码审查

---

## 🧪 测试策略

### 单元测试

```zig
// src/exchange/hyperliquid/http_test.zig

const std = @import("std");
const testing = std.testing;
const HyperliquidClient = @import("http.zig").HyperliquidClient;
const InfoAPI = @import("info_api.zig");

test "HyperliquidClient: initialization" {
    const config = HyperliquidClient.Config{
        .base_url = "https://api.hyperliquid-testnet.xyz",
        .api_key = null,
        .secret_key = null,
        .testnet = true,
        .timeout_ms = 5000,
        .max_retries = 3,
    };

    var client = try HyperliquidClient.init(testing.allocator, config, logger);
    defer client.deinit();

    try testing.expect(client.config.testnet);
}

test "Auth: Ed25519 signature generation" {
    const secret_key = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
    var auth = try Auth.init(testing.allocator, secret_key);
    defer auth.deinit();

    const signature = try auth.signRequest(
        1640000000000,
        "POST",
        "/exchange/order",
        "{\"coin\":\"ETH\",\"is_buy\":true}",
    );
    defer testing.allocator.free(signature);

    try testing.expect(signature.len == 128); // 64 bytes in hex
}

test "InfoAPI: parse order book" {
    const json_response =
        \\{
        \\  "coin": "ETH",
        \\  "levels": [
        \\    [
        \\      [{"px": "2000.5", "sz": "10.0", "n": 1}],
        \\      [{"px": "2001.0", "sz": "5.0", "n": 1}]
        \\    ]
        \\  ],
        \\  "time": 1640000000000
        \\}
    ;

    const result = try std.json.parseFromSlice(
        std.json.Value,
        testing.allocator,
        json_response,
        .{},
    );
    defer result.deinit();

    const orderbook = try InfoAPI.parseOrderBook(testing.allocator, result.value);
    defer testing.allocator.free(orderbook.bids);
    defer testing.allocator.free(orderbook.asks);

    try testing.expectEqualStrings("ETH", orderbook.symbol);
    try testing.expect(orderbook.bids.len > 0);
}
```

### 集成测试

```zig
test "Integration: connect to testnet" {
    const config = HyperliquidClient.Config{
        .base_url = "https://api.hyperliquid-testnet.xyz",
        .api_key = null,
        .secret_key = null,
        .testnet = true,
        .timeout_ms = 10000,
        .max_retries = 3,
    };

    var client = try HyperliquidClient.init(testing.allocator, config, logger);
    defer client.deinit();

    // 测试获取资产列表
    const assets = try InfoAPI.getAllAssets(&client);
    defer testing.allocator.free(assets);

    try testing.expect(assets.len > 0);
    std.debug.print("\nFound {} assets\n", .{assets.len});
}

test "Integration: get order book" {
    var client = try createTestClient();
    defer client.deinit();

    const orderbook = try InfoAPI.getOrderBook(&client, "ETH");
    defer testing.allocator.free(orderbook.bids);
    defer testing.allocator.free(orderbook.asks);

    try testing.expect(orderbook.bids.len > 0);
    try testing.expect(orderbook.asks.len > 0);

    std.debug.print("\nOrder Book for ETH:\n", .{});
    std.debug.print("  Best Bid: {} @ {}\n", .{
        orderbook.bids[0].size.toFloat(),
        orderbook.bids[0].price.toFloat(),
    });
    std.debug.print("  Best Ask: {} @ {}\n", .{
        orderbook.asks[0].size.toFloat(),
        orderbook.asks[0].price.toFloat(),
    });
}
```

### 手动测试场景

```bash
# 场景 1: 获取市场数据
$ zig test src/exchange/hyperliquid/http_test.zig --test-filter "get order book"

# 场景 2: 测试认证签名
$ zig test src/exchange/hyperliquid/auth_test.zig

# 场景 3: 下单测试（需要测试网 API Key）
$ export HYPERLIQUID_SECRET_KEY="your_testnet_key"
$ zig test src/exchange/hyperliquid/exchange_api_test.zig --test-filter "place order"
```

---

## 📚 相关文档

### 设计文档
- [ ] `docs/features/hyperliquid-connector/README.md` - 功能概览
- [ ] `docs/features/hyperliquid-connector/api-reference.md` - API 文档
- [ ] `docs/features/hyperliquid-connector/authentication.md` - 认证机制
- [ ] `docs/features/hyperliquid-connector/testing.md` - 测试指南

### 参考资料
- [Hyperliquid API Documentation](https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api)
- [Hyperliquid Python SDK](https://github.com/hyperliquid-dex/hyperliquid-python-sdk)
- [Ed25519 Signatures in Zig](https://ziglang.org/documentation/master/std/#std.crypto.sign.Ed25519)
- [ADR-002: 选择 Hyperliquid 作为首个支持的交易所](../../docs/decisions/002-hyperliquid-first-exchange.md)

---

## 🔗 依赖关系

### 前置条件
- [x] Story 001: Decimal 类型（价格、数量计算）
- [x] Story 002: Time Utils（时间戳处理）
- [x] Story 003: Error System（错误处理）
- [x] Story 004: Logger（日志记录）
- [x] Story 005: Config（配置管理）

### 被依赖
- Story 007: Hyperliquid WebSocket 客户端
- Story 008: 订单簿维护
- Story 009: 订单管理器
- Story 010: 仓位追踪器

---

## ⚠️ 风险与挑战

### 已识别风险
1. **API 变更风险**: Hyperliquid API 可能更新
   - **影响**: 中
   - **缓解措施**: 使用版本化 API，监控官方更新

2. **网络稳定性**: 网络波动可能导致请求失败
   - **影响**: 高
   - **缓解措施**: 实现完善的重试机制，指数退避策略

3. **签名错误**: Ed25519 签名实现错误会导致认证失败
   - **影响**: 高
   - **缓解措施**: 充分测试签名逻辑，参考官方 SDK

4. **速率限制**: 超过速率限制会被临时封禁
   - **影响**: 中
   - **缓解措施**: 实现客户端速率限制器

### 技术挑战
1. **JSON 序列化**: Zig 的 JSON 库相对底层
   - **解决方案**: 封装便捷的序列化/反序列化工具函数

2. **异步 HTTP**: Zig 的 HTTP 客户端是同步的
   - **解决方案**: MVP 阶段使用同步调用，后续优化为异步

3. **错误处理**: 需要区分网络错误、API 错误、业务错误
   - **解决方案**: 使用 Story 003 的错误系统，分类错误

---

## 📊 进度追踪

### 时间线
- 开始日期: 待定
- 预计完成: 待定
- 实际完成: 待定

### 工作日志
| 日期 | 进展 | 备注 |
|------|------|------|
| - | - | - |

---

## ✅ 验收检查清单

- [ ] 所有验收标准已满足
- [ ] 所有任务已完成
- [ ] 单元测试通过
- [ ] 集成测试通过（连接测试网）
- [ ] 代码已审查
- [ ] 文档已更新
- [ ] 无编译警告
- [ ] 签名生成正确（与官方 SDK 验证）
- [ ] 速率限制正常工作

---

## 📸 演示

### 使用示例

```zig
const std = @import("std");
const HyperliquidClient = @import("exchange/hyperliquid/http.zig").HyperliquidClient;
const InfoAPI = @import("exchange/hyperliquid/info_api.zig");
const ExchangeAPI = @import("exchange/hyperliquid/exchange_api.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 初始化客户端（测试网）
    const config = HyperliquidClient.Config{
        .base_url = HyperliquidClient.Config.DEFAULT_TESTNET_URL,
        .api_key = null,
        .secret_key = std.os.getenv("HYPERLIQUID_SECRET_KEY"),
        .testnet = true,
        .timeout_ms = 10000,
        .max_retries = 3,
    };

    var client = try HyperliquidClient.init(allocator, config, logger);
    defer client.deinit();

    // 1. 获取订单簿
    std.debug.print("=== Fetching ETH Order Book ===\n", .{});
    const orderbook = try InfoAPI.getOrderBook(&client, "ETH");
    defer allocator.free(orderbook.bids);
    defer allocator.free(orderbook.asks);

    std.debug.print("Best Bid: {} @ {}\n", .{
        orderbook.bids[0].size.toFloat(),
        orderbook.bids[0].price.toFloat(),
    });
    std.debug.print("Best Ask: {} @ {}\n", .{
        orderbook.asks[0].size.toFloat(),
        orderbook.asks[0].price.toFloat(),
    });

    // 2. 获取账户状态
    if (config.secret_key) |_| {
        std.debug.print("\n=== Fetching Account State ===\n", .{});
        const pub_key = try client.auth.getPublicKey();
        defer allocator.free(pub_key);

        const account = try InfoAPI.getAccountState(&client, pub_key);
        std.debug.print("Account Value: ${}\n", .{
            account.margin_summary.account_value.toFloat(),
        });
        std.debug.print("Margin Used: ${}\n", .{
            account.margin_summary.total_margin_used.toFloat(),
        });

        // 3. 下限价单（示例）
        std.debug.print("\n=== Placing Limit Order ===\n", .{});
        const order = ExchangeAPI.OrderRequest{
            .coin = "ETH",
            .is_buy = true,
            .sz = try Decimal.fromString("0.01"),
            .limit_px = try Decimal.fromString("2000.0"),
            .order_type = .{
                .limit = .{
                    .tif = "Gtc", // Good-til-cancelled
                },
            },
            .reduce_only = false,
        };

        const response = try ExchangeAPI.placeOrder(&client, order);
        if (std.mem.eql(u8, response.status, "ok")) {
            std.debug.print("Order placed successfully!\n", .{});
        } else {
            std.debug.print("Order failed: {s}\n", .{response.response.error});
        }
    }
}
```

### 输出示例
```
=== Fetching ETH Order Book ===
Best Bid: 10.5 @ 2145.23
Best Ask: 8.2 @ 2145.67

=== Fetching Account State ===
Account Value: $10000.50
Margin Used: $1250.00

=== Placing Limit Order ===
Order placed successfully!
```

---

## 💡 未来改进

完成此 Story 后可以考虑的优化方向:

- [ ] 支持异步 HTTP 请求（减少延迟）
- [ ] 实现连接池复用
- [ ] 支持批量请求（batch API）
- [ ] 添加请求缓存机制
- [ ] 实现更智能的速率限制（令牌桶算法）
- [ ] 支持 HTTP/2
- [ ] 添加请求/响应拦截器
- [ ] 实现请求去重

---

## 📝 备注

### Hyperliquid API 特点
1. **无需 API Key 读取公开数据**: Info API 不需要认证
2. **Ed25519 签名**: Exchange API 需要 Ed25519 签名
3. **高速率限制**: 20 req/s（远高于大多数 CEX）
4. **测试网支持**: 提供完整的测试环境

### 开发建议
1. 先实现 Info API（无需认证，容易测试）
2. 再实现 Ed25519 签名逻辑（单独测试）
3. 最后实现 Exchange API（需要测试网 API Key）
4. 使用测试网充分测试后再连接主网

---

*Last updated: 2025-12-23*
*Assignee: TBD*
*Status: 📋 Planning*
