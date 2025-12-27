# Hyperliquid Adapter 实现细节

**版本**: v0.6.0
**状态**: 📋 待开始

---

## 架构概览

```
┌─────────────────────────────────────────────────────────────┐
│                   Hyperliquid Adapter                        │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌────────────────────────────────────────────────────────┐ │
│  │                    WebSocketClient                      │ │
│  │              (共享连接 - 数据 + 订单更新)               │ │
│  └────────────────────────────────────────────────────────┘ │
│           ↑                              ↑                   │
│  ┌────────┴────────┐          ┌──────────┴──────────┐       │
│  │ DataProvider    │          │ ExecutionClient     │       │
│  │ - allMids       │          │ - orderUpdates     │       │
│  │ - l2Book        │          │ - userFills        │       │
│  │ - trades        │          │                     │       │
│  └─────────────────┘          └─────────────────────┘       │
│           │                              │                   │
│           ↓                              ↓                   │
│  ┌─────────────────────────────────────────────────────────┐│
│  │                     MessageBus                           ││
│  └─────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────┘
```

---

## WebSocket 实现

### 连接管理

```zig
pub const WebSocketClient = struct {
    allocator: Allocator,
    uri: std.Uri,
    stream: ?std.net.Stream,
    connected: std.atomic.Value(bool),
    recv_thread: ?std.Thread,

    pub fn connect(self: *WebSocketClient) !void {
        // 1. DNS 解析
        const addr = try std.net.Address.resolveIp(self.uri.host.?, self.uri.port.?);

        // 2. 建立 TCP 连接
        self.stream = try std.net.tcpConnectToAddress(addr);

        // 3. TLS 握手 (wss://)
        if (std.mem.eql(u8, self.uri.scheme, "wss")) {
            try self.upgradeTls();
        }

        // 4. WebSocket 握手
        try self.performWebSocketHandshake();

        self.connected.store(true, .seq_cst);

        // 5. 启动接收线程
        self.recv_thread = try std.Thread.spawn(.{}, receiveLoop, .{self});
    }

    fn performWebSocketHandshake(self: *WebSocketClient) !void {
        // 生成 Sec-WebSocket-Key
        var key_bytes: [16]u8 = undefined;
        std.crypto.random.bytes(&key_bytes);
        const key = std.base64.standard.encode(&key_bytes);

        // 发送握手请求
        const request = try std.fmt.allocPrint(self.allocator,
            "GET {s} HTTP/1.1\r\n" ++
            "Host: {s}\r\n" ++
            "Upgrade: websocket\r\n" ++
            "Connection: Upgrade\r\n" ++
            "Sec-WebSocket-Key: {s}\r\n" ++
            "Sec-WebSocket-Version: 13\r\n\r\n",
            .{ self.uri.path, self.uri.host.?, key },
        );

        try self.stream.?.writeAll(request);

        // 读取响应
        var buf: [1024]u8 = undefined;
        const len = try self.stream.?.read(&buf);

        // 验证 101 Switching Protocols
        if (!std.mem.startsWith(u8, buf[0..len], "HTTP/1.1 101")) {
            return error.HandshakeFailed;
        }
    }

    pub fn send(self: *WebSocketClient, message: []const u8) !void {
        const frame = try self.encodeFrame(.text, message);
        try self.stream.?.writeAll(frame);
    }

    fn receiveLoop(self: *WebSocketClient) void {
        while (self.connected.load(.seq_cst)) {
            const frame = self.readFrame() catch |err| {
                log.err("Read error: {}", .{err});
                self.handleDisconnect();
                return;
            };

            switch (frame.opcode) {
                .text => self.onMessage(frame.payload),
                .ping => self.sendPong(frame.payload) catch {},
                .pong => {},
                .close => {
                    self.handleDisconnect();
                    return;
                },
            }
        }
    }
};
```

### 消息帧编码/解码

