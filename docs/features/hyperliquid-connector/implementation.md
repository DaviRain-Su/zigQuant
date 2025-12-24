# Hyperliquid 连接器 - 实现细节

> 深入了解 HTTP 客户端、WebSocket 客户端、EIP-712 签名等内部实现

**最后更新**: 2025-12-24

---

## 架构概览

```
src/exchange/hyperliquid/
├── connector.zig         # IExchange 接口实现
├── http.zig              # HTTP 客户端核心
├── info_api.zig          # Info API 端点封装
├── exchange_api.zig      # Exchange API 端点封装
├── auth.zig              # EIP-712 签名认证（基于 zigeth）
├── types.zig             # Hyperliquid 数据类型定义
├── rate_limiter.zig      # 令牌桶速率限制器
├── websocket.zig         # WebSocket 客户端核心
├── ws_types.zig          # WebSocket 消息类型
├── subscription.zig      # 订阅管理器（线程安全）
└── message_handler.zig   # 消息解析器
```

---

## Connector 实现 (IExchange 接口)

### 数据结构

```zig
pub const HyperliquidConnector = struct {
    allocator: std.mem.Allocator,
    config: ExchangeConfig,
    logger: Logger,
    connected: bool,

    // Phase D: HTTP 客户端和 API 模块
    http_client: HttpClient,
    rate_limiter: RateLimiter,
    info_api: InfoAPI,
    exchange_api: ExchangeAPI,
    signer: ?Signer,  // 可选：仅交易时需要

    pub fn create(
        allocator: std.mem.Allocator,
        config: ExchangeConfig,
        logger: Logger,
    ) !*HyperliquidConnector {
        const self = try allocator.create(HyperliquidConnector);
        errdefer allocator.destroy(self);

        // 初始化结构体字段（http_client 优先，然后 API 获取其指针）
        self.* = .{
            .allocator = allocator,
            .config = config,
            .logger = logger,
            .connected = false,
            .http_client = HttpClient.init(allocator, config.testnet, logger),
            .rate_limiter = @import("rate_limiter.zig").createHyperliquidRateLimiter(),
            .info_api = undefined,
            .exchange_api = undefined,
            .signer = null,
        };

        // 使用稳定指针初始化 API
        self.info_api = InfoAPI.init(allocator, &self.http_client, logger);
        self.exchange_api = ExchangeAPI.init(allocator, &self.http_client, null, logger);

        return self;
    }

    pub fn destroy(self: *HyperliquidConnector) void {
        if (self.connected) {
            disconnect(self);
        }
        self.http_client.deinit();
        self.allocator.destroy(self);
    }
};
```

## HTTP 客户端实现

### 数据结构

```zig
pub const HttpClient = struct {
    allocator: std.mem.Allocator,
    base_url: []const u8,
    http_client: std.http.Client,
    logger: Logger,

    pub fn init(
        allocator: std.mem.Allocator,
        testnet: bool,
        logger: Logger,
    ) HttpClient {
        const base_url = if (testnet)
            types.API_BASE_URL_TESTNET
        else
            types.API_BASE_URL_MAINNET;

        return .{
            .allocator = allocator,
            .base_url = base_url,
            .http_client = std.http.Client{ .allocator = allocator },
            .logger = logger,
        };
    }

    pub fn deinit(self: *HttpClient) void {
        self.http_client.deinit();
    }
};
```

### 请求处理流程

1. **速率限制检查**: 在 Connector 层使用 `RateLimiter.wait()` 确保不超过 20 req/s
2. **构造请求**: Info API 和 Exchange API 模块构造 JSON 请求体
3. **签名（Exchange API）**: Exchange API 使用 `Signer` 进行 EIP-712 签名
4. **发送请求**: `HttpClient.post()` 使用 `std.http.Client.fetch()` 发送
5. **解析响应**: Info API 和 Exchange API 解析 JSON
6. **错误处理**: 网络错误返回 `NetworkError`

### POST 请求实现

