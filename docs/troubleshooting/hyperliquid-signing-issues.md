# Hyperliquid 签名问题排查指南

本文档记录 Hyperliquid API 签名相关的常见问题和解决方案。

**最后更新**: 2025-12-30
**Zig 版本**: 0.15.2
**状态**: ✅ 已解决

---

## 问题索引

| 问题 | 错误信息 | 根因 | 严重性 |
|------|----------|------|--------|
| #1 | "User or API Wallet does not exist" (地址变化) | 价格/数量尾部零 | Critical |
| #2 | "User or API Wallet does not exist" (固定地址) | 使用 API wallet 而非主账户 | High |
| #3 | "Price must be divisible by tick size" | 价格未对齐 tick size | Medium |

---

## 问题 #1: 签名验证失败 - 每次返回不同地址

### 症状

```
[ERROR] Exchange API error: User or API Wallet 0xab12cd34... does not exist
```

**关键特征**: 每次运行时错误地址**不同**

### 根本原因

价格/数量字符串格式包含尾部零，导致签名数据与服务器预期不匹配。

```zig
// 错误输出
formatPrice(87000.0) → "87000.0"  // ❌ 尾部 .0

// 正确输出 (匹配 Python SDK)
formatPrice(87000.0) → "87000"    // ✅
```

Hyperliquid 对签名数据**字节级敏感**。`"87000.0"` 和 `"87000"` 的 hash 不同，导致恢复出错误的签名地址。

### 解决方案

更新 `formatPrice()` 和 `formatSize()` 移除尾部零：

```zig
// src/exchange/hyperliquid/types.zig
pub fn formatPrice(allocator: std.mem.Allocator, price: Decimal) ![]const u8 {
    const float_price = price.toFloat();
    var buf: [64]u8 = undefined;
    const formatted = std.fmt.bufPrint(&buf, "{d:.8}", .{float_price}) catch return error.FormatError;

    var end: usize = formatted.len;
    var has_decimal = false;
    for (formatted) |c| {
        if (c == '.') { has_decimal = true; break; }
    }
    if (has_decimal) {
        // 移除尾部零
        while (end > 0 and formatted[end - 1] == '0') { end -= 1; }
        // 移除尾部小数点
        if (end > 0 and formatted[end - 1] == '.') { end -= 1; }
    }

    return allocator.dupe(u8, formatted[0..end]);
}
```

### 验证方法

```
✅ 87000.0 → "87000"
✅ 87736.5 → "87736.5"
✅ 0.0010 → "0.001"
✅ 1.0 → "1"
```

### 相关文件

- `src/exchange/hyperliquid/types.zig`:304-336 - formatPrice()
- `src/exchange/hyperliquid/types.zig`:347-379 - formatSize()

---

## 问题 #2: 签名验证失败 - 地址固定但错误

### 症状

```
[ERROR] Exchange API error: User or API Wallet 0x2544763d... does not exist
```

**关键特征**: 错误地址**每次相同**，且是 API wallet 地址

### 根本原因

查询操作使用了 `signer.address`（API wallet）而非 `config.api_key`（主账户）。

Hyperliquid 双地址系统：
- **主账户地址** (api_key): 持有资产、订单、仓位
- **API wallet 地址** (signer.address): 仅用于签名操作

### 解决方案

```zig
// ❌ 错误
const user_address = self.signer.?.address;  // API wallet

// ✅ 正确
const user_address = self.config.api_key;    // 主账户
```

### 影响范围

- `getOpenOrders()` - 查询挂单
- `getBalance()` - 查询余额
- `getPositions()` - 查询仓位
- `cancelAllOrders()` - 批量撤单（查询部分）

### 相关文件

- `src/exchange/hyperliquid/connector.zig`:555-556 - cancelAllOrders
- `src/exchange/hyperliquid/connector.zig`:489 - getOrder
- `src/exchange/hyperliquid/connector.zig`:604 - getOpenOrders

---

## 问题 #3: 价格 tick size 错误

### 症状

```
[ERROR] Price must be divisible by tick size. asset=3
```

### 根本原因

价格未对齐到交易对的 tick size（最小价格变动单位）。

### 解决方案

在下单前将价格四舍五入到 tick size：

```zig
fn roundToTickSize(price: f64, tick_size: f64) f64 {
    return @round(price / tick_size) * tick_size;
}

// 使用示例
const tick_size = 0.1;  // BTC tick size
const raw_price = 87436.37;
const rounded_price = roundToTickSize(raw_price, tick_size);  // 87436.4
```

### 相关文件

- `src/cli/commands/live.zig` - roundToTickSize 函数

---

## 调试技巧

### 添加调试日志

在 `exchange_api.zig` 中添加：

```zig
std.debug.print("[DEBUG] Sending request:\n{s}\n", .{request_json});
std.debug.print("[DEBUG] Raw response:\n{s}\n", .{response_body});
```

### 验证签名地址

在 `auth.zig` 中添加本地验证：

```zig
std.debug.print("[VERIFY] Signer address: {s}\n", .{self.address});
// 如果本地恢复的地址与 self.address 匹配，问题在于数据格式
// 如果不匹配，问题在于签名算法
```

### 对比 Python SDK

使用 Python SDK 验证预期格式：

```python
from decimal import Decimal
print(Decimal("87000.0").normalize())  # 输出: 87000
print(Decimal("0.0010").normalize())   # 输出: 0.001
```

---

## 预防措施

1. **始终使用字符串格式**的价格和数量（不是数字）
2. **移除尾部零**（模拟 `Decimal.normalize()`）
3. **区分双地址**：查询用 api_key，签名用 signer.address
4. **对齐 tick size**：下单前四舍五入价格
5. **msgpack 字段顺序**：必须固定（a, b, p, s, r, t）

---

## 相关文档

- [Hyperliquid 连接器 Bug 追踪](../features/hyperliquid-connector/bugs.md)
- [Hyperliquid 连接器实现细节](../features/hyperliquid-connector/implementation.md)
- [MessagePack 编码器](../features/hyperliquid-connector/implementation.md#messagepack-编码器实现)