```zig
const Frame = struct {
    fin: bool,
    opcode: Opcode,
    mask: bool,
    payload: []const u8,
};

const Opcode = enum(u4) {
    continuation = 0x0,
    text = 0x1,
    binary = 0x2,
    close = 0x8,
    ping = 0x9,
    pong = 0xA,
};

fn encodeFrame(self: *WebSocketClient, opcode: Opcode, payload: []const u8) ![]u8 {
    var frame = std.ArrayList(u8).init(self.allocator);

    // 第一字节: FIN + opcode
    try frame.append(0x80 | @intFromEnum(opcode));

    // 第二字节: MASK + payload length
    const mask_bit: u8 = 0x80;  // 客户端必须 mask
    if (payload.len < 126) {
        try frame.append(mask_bit | @truncate(payload.len));
    } else if (payload.len < 65536) {
        try frame.append(mask_bit | 126);
        try frame.appendSlice(std.mem.toBytes(@as(u16, @truncate(payload.len))));
    } else {
        try frame.append(mask_bit | 127);
        try frame.appendSlice(std.mem.toBytes(@as(u64, payload.len)));
    }

    // Masking key
    var mask_key: [4]u8 = undefined;
    std.crypto.random.bytes(&mask_key);
    try frame.appendSlice(&mask_key);

    // Masked payload
    for (payload, 0..) |byte, i| {
        try frame.append(byte ^ mask_key[i % 4]);
    }

    return frame.toOwnedSlice();
}

fn readFrame(self: *WebSocketClient) !Frame {
    var header: [2]u8 = undefined;
    _ = try self.stream.?.readAll(&header);

    const fin = (header[0] & 0x80) != 0;
    const opcode: Opcode = @enumFromInt(header[0] & 0x0F);
    const masked = (header[1] & 0x80) != 0;
    var payload_len: usize = header[1] & 0x7F;

    // 扩展长度
    if (payload_len == 126) {
        var len_bytes: [2]u8 = undefined;
        _ = try self.stream.?.readAll(&len_bytes);
        payload_len = std.mem.readInt(u16, &len_bytes, .big);
    } else if (payload_len == 127) {
        var len_bytes: [8]u8 = undefined;
        _ = try self.stream.?.readAll(&len_bytes);
        payload_len = std.mem.readInt(u64, &len_bytes, .big);
    }

    // Masking key (服务端通常不 mask)
    var mask_key: [4]u8 = undefined;
    if (masked) {
        _ = try self.stream.?.readAll(&mask_key);
    }

    // Payload
    const payload = try self.allocator.alloc(u8, payload_len);
    _ = try self.stream.?.readAll(payload);

    if (masked) {
        for (payload, 0..) |*byte, i| {
            byte.* ^= mask_key[i % 4];
        }
    }

    return .{
        .fin = fin,
        .opcode = opcode,
        .mask = masked,
        .payload = payload,
    };
}
```

---

## 订阅管理

```zig
pub const SubscriptionManager = struct {
    subscriptions: std.StringHashMap(SubscriptionState),
    allocator: Allocator,

    pub const SubscriptionState = struct {
        channel: Channel,
        symbol: []const u8,
        subscribed_at: i64,
        last_update: i64,
    };

    pub const Channel = enum {
        allMids,
        l2Book,
        trades,
        candle,
        orderUpdates,
        userFills,
    };

    pub fn add(self: *SubscriptionManager, channel: Channel, symbol: []const u8) !void {
        const key = try std.fmt.allocPrint(self.allocator, "{s}:{s}", .{
            @tagName(channel),
            symbol,
        });

        try self.subscriptions.put(key, .{
            .channel = channel,
            .symbol = try self.allocator.dupe(u8, symbol),
            .subscribed_at = std.time.milliTimestamp(),
            .last_update = 0,
        });
    }

    pub fn buildMessage(channel: Channel, symbol: []const u8, allocator: Allocator) ![]const u8 {
        return switch (channel) {
            .allMids => try allocator.dupe(u8,
                \\{"method":"subscribe","subscription":{"type":"allMids"}}
            ),
            .l2Book => try std.fmt.allocPrint(allocator,
                \\{{"method":"subscribe","subscription":{{"type":"l2Book","coin":"{s}"}}}}
            , .{symbol}),
            .trades => try std.fmt.allocPrint(allocator,
                \\{{"method":"subscribe","subscription":{{"type":"trades","coin":"{s}"}}}}
            , .{symbol}),
            .orderUpdates => try std.fmt.allocPrint(allocator,
                \\{{"method":"subscribe","subscription":{{"type":"orderUpdates","user":"{s}"}}}}
            , .{symbol}),  // symbol 此处为 user address
            else => error.UnsupportedChannel,
        };
    }
};
```