```zig
pub fn post(
    self: *HttpClient,
    endpoint: []const u8,
    request_body: []const u8,
) ![]const u8 {
    // 创建 arena allocator 用于临时数据
    var arena = std.heap.ArenaAllocator.init(self.allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    // 构建完整 URL
    const url = try std.fmt.allocPrint(
        arena_alloc,
        "{s}{s}",
        .{ self.base_url, endpoint },
    );

    self.logger.debug("POST {s}", .{url}) catch {};

    // 准备头部
    var header_list = try std.ArrayList(std.http.Header).initCapacity(arena_alloc, 2);
    try header_list.append(arena_alloc, .{ .name = "Content-Type", .value = "application/json" });

    // 创建响应写入器
    var body_writer = std.io.Writer.Allocating.init(arena_alloc);
    defer body_writer.deinit();

    // 发送 HTTP 请求
    const result = self.http_client.fetch(.{
        .location = .{ .url = url },
        .method = .POST,
        .payload = request_body,
        .extra_headers = header_list.items,
        .response_writer = &body_writer.writer,
        .keep_alive = true,
    }) catch return NetworkError.ConnectionFailed;

    // 检查状态码
    const status = @intFromEnum(result.status);
    if (status < 200 or status >= 300) {
        self.logger.err("HTTP error: {d}", .{status}) catch {};
        return NetworkError.HttpError;
    }

    // 复制响应到持久内存
    const written = body_writer.written();
    const response_body = try self.allocator.alloc(u8, written.len);
    @memcpy(response_body, written);

    return response_body;
}
```

**复杂度**: O(n)，其中 n = 响应大小
**说明**: 使用 arena allocator 管理临时分配，返回的响应需要调用者释放

---

## EIP-712 认证实现

Hyperliquid 使用 **EIP-712** 签名（而非 Ed25519），基于以太坊的 secp256k1 曲线。

### 签名流程

```zig
pub const Signer = struct {
    allocator: Allocator,
    wallet: zigeth.signer.Wallet,  // Ethereum 钱包 (secp256k1)
    address: []const u8,            // 缓存的以太坊地址 (0x...)

    pub fn init(
        allocator: Allocator,
        private_key: [32]u8,
    ) !Signer {
        // 转换私钥为十六进制字符串
        const pk_hex = try std.fmt.allocPrint(allocator, "0x{s}", .{
            std.fmt.bytesToHex(&private_key, .lower),
        });
        defer allocator.free(pk_hex);

        // 从私钥创建钱包
        var wallet = try zigeth.signer.Wallet.fromPrivateKeyHex(allocator, pk_hex);

        // 获取以太坊地址
        const addr = try wallet.getAddress();
        const address = try addr.toHex(allocator);

        return .{
            .allocator = allocator,
            .wallet = wallet,
            .address = address,
        };
    }

    pub fn signAction(
        self: *Signer,
        action_data: []const u8,
    ) !Signature {
        // 1. Hash the action data (message hash)
        const message_hash = keccak256(action_data);

        // 2. 计算 domain separator hash
        const domain_hash = try encodeDomainSeparator(
            self.allocator,
            HYPERLIQUID_EXCHANGE_DOMAIN,
        );

        // 3. 使用 EIP-712 签名（zigeth 处理最终编码和签名）
        const sig = try self.wallet.signTypedData(domain_hash, message_hash);

        // 4. 转换签名组件为十六进制字符串（带 0x 前缀）
        const r_hex = try std.fmt.allocPrint(self.allocator, "0x{s}", .{
            std.fmt.bytesToHex(&sig.r, .lower),
        });
        const s_hex = try std.fmt.allocPrint(self.allocator, "0x{s}", .{
            std.fmt.bytesToHex(&sig.s, .lower),
        });

        return Signature{
            .r = r_hex,
            .s = s_hex,
            .v = @truncate(sig.v),  // 转换 u64 为 u8
        };
    }
};
```

### EIP-712 Domain Separator

```zig
pub const HYPERLIQUID_EXCHANGE_DOMAIN = EIP712Domain{
    .name = "Exchange",
    .version = "1",
    .chainId = 1337,
    .verifyingContract = "0x0000000000000000000000000000000000000000",
};

fn encodeDomainSeparator(allocator: Allocator, domain: EIP712Domain) ![32]u8 {
    // EIP712Domain type hash
    const type_string = "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)";
    const type_hash = keccak256(type_string);

    // 编码 domain 字段
    const name_hash = keccak256(domain.name);
    const version_hash = keccak256(domain.version);

    // ... (拼接并 hash)
    return keccak256(data);
}
```

