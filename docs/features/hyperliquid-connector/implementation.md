# Hyperliquid 连接器 - 实现细节

> 深入了解 HTTP 客户端、WebSocket 客户端、Ed25519 签名等内部实现

**最后更新**: 2025-12-23

---

## 架构概览

```
src/exchange/hyperliquid/
├── http.zig              # HTTP 客户端核心
├── auth.zig              # Ed25519 签名认证
├── info_api.zig          # Info API 端点
├── exchange_api.zig      # Exchange API 端点
├── types.zig             # 数据类型定义
├── rate_limit.zig        # 速率限制器
├── websocket.zig         # WebSocket 客户端核心
├── ws_types.zig          # WebSocket 消息类型
├── subscription.zig      # 订阅管理器
├── message_handler.zig   # 消息处理器
└── http_test.zig         # 测试
```

---

## HTTP 客户端实现

### 数据结构

```zig
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
};
```

### 请求处理流程

1. **速率限制检查**: 使用 `RateLimiter` 确保不超过 20 req/s
2. **构造请求**: 根据端点构造 HTTP 请求（GET/POST）
3. **签名（Exchange API）**: 使用 Ed25519 签名请求体
4. **发送请求**: 使用 `std.http.Client` 发送
5. **解析响应**: JSON 反序列化
6. **错误处理**: 分类错误并决定是否重试

### 重试机制

```zig
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

            // 指数退避
            const sleep_time = std.time.ns_per_s * @as(u64, @intCast(retries + 1));
            std.time.sleep(sleep_time);
            continue;
        };
        return result;
    }
    unreachable;
}
```

**复杂度**: O(n)，其中 n = max_retries
**说明**: 使用指数退避策略，每次重试等待时间递增

---

## Ed25519 认证实现

### 签名流程

```zig
pub fn signL1Action(
    self: *Auth,
    action: []const u8,  // action 的 JSON/msgpack
    nonce: i64,
) !Signature {
    if (self.keypair == null) {
        return error.NoSecretKey;
    }

    // 1. 构造签名消息: action + nonce
    var msg_buffer: [4096]u8 = undefined;
    const msg = try std.fmt.bufPrint(&msg_buffer, "{s}{d}", .{
        action, nonce,
    });

    // 2. Ed25519 签名
    const signature = try self.keypair.?.sign(msg, null);

    // 3. 转换为 (r, s, v) 格式
    return Signature{
        .r = signature.toBytes()[0..32].*,
        .s = signature.toBytes()[32..64].*,
        .v = 27,  // 恢复 ID
    };
}
```

### Nonce 生成策略

```zig
pub fn generateNonce() i64 {
    const now = std.time.milliTimestamp();

    // 确保同一毫秒内的多个请求有唯一 nonce
    const static = struct {
        var last_nonce: i64 = 0;
    };

    if (now <= static.last_nonce) {
        static.last_nonce += 1;
        return static.last_nonce;
    }

    static.last_nonce = now;
    return now;
}
```

**复杂度**: O(1)
**说明**: 使用毫秒时间戳确保 nonce 递增，同时处理同一毫秒内的多个请求

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

### 速率限制器

```zig
pub const RateLimiter = struct {
    last_request_time: i64,
    min_interval_ms: u64,

    pub fn init() RateLimiter {
        return .{
            .last_request_time = 0,
            .min_interval_ms = 50, // Hyperliquid: 20 req/s
        };
    }

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

**复杂度**: O(1)
**说明**: 使用简单的固定间隔策略，确保最小请求间隔 50ms（20 req/s）

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

*Last updated: 2025-12-23*