---

## JSON 消息解析

```zig
pub const MessageParser = struct {
    allocator: Allocator,

    pub fn parse(self: *MessageParser, raw: []const u8) !ParsedMessage {
        const parsed = try std.json.parseFromSlice(
            std.json.Value,
            self.allocator,
            raw,
            .{},
        );
        defer parsed.deinit();

        const root = parsed.value.object;
        const channel = root.get("channel") orelse return error.NoChannel;

        return switch (channel.string) {
            "allMids" => .{ .all_mids = try self.parseAllMids(root) },
            "l2Book" => .{ .orderbook = try self.parseL2Book(root) },
            "trades" => .{ .trades = try self.parseTrades(root) },
            "orderUpdates" => .{ .order_update = try self.parseOrderUpdate(root) },
            "fills" => .{ .fill = try self.parseFill(root) },
            else => error.UnknownChannel,
        };
    }

    fn parseAllMids(self: *MessageParser, root: std.json.ObjectMap) ![]Quote {
        const data = root.get("data").?.object;
        const mids = data.get("mids").?.object;

        var quotes = std.ArrayList(Quote).init(self.allocator);
        var it = mids.iterator();

        while (it.next()) |entry| {
            const mid_str = entry.value_ptr.string;
            const mid = try std.fmt.parseFloat(f64, mid_str);

            try quotes.append(.{
                .symbol = try self.allocator.dupe(u8, entry.key_ptr.*),
                .mid = Decimal.fromFloat(mid),
                .timestamp = Timestamp.now(),
            });
        }

        return quotes.toOwnedSlice();
    }

    fn parseL2Book(self: *MessageParser, root: std.json.ObjectMap) !OrderBook {
        const data = root.get("data").?.object;
        const coin = data.get("coin").?.string;
        const levels = data.get("levels").?.array;

        var bids = std.ArrayList(PriceLevel).init(self.allocator);
        var asks = std.ArrayList(PriceLevel).init(self.allocator);

        // levels[0] = bids, levels[1] = asks
        for (levels.items[0].array.items) |level| {
            const arr = level.array;
            try bids.append(.{
                .price = Decimal.fromFloat(try std.fmt.parseFloat(f64, arr.items[0].string)),
                .quantity = Decimal.fromFloat(try std.fmt.parseFloat(f64, arr.items[1].string)),
            });
        }

        for (levels.items[1].array.items) |level| {
            const arr = level.array;
            try asks.append(.{
                .price = Decimal.fromFloat(try std.fmt.parseFloat(f64, arr.items[0].string)),
                .quantity = Decimal.fromFloat(try std.fmt.parseFloat(f64, arr.items[1].string)),
            });
        }

        return .{
            .symbol = try self.allocator.dupe(u8, coin),
            .bids = bids.toOwnedSlice(),
            .asks = asks.toOwnedSlice(),
            .timestamp = Timestamp.now(),
        };
    }
};
```

---

## EIP-712 签名

