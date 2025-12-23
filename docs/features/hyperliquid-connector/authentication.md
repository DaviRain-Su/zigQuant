# Hyperliquid 认证详解

> 导航: [首页](../../../README.md) / [Features](../../README.md) / [Hyperliquid 连接器](./README.md) / 认证

## 概述

Hyperliquid Exchange API 使用 **Ed25519 数字签名**进行认证。所有交易操作（下单、撤单等）都需要签名验证。

## Ed25519 签名机制

### 基本流程

1. **生成 Nonce**: 使用毫秒时间戳
2. **构造 Action**: 交易操作的 JSON/msgpack 格式
3. **签名**: 对 `action + nonce` 进行 Ed25519 签名
4. **发送请求**: 包含 action、nonce、signature

### Nonce 规则

**Nonce 系统**:
- Hyperliquid 保存每个地址的 **100 个最高 nonce**
- 每个新交易的 nonce 必须：
  1. 大于当前保存的最小 nonce
  2. 从未被使用过

**最佳实践**:
```zig
pub fn generateNonce() i64 {
    return std.time.milliTimestamp();
}
```

**错误示例**:
```
"Nonce error: nonce value is lower than the next valid nonce"
```

## 实现

### Auth 结构体

```zig
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
};
```

### 签名生成

```zig
pub fn signL1Action(
    self: *Auth,
    action: []const u8,  // action 的 JSON/msgpack
    nonce: i64,
) !Signature {
    if (self.keypair == null) {
        return error.NoSecretKey;
    }

    // 构造签名消息
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
```

### 签名结构

```zig
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

## API Wallet

### 什么是 API Wallet

**API Wallet** 是用于程序化交易的代理钱包：

- 从 [https://app.hyperliquid.xyz/API](https://app.hyperliquid.xyz/API) 创建
- 可以代表主账户或子账户签名
- 与主账户分离的私钥

### 使用 API Wallet

```zig
// 1. 创建 API wallet（在网页上）
// 2. 获取 API wallet 私钥
const api_wallet_key = "0x...";

// 3. 初始化 Auth
var auth = try Auth.init(allocator, api_wallet_key);

// 4. 下单时，API wallet 代表主账户签名
const order = try placeOrder(&client, order_request);
```

### 重要提示

- **不要重复使用** API wallet 地址
- 一旦注销 (deregister)，已用 nonce 状态可能被清除
- 已签名的操作可能在 nonce 集合被清除后被重放

## 用户地址

### 获取用户地址

```zig
pub fn getUserAddress(self: *Auth) ![]const u8 {
    if (self.keypair == null) {
        return error.NoSecretKey;
    }

    // 从 Ed25519 公钥派生以太坊地址
    const pub_key = self.keypair.?.public_key;
    var address: [42]u8 = undefined;
    _ = try std.fmt.bufPrint(&address, "0x{x}", .{pub_key.bytes[0..20]});

    return try self.allocator.dupe(u8, &address);
}
```

### 地址格式

- **格式**: 以太坊地址格式 (0x...)
- **大小写**: 建议使用小写
- **长度**: 42 字符 (包括 `0x`)

## 完整示例

### 下单流程

```zig
pub fn placeOrder(
    client: *HyperliquidClient,
    order: OrderRequest,
) !OrderResponse {
    // 1. 生成 nonce
    const nonce = Auth.generateNonce();

    // 2. 构造 action
    const action = .{
        .type = "order",
        .orders = &[_]Order{order.toApiFormat()},
        .grouping = "na",
    };

    // 3. 签名
    const action_json = try std.json.stringifyAlloc(client.allocator, action, .{});
    defer client.allocator.free(action_json);

    const signature = try client.auth.signL1Action(action_json, nonce);

    // 4. 构造请求体
    const body = .{
        .action = action,
        .nonce = nonce,
        .signature = signature,
        .vaultAddress = null,
    };

    // 5. 发送请求
    const result = try client.post("/exchange", body);
    return try parseOrderResponse(client.allocator, result);
}
```

## 常见错误

### 签名验证失败

**错误消息**:
```json
{
  "error": "L1 error: User or API Wallet 0x0123... does not exist"
}
```

**可能原因**:
1. 私钥不正确
2. 地址格式错误（使用大写而非小写）
3. 签名逻辑错误
4. 账户未存入资金

**解决方案**:
```zig
// 1. 验证私钥格式
const secret_key = "0123456789abcdef..."; // 64 字符 hex

// 2. 确保地址小写
const address = try std.ascii.toLowerString(allocator, raw_address);

// 3. 在测试网测试
if (config.testnet) {
    // 先测试最简单的操作
    const test_result = try InfoAPI.getMeta(&client);
}
```

### Nonce 错误

**错误消息**:
```
"Nonce error: nonce value is lower than the next valid nonce"
```

**解决方案**:
```zig
// 使用时间戳确保递增
pub fn generateNonce() i64 {
    const now = std.time.milliTimestamp();

    // 如果需要在同一毫秒内发送多个请求
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

## 安全最佳实践

### 1. 私钥管理

```zig
// 从环境变量读取
const secret_key = std.os.getenv("HYPERLIQUID_SECRET_KEY") orelse {
    logger.err("HYPERLIQUID_SECRET_KEY not set", .{});
    return error.NoSecretKey;
};

// 不要硬编码私钥
// ❌ const secret_key = "0x123...";
```

### 2. 测试网验证

```zig
// 始终在测试网先验证
const config = HyperliquidConfig{
    .base_url = if (use_testnet)
        HyperliquidConfig.DEFAULT_TESTNET_URL
    else
        HyperliquidConfig.DEFAULT_MAINNET_URL,
    .testnet = use_testnet,
    // ...
};
```

### 3. 签名验证

```zig
// 在发送前验证签名
const test_sig = try auth.signL1Action(test_action, test_nonce);
if (test_sig.r.len != 32 or test_sig.s.len != 32) {
    return error.InvalidSignature;
}
```

## 参考资料

- [Hyperliquid Signing Documentation](https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/signing)
- [Nonces and API Wallets](https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/nonces-and-api-wallets)
- [Zig Ed25519 Documentation](https://ziglang.org/documentation/master/std/#std.crypto.sign.Ed25519)