**复杂度**: O(1)
**说明**: 使用 Keccak256 hash 和 secp256k1 签名，符合 Ethereum EIP-712 标准

---

## WebSocket 客户端实现

### 连接管理

```zig
pub const HyperliquidWS = struct {
    allocator: std.mem.Allocator,
    config: HyperliquidWSConfig,
    client: ws.Client,
    subscription_manager: SubscriptionManager,
    message_handler: MessageHandler,
    logger: Logger,

    // 连接状态（原子操作）
    connected: std.atomic.Value(bool),
    reconnecting: std.atomic.Value(bool),

    pub fn connect(self: *HyperliquidWS) !void {
        self.logger.info("Connecting to WebSocket: {s}", .{self.config.ws_url});

        self.client = try ws.Client.init(self.allocator, .{
            .url = self.config.ws_url,
        });

        try self.client.connect();
        self.connected.store(true, .release);

        self.logger.info("WebSocket connected successfully", .{});

        // 启动消息接收循环（单独线程）
        try self.startReceiveLoop();

        // 启动心跳（单独线程）
        try self.startPingLoop();
    }
};
```

### 消息接收循环

```zig
fn startReceiveLoop(self: *HyperliquidWS) !void {
    const thread = try std.Thread.spawn(.{}, receiveLoop, .{self});
    thread.detach();
}

fn receiveLoop(self: *HyperliquidWS) void {
    while (self.connected.load(.acquire)) {
        const msg = self.client.receive() catch |err| {
            self.logger.err("Failed to receive message: {}", .{err});
            self.handleConnectionError(err);
            continue;
        };
        defer self.allocator.free(msg);

        // 解析消息
        const parsed = self.message_handler.parse(msg) catch |err| {
            self.logger.warn("Failed to parse message: {}", .{err});
            continue;
        };

        // 分发消息
        if (self.on_message) |callback| {
            callback(parsed);
        }
    }
}
```

**复杂度**: O(∞)（持续运行）
**说明**: 独立线程持续接收消息，解析并分发

### 断线重连机制

```zig
fn handleConnectionError(self: *HyperliquidWS, err: anytype) void {
    _ = err;

    if (self.reconnecting.load(.acquire)) return;

    self.reconnecting.store(true, .release);
    defer self.reconnecting.store(false, .release);

    self.logger.warn("Connection lost, attempting to reconnect...", .{});

    var attempts: u32 = 0;
    while (attempts < self.config.max_reconnect_attempts) : (attempts += 1) {
        std.time.sleep(self.config.reconnect_interval_ms * std.time.ns_per_ms);

        self.connect() catch |reconnect_err| {
            self.logger.warn("Reconnect attempt {} failed: {}", .{
                attempts + 1, reconnect_err,
            });
            continue;
        };

        // 重新订阅所有频道
        self.resubscribeAll() catch |sub_err| {
            self.logger.err("Failed to resubscribe: {}", .{sub_err});
            continue;
        };

        self.logger.info("Reconnected successfully", .{});
        return;
    }

    self.logger.err("Max reconnect attempts reached, giving up", .{});
}
```

**复杂度**: O(n)，其中 n = max_reconnect_attempts
**说明**: 使用固定间隔重连策略，重连成功后自动恢复所有订阅

---

## 订阅管理实现

### 订阅管理器

```zig
pub const SubscriptionManager = struct {
    allocator: std.mem.Allocator,
    subscriptions: std.ArrayList(Subscription),
    mutex: std.Thread.Mutex,  // 线程安全

    pub fn init(allocator: std.mem.Allocator) SubscriptionManager {
        return .{
            .allocator = allocator,
            .subscriptions = std.ArrayList(Subscription).init(allocator),
            .mutex = std.Thread.Mutex{},
        };
    }

    pub fn add(self: *SubscriptionManager, sub: Subscription) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        try self.subscriptions.append(sub);
    }

    pub fn remove(self: *SubscriptionManager, sub: Subscription) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        for (self.subscriptions.items, 0..) |s, i| {
            if (std.mem.eql(u8, @tagName(s.channel), @tagName(sub.channel))) {
                _ = self.subscriptions.swapRemove(i);
                return;
            }
        }
    }
};
```

