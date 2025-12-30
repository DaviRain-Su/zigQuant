# Hyperliquid 连接器 - 实现细节

> 深入了解 HTTP 客户端、WebSocket 客户端、EIP-712 签名等内部实现

**最后更新**: 2025-12-30

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
    signer: ?Signer,  // 可选：仅交易时需要（懒加载）

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
            .signer = null,  // 懒加载：首次使用时初始化
        };

        // 注意：Signer 延迟到首次使用时初始化（懒加载）
        // 这避免了启动时阻塞在熵/加密初始化上
        // Signer 将在需要交易操作时按需初始化

        // 使用稳定指针初始化 API
        self.info_api = InfoAPI.init(allocator, &self.http_client, logger);
        self.exchange_api = ExchangeAPI.init(allocator, &self.http_client, null, logger);

        return self;
    }

    pub fn destroy(self: *HyperliquidConnector) void {
        if (self.connected) {
            disconnect(self);
        }
        // 清理 signer（如果已初始化）
        if (self.signer) |*signer| {
            signer.deinit();
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

## Signer 懒加载机制

为了优化启动性能和资源使用，Signer（签名器）采用懒加载策略。

### 设计理念

```zig
/// Ensure signer is initialized (lazy initialization)
/// Only initializes if not already initialized and credentials are available
fn ensureSigner(self: *HyperliquidConnector) !void {
    // 已经初始化，直接返回
    if (self.signer != null) return;

    // 未提供凭证
    if (self.config.api_secret.len == 0) {
        return error.NoCredentials;
    }

    // 现在才初始化 signer
    self.logger.info("Lazy-initializing signer for trading operations...", .{}) catch {};
    self.signer = try self.initializeSigner(self.config.api_secret);

    // 更新 ExchangeAPI 的 signer 引用
    const signer_ptr = if (self.signer) |*s| s else null;
    self.exchange_api.signer = signer_ptr;
}
```

### 优势

1. **避免阻塞启动**: 不在 `create()` 时初始化加密库，避免阻塞
2. **按需初始化**: 仅在需要交易操作时才初始化 signer
3. **支持只读模式**: 无需私钥也可以查询市场数据
4. **延迟熵消耗**: 推迟随机数生成器的初始化

### 使用场景

所有需要签名的方法都会自动调用 `ensureSigner()`:
- `getBalance()` - 需要用户地址查询账户状态
- `getPositions()` - 需要用户地址查询持仓
- `getOpenOrders()` - 需要用户地址查询挂单
- `createOrder()` - 需要签名提交订单
- `cancelOrder()` - 需要签名取消订单
- `cancelAllOrders()` - 需要签名批量取消

### 错误处理

```zig
// 如果未提供私钥，返回明确错误
const result = exchange.getBalance() catch |err| {
    if (err == error.NoCredentials) {
        std.debug.print("Trading requires api_secret in config\n", .{});
    }
    return err;
};
```

---

## MessagePack 编码器实现

Hyperliquid 要求所有签名操作使用 **MessagePack 编码**而非 JSON，确保签名数据的字节级一致性。

### 背景

**为什么使用 MessagePack？**
- **确定性编码**: JSON 字段顺序不确定，MessagePack 保证字段顺序
- **紧凑性**: 二进制格式比 JSON 更小
- **签名一致性**: Hyperliquid 服务器和客户端必须对相同数据生成相同的字节序列

**关键要求**:
- 固定字段顺序（`{"type": ..., "orders": [...], "grouping": ...}`）
- 固定订单字段顺序（`{a, b, p, s, r, t}`）
- 精确的 MessagePack 格式（fixmap, fixstr, fixint 等）

### 编码器实现

```zig
pub const Encoder = struct {
    allocator: Allocator,
    buffer: std.ArrayList(u8),

    pub fn init(allocator: Allocator) Encoder {
        return .{
            .allocator = allocator,
            .buffer = std.ArrayList(u8){},
        };
    }

    pub fn deinit(self: *Encoder) void {
        self.buffer.deinit(self.allocator);
    }

    pub fn toOwnedSlice(self: *Encoder) ![]u8 {
        return self.buffer.toOwnedSlice(self.allocator);
    }
};
```

### 核心编码方法

#### 1. Map 编码

```zig
pub fn writeMapHeader(self: *Encoder, size: u32) !void {
    if (size <= 15) {
        // fixmap: 1000xxxx (0x80 - 0x8f)
        try self.buffer.append(self.allocator, @as(u8, 0x80) | @as(u8, @intCast(size)));
    } else if (size <= 0xffff) {
        // map16
        try self.buffer.append(self.allocator, 0xde);
        try self.buffer.append(self.allocator, @as(u8, @intCast(size >> 8)));
        try self.buffer.append(self.allocator, @as(u8, @intCast(size & 0xff)));
    } else {
        return error.MapTooLarge;
    }
}
```

#### 2. String 编码

```zig
pub fn writeString(self: *Encoder, str: []const u8) !void {
    const len = str.len;
    if (len <= 31) {
        // fixstr: 101xxxxx (0xa0 - 0xbf)
        try self.buffer.append(self.allocator, @as(u8, 0xa0) | @as(u8, @intCast(len)));
    } else if (len <= 0xff) {
        // str8
        try self.buffer.append(self.allocator, 0xd9);
        try self.buffer.append(self.allocator, @as(u8, @intCast(len)));
    } else if (len <= 0xffff) {
        // str16
        try self.buffer.append(self.allocator, 0xda);
        try self.buffer.append(self.allocator, @as(u8, @intCast(len >> 8)));
        try self.buffer.append(self.allocator, @as(u8, @intCast(len & 0xff)));
    } else {
        return error.StringTooLong;
    }
    try self.buffer.appendSlice(self.allocator, str);
}
```

#### 3. Uint 编码

```zig
pub fn writeUint(self: *Encoder, value: u64) !void {
    if (value <= 127) {
        // positive fixint: 0xxxxxxx (0x00 - 0x7f)
        try self.buffer.append(self.allocator, @as(u8, @intCast(value)));
    } else if (value <= 0xff) {
        // uint8
        try self.buffer.append(self.allocator, 0xcc);
        try self.buffer.append(self.allocator, @as(u8, @intCast(value)));
    } else if (value <= 0xffff) {
        // uint16
        try self.buffer.append(self.allocator, 0xcd);
        try self.buffer.append(self.allocator, @as(u8, @intCast(value >> 8)));
        try self.buffer.append(self.allocator, @as(u8, @intCast(value & 0xff)));
    } else {
        // uint32/uint64 (略)
    }
}
```

### 订单 Action 编码

#### placeOrder 编码

```zig
pub fn packOrderAction(
    allocator: Allocator,
    orders: []const OrderRequest,
    grouping: []const u8,
) ![]u8 {
    var encoder = Encoder.init(allocator);
    errdefer encoder.deinit();

    // 根 map (3 个 key)
    try encoder.writeMapHeader(3);

    // Key 1: "type"
    try encoder.writeString("type");
    try encoder.writeString("order");

    // Key 2: "orders" (数组)
    try encoder.writeString("orders");
    try encoder.writeArrayHeader(@intCast(orders.len));
    for (orders) |order| {
        try packOrder(&encoder, order);
    }

    // Key 3: "grouping"
    try encoder.writeString("grouping");
    try encoder.writeString(grouping);

    return encoder.toOwnedSlice();
}
```

**关键点**:
1. **固定顺序**: type → orders → grouping
2. **字段名必须精确**: 不能改变大小写或拼写
3. **嵌套编码**: orders 数组内的每个订单也要正确编码

#### 单个订单编码

```zig
fn packOrder(encoder: *Encoder, order: OrderRequest) !void {
    // 订单 map (6 个 key: a, b, p, s, r, t)
    try encoder.writeMapHeader(6);

    try encoder.writeString("a");  // asset index
    try encoder.writeUint(order.a);

    try encoder.writeString("b");  // is_buy
    try encoder.writeBool(order.b);

    try encoder.writeString("p");  // price
    try encoder.writeString(order.p);

    try encoder.writeString("s");  // size
    try encoder.writeString(order.s);

    try encoder.writeString("r");  // reduce_only
    try encoder.writeBool(order.r);

    try encoder.writeString("t");  // order type
    if (order.t.limit) |limit| {
        try encoder.writeMapHeader(1);
        try encoder.writeString("limit");
        try encoder.writeMapHeader(1);
        try encoder.writeString("tif");
        try encoder.writeString(limit.tif);
    } else if (order.t.market) |_| {
        try encoder.writeMapHeader(1);
        try encoder.writeString("market");
        try encoder.writeMapHeader(0);  // 空 map
    }
}
```

**字段顺序至关重要**：
- 必须按 a, b, p, s, r, t 顺序
- 价格和数量使用**字符串**而非数字（Hyperliquid 要求）

#### cancelOrder 编码

```zig
pub const CancelRequest = struct {
    a: u64,  // asset index
    o: u64,  // order id
};

pub fn packCancelAction(
    allocator: Allocator,
    cancels: []const CancelRequest,
) ![]u8 {
    var encoder = Encoder.init(allocator);
    errdefer encoder.deinit();

    // 根 map (2 个 key)
    try encoder.writeMapHeader(2);

    // Key 1: "type"
    try encoder.writeString("type");
    try encoder.writeString("cancel");

    // Key 2: "cancels" (数组)
    try encoder.writeString("cancels");
    try encoder.writeArrayHeader(@intCast(cancels.len));

    for (cancels) |cancel| {
        try packCancel(&encoder, cancel);
    }

    return encoder.toOwnedSlice();
}

fn packCancel(encoder: *Encoder, cancel: CancelRequest) !void {
    // 取消 map (2 个 key: a, o)
    try encoder.writeMapHeader(2);

    try encoder.writeString("a");
    try encoder.writeUint(cancel.a);

    try encoder.writeString("o");
    try encoder.writeUint(cancel.o);
}
```

### 使用流程

#### 下单签名流程

```zig
// 1. 构造 msgpack OrderRequest
const msgpack_order = msgpack.OrderRequest{
    .a = asset_index,  // BTC = 3
    .b = true,         // buy
    .p = "87000.0",    // 字符串格式
    .s = "0.001",      // 字符串格式
    .r = false,        // not reduce_only
    .t = .{ .limit = .{ .tif = "Gtc" } },
};

// 2. 编码为 msgpack 二进制
const orders = [_]msgpack.OrderRequest{msgpack_order};
const action_msgpack = try msgpack.packOrderAction(allocator, &orders, "na");
defer allocator.free(action_msgpack);

// 3. 生成 nonce
const nonce = @as(u64, @intCast(std.time.milliTimestamp()));

// 4. 签名 msgpack 数据
const signature = try signer.signAction(action_msgpack, nonce);

// 5. 构造 JSON 请求体（包含 action, nonce, signature）
const request_json = try std.fmt.allocPrint(...);
```

**关键步骤**:
1. ✅ 使用 msgpack 编码 action
2. ✅ 签名 msgpack 二进制数据（不是 JSON）
3. ✅ 将 JSON 请求体发送到服务器（包含 nonce 和 signature）

#### 撤单签名流程

```zig
// 1. 构造 msgpack CancelRequest
const msgpack_cancel = msgpack.CancelRequest{
    .a = asset_index,  // 3
    .o = order_id,     // 45564725639
};

// 2. 编码为 msgpack 二进制
const cancels = [_]msgpack.CancelRequest{msgpack_cancel};
const action_msgpack = try msgpack.packCancelAction(allocator, &cancels);
defer allocator.free(action_msgpack);

// 3. 签名 msgpack 数据
const signature = try signer.signAction(action_msgpack, nonce);

// 4. 构造 JSON 请求体
const request_json = try std.fmt.allocPrint(...);
```

### 测试验证

```zig
test "pack order action" {
    const orders = [_]OrderRequest{
        .{
            .a = 0,
            .b = true,
            .p = "1000",
            .s = "0.01",
            .r = false,
            .t = .{ .limit = .{ .tif = "Gtc" } },
        },
    };

    const packed_data = try packOrderAction(std.testing.allocator, &orders, "na");
    defer std.testing.allocator.free(packed_data);

    // 验证 fixmap header
    try std.testing.expectEqual(@as(u8, 0x83), packed_data[0]);  // map with 3 keys

    // 验证包含 "type", "orders", "grouping" 字符串
    const packed_str = std.mem.sliceAsBytes(packed_data);
    try std.testing.expect(std.mem.indexOf(u8, packed_str, "type") != null);
    try std.testing.expect(std.mem.indexOf(u8, packed_str, "orders") != null);
    try std.testing.expect(std.mem.indexOf(u8, packed_str, "grouping") != null);
}
```

### 常见陷阱

1. **❌ 字段顺序错误**
   ```zig
   // 错误：orders 在 type 之前
   try encoder.writeString("orders");
   // ... 应该先写 "type"
   ```

2. **❌ 使用 JSON 签名**
   ```zig
   // 错误：签名 JSON 字符串
   const action_json = "...";
   const signature = try signer.signAction(action_json, nonce);

   // 正确：签名 msgpack 二进制
   const action_msgpack = try msgpack.packOrderAction(...);
   const signature = try signer.signAction(action_msgpack, nonce);
   ```

3. **❌ 价格/数量使用数字**
   ```zig
   // 错误：
   const order = msgpack.OrderRequest{
       .p = 87000.0,  // ❌ 浮点数
       .s = 0.001,    // ❌ 浮点数
   };

   // 正确：
   const order = msgpack.OrderRequest{
       .p = "87000.0",  // ✅ 字符串
       .s = "0.001",    // ✅ 字符串
   };
   ```

### 性能

- **编码耗时**: ~1-2 微秒（单个订单）
- **内存分配**: 动态增长，通常 < 1 KB
- **复杂度**: O(n)，n 为订单数量

### 参考

- MessagePack 规范：https://msgpack.org/
- Hyperliquid API 文档：https://hyperliquid.gitbook.io/hyperliquid-docs/

---

## 价格/数量 Wire Format

Hyperliquid 对价格和数量的字符串格式有严格要求，必须与 Python SDK 的 `Decimal.normalize()` 行为一致。

### 格式要求

| 原始值 | 错误格式 | 正确格式 | 说明 |
|--------|----------|----------|------|
| 87000.0 | `"87000.0"` | `"87000"` | 移除尾部 `.0` |
| 87736.5 | - | `"87736.5"` | 保留有效小数 |
| 0.0010 | `"0.0010"` | `"0.001"` | 移除尾部零 |
| 1.0 | `"1.0"` | `"1"` | 移除尾部 `.0` |

### 实现

```zig
/// Format Decimal to price string (Hyperliquid wire format)
/// - Rounds to appropriate precision
/// - Removes trailing zeros (like Python SDK's Decimal.normalize())
/// Example: 87000.0 -> "87000", 87736.5 -> "87736.5"
pub fn formatPrice(allocator: std.mem.Allocator, price: Decimal) ![]const u8 {
    // Round to 8 decimal places first (matching Python SDK)
    const float_price = price.toFloat();

    // Format with enough precision, then normalize
    var buf: [64]u8 = undefined;
    const formatted = std.fmt.bufPrint(&buf, "{d:.8}", .{float_price}) catch return error.FormatError;

    // Find the decimal point and remove trailing zeros
    var end: usize = formatted.len;

    // Check if there's a decimal point
    var has_decimal = false;
    for (formatted) |c| {
        if (c == '.') {
            has_decimal = true;
            break;
        }
    }

    if (has_decimal) {
        // Remove trailing zeros
        while (end > 0 and formatted[end - 1] == '0') {
            end -= 1;
        }
        // Remove trailing decimal point if no decimals left
        if (end > 0 and formatted[end - 1] == '.') {
            end -= 1;
        }
    }

    return allocator.dupe(u8, formatted[0..end]);
}
```

### 为什么这很重要？

1. **签名数据字节级敏感**：Hyperliquid 使用签名数据的 hash 来验证身份
2. **格式不匹配 → 签名失败**：`"87000.0"` vs `"87000"` 产生不同的 hash
3. **恢复地址错误**：签名验证失败时，每次返回不同的错误地址

### 调试技巧

如果遇到 "User or API Wallet does not exist" 错误，且每次地址不同：
1. 检查价格/数量字符串格式
2. 确保没有尾部零
3. 对比 Python SDK 的输出

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