```zig
pub const Wallet = struct {
    private_key: [32]u8,
    address: [20]u8,

    pub fn init(private_key_hex: []const u8) !Wallet {
        var key: [32]u8 = undefined;
        _ = try std.fmt.hexToBytes(&key, private_key_hex);

        // 从私钥派生公钥和地址
        const public_key = try secp256k1.derivePublicKey(key);
        const address = keccak256(public_key[1..])[12..32].*;

        return .{
            .private_key = key,
            .address = address,
        };
    }

    pub fn signTypedData(self: *Wallet, domain: Domain, message: anytype) !Signature {
        // 1. 计算 domain separator
        const domain_hash = computeDomainSeparator(domain);

        // 2. 计算 message hash
        const message_hash = computeStructHash(message);

        // 3. 组合: keccak256("\x19\x01" || domainSeparator || structHash)
        var data: [66]u8 = undefined;
        data[0] = 0x19;
        data[1] = 0x01;
        @memcpy(data[2..34], &domain_hash);
        @memcpy(data[34..66], &message_hash);

        const hash = keccak256(&data);

        // 4. ECDSA 签名
        return try secp256k1.sign(self.private_key, hash);
    }

    fn computeDomainSeparator(domain: Domain) [32]u8 {
        // EIP-712 domain separator
        const type_hash = keccak256(
            "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
        );

        var encoded: [160]u8 = undefined;
        @memcpy(encoded[0..32], &type_hash);
        @memcpy(encoded[32..64], &keccak256(domain.name));
        @memcpy(encoded[64..96], &keccak256(domain.version));
        @memcpy(encoded[96..128], &std.mem.toBytes(domain.chain_id));
        @memcpy(encoded[128..160], &domain.verifying_contract);

        return keccak256(&encoded);
    }
};

pub const Signature = struct {
    r: [32]u8,
    s: [32]u8,
    v: u8,

    pub fn toHex(self: Signature, allocator: Allocator) ![]u8 {
        return try std.fmt.allocPrint(allocator, "0x{s}{s}{x:0>2}", .{
            std.fmt.fmtSliceHexLower(&self.r),
            std.fmt.fmtSliceHexLower(&self.s),
            self.v,
        });
    }
};
```

---

## HTTP 客户端

```zig
pub const HttpClient = struct {
    allocator: Allocator,
    base_url: []const u8,

    pub fn post(self: *HttpClient, path: []const u8, body: anytype) ![]u8 {
        const url = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{
            self.base_url,
            path,
        });
        defer self.allocator.free(url);

        const json_body = try std.json.stringifyAlloc(self.allocator, body, .{});
        defer self.allocator.free(json_body);

        var client = std.http.Client{ .allocator = self.allocator };
        defer client.deinit();

        var request = try client.request(.POST, try std.Uri.parse(url), .{
            .extra_headers = &.{
                .{ .name = "Content-Type", .value = "application/json" },
            },
        }, .{});
        defer request.deinit();

        request.transfer_encoding = .{ .content_length = json_body.len };
        try request.writer().writeAll(json_body);
        try request.finish();
        try request.wait();

        const response_body = try request.reader().readAllAlloc(self.allocator, 1024 * 1024);
        return response_body;
    }
};
```

---

## 重连机制

```zig
fn handleDisconnect(self: *HyperliquidDataProvider) void {
    self.connected.store(false, .seq_cst);

    // 发布断开事件
    self.message_bus.publish("system.disconnected", .{
        .system = .{ .message = "Hyperliquid WebSocket disconnected" },
    });

    // 指数退避重连
    var delay: u64 = self.config.reconnect_delay_ms;
    var attempts: u32 = 0;

    while (attempts < self.config.max_reconnect_attempts) : (attempts += 1) {
        std.time.sleep(delay * std.time.ns_per_ms);

        if (self.ws_client.connect()) |_| {
            log.info("Reconnected after {} attempts", .{attempts + 1});
            self.resubscribeAll();
            self.connected.store(true, .seq_cst);

            self.message_bus.publish("system.reconnected", .{
                .system = .{ .message = "Hyperliquid WebSocket reconnected" },
            });
            return;
        } else |err| {
            log.warn("Reconnect attempt {} failed: {}", .{ attempts + 1, err });
            delay = @min(delay * 2, 30000);  // 最大 30 秒
        }
    }

    log.err("Failed to reconnect after {} attempts", .{self.config.max_reconnect_attempts});
}
```

---

## 文件结构

```
src/adapters/hyperliquid/
├── mod.zig                     # 模块入口
├── data_provider.zig           # HyperliquidDataProvider
├── execution_client.zig        # HyperliquidExecutionClient
├── websocket_client.zig        # WebSocket 客户端
├── http_client.zig             # HTTP 客户端
├── subscription_manager.zig    # 订阅管理
├── message_parser.zig          # JSON 解析
├── wallet.zig                  # 签名
├── order_manager.zig           # 订单状态管理
└── tests/
    ├── websocket_test.zig
    ├── parser_test.zig
    └── integration_test.zig
```

---

*Last updated: 2025-12-27*