**复杂度**:
- `add`: O(1) 平均
- `remove`: O(n)，其中 n = 订阅数量
**说明**: 使用互斥锁保证线程安全，支持并发访问

### 订阅 JSON 生成

```zig
pub fn toJSON(self: Subscription, allocator: std.mem.Allocator) ![]u8 {
    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();

    const writer = buffer.writer();

    try writer.writeAll("{\"method\":\"subscribe\",\"subscription\":{");

    // type 字段
    try writer.print("\"type\":\"{s}\"", .{@tagName(self.channel)});

    // 添加额外参数
    if (self.coin) |coin| {
        try writer.print(",\"coin\":\"{s}\"", .{coin});
    }
    if (self.user) |user| {
        try writer.print(",\"user\":\"{s}\"", .{user});
    }
    // ... 其他参数

    try writer.writeAll("}}");

    return buffer.toOwnedSlice();
}
```

**复杂度**: O(m)，其中 m = JSON 字符串长度
**说明**: 动态构造 JSON 字符串，避免使用完整的 JSON 序列化库

---

## 消息处理实现

### 消息解析器

```zig
pub const MessageHandler = struct {
    allocator: std.mem.Allocator,

    pub fn parse(self: *MessageHandler, raw: []const u8) !Message {
        const parsed = try std.json.parseFromSlice(
            std.json.Value,
            self.allocator,
            raw,
            .{},
        );
        defer parsed.deinit();

        const root = parsed.value.object;
        const channel = root.get("channel").?.string;

        // 根据 channel 分发到对应的解析器
        if (std.mem.eql(u8, channel, "l2Book")) {
            return Message{ .l2_book = try parseL2Book(self.allocator, root) };
        } else if (std.mem.eql(u8, channel, "trades")) {
            return Message{ .trades = try parseTrades(self.allocator, root) };
        }
        // ... 其他类型

        return Message{ .unknown = raw };
    }
};
```

**复杂度**: O(n)，其中 n = JSON 大小
**说明**: 使用 channel 字段分发，避免全类型遍历

---

## 速率限制实现

### 令牌桶算法

```zig
pub const RateLimiter = struct {
    tokens: f64,
    max_tokens: f64,
    refill_rate: f64,  // tokens per second
    last_refill: i128,  // timestamp in nanoseconds
    mutex: std.Thread.Mutex,

    pub fn init(rate: f64, burst: f64) RateLimiter {
        const max_tokens = if (burst > 0) burst else rate;
        return .{
            .tokens = max_tokens,
            .max_tokens = max_tokens,
            .refill_rate = rate,
            .last_refill = std.time.nanoTimestamp(),
            .mutex = std.Thread.Mutex{},
        };
    }

    pub fn wait(self: *RateLimiter) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        while (true) {
            self.refill();

            if (self.tokens >= 1.0) {
                self.tokens -= 1.0;
                return;
            }

            // 计算等待时间
            const tokens_needed = 1.0 - self.tokens;
            const wait_seconds = tokens_needed / self.refill_rate;
            const wait_ns = @as(u64, @intFromFloat(wait_seconds * std.time.ns_per_s));

            // 释放锁期间睡眠
            self.mutex.unlock();
            std.Thread.sleep(wait_ns);
            self.mutex.lock();
        }
    }

    fn refill(self: *RateLimiter) void {
        const now = std.time.nanoTimestamp();
        const elapsed_ns = now - self.last_refill;
        const elapsed_seconds = @as(f64, @floatFromInt(elapsed_ns)) / std.time.ns_per_s;

        const tokens_to_add = elapsed_seconds * self.refill_rate;
        self.tokens = @min(self.tokens + tokens_to_add, self.max_tokens);
        self.last_refill = now;
    }
};

/// Hyperliquid 专用速率限制器（20 req/s）
pub fn createHyperliquidRateLimiter() RateLimiter {
    return RateLimiter.init(20.0, 20.0);
}
```

**复杂度**: O(1)
**说明**:
- 使用令牌桶算法，支持突发流量
- 线程安全（使用互斥锁）
- 自动按时间补充令牌

---

## 内存管理

### HTTP 客户端

- **分配**: `http_client` 由 `std.http.Client` 管理
- **释放**: `deinit()` 中调用 `http_client.deinit()`

### WebSocket 客户端

- **分配**:
  - 订阅列表：`std.ArrayList(Subscription)`
  - 消息缓冲：每次接收时分配
- **释放**:
  - `deinit()` 中释放所有订阅
  - 消息处理后使用 `defer allocator.free(msg)` 释放

### 签名数据

- **分配**: 签名缓冲区使用栈分配（`[4096]u8`）
- **释放**: 自动回收（栈释放）

---

## 性能优化

### 1. 减少内存分配

```zig
// 使用栈缓冲区避免堆分配
var msg_buffer: [4096]u8 = undefined;
const msg = try std.fmt.bufPrint(&msg_buffer, "{s}{d}", .{action, nonce});
```

### 2. 避免重复序列化

```zig
// 缓存订阅 JSON
const json = try subscription.toJSON(allocator);
defer allocator.free(json);
try client.send(json);
```

### 3. 并发处理

```zig
// WebSocket 接收和心跳使用独立线程
try std.Thread.spawn(.{}, receiveLoop, .{self});
try std.Thread.spawn(.{}, pingLoop, .{self});
```

---

## 边界情况处理

### 1. 网络断开

- **检测**: `client.receive()` 返回错误
- **处理**: 调用 `handleConnectionError`，自动重连
- **恢复**: 重新订阅所有频道

### 2. Nonce 冲突

- **检测**: Exchange API 返回 "Nonce error"
- **处理**: 使用静态变量递增 nonce
- **避免**: 确保单调递增

### 3. 消息解析失败

- **检测**: JSON 解析返回错误
- **处理**: 记录警告，跳过该消息
- **继续**: 不影响后续消息接收

### 4. 订阅限制

- **限制**: 每 IP 最多 1000 订阅
- **检测**: 订阅确认返回错误
- **建议**: 使用 `allMids` 替代逐个订阅

---

## 线程安全

### 原子操作

```zig
// WebSocket 连接状态使用原子操作
connected: std.atomic.Value(bool),
reconnecting: std.atomic.Value(bool),

// 读取
if (self.connected.load(.acquire)) { ... }

// 写入
self.connected.store(true, .release);
```

### 互斥锁

```zig
// 订阅管理器使用互斥锁
pub fn add(self: *SubscriptionManager, sub: Subscription) !void {
    self.mutex.lock();
    defer self.mutex.unlock();
    try self.subscriptions.append(sub);
}
```

---

## 参考实现

- **完整 HTTP 实现**: `src/exchange/hyperliquid/http.zig`
- **完整 WebSocket 实现**: `src/exchange/hyperliquid/websocket.zig`
- **完整签名实现**: `src/exchange/hyperliquid/auth.zig`

---

## 集成示例

### 完整的市场数据获取流程

```zig
// 1. 创建连接器
const connector = try HyperliquidConnector.create(allocator, config, logger);
defer connector.destroy();

// 2. 获取 IExchange 接口
const exchange = connector.interface();

// 3. 连接
try exchange.connect();

// 4. 速率限制自动应用
connector.rate_limiter.wait();  // 自动在内部调用

// 5. 获取 ticker（通过 IExchange）
const pair = TradingPair{ .base = "ETH", .quote = "USDC" };
const ticker = try exchange.getTicker(pair);

// 内部流程：
// - getTicker() 调用 symbol_mapper.toHyperliquid() 转换符号
// - 调用 rate_limiter.wait() 限速
// - 调用 info_api.getAllMids()
// - getAllMids() 调用 http_client.postInfo()
// - http_client 使用 arena allocator 处理临时分配
// - 解析 JSON 并返回结果
```

---

*Last updated: 2025-12-24*
