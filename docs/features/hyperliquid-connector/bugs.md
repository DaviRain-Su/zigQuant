# Hyperliquid 连接器 - Bug 追踪

> 已知问题和修复记录

**最后更新**: 2025-12-24

---

## 当前状态

目前处于开发阶段，已修复 2 个 Bug。

---

## 已知 Bug

目前无已知Bug。

---

## 已修复的 Bug

### Bug #4: Signer lazy loading for balance/positions commands

**发现日期**: 2025-12-24
**修复日期**: 2025-12-24
**严重性**: High

**问题描述**:
- `getBalance()` 和 `getPositions()` 方法在 signer 未初始化时会崩溃
- 这些方法直接访问 `self.signer.?.address`，但没有确保 signer 已经初始化
- 如果在 connector 创建时未提供私钥，signer 会是 `null`，导致程序崩溃

**复现步骤**:
1. 创建 connector 时提供 `api_secret`
2. 调用 `exchange.getBalance()` 或 `exchange.getPositions()`
3. 如果 signer 未在初始化时自动创建，程序会在访问 `signer.?.address` 时崩溃

**根本原因**:
- Connector 在 `create()` 时设置 `signer = null`，注释说明采用懒加载策略
- 但 `getBalance()` 和 `getPositions()` 没有调用懒加载机制

**修复方案**:
实现 `ensureSigner()` 懒加载机制，在所有需要认证的方法中调用：

```zig
/// Ensure signer is initialized (lazy initialization)
fn ensureSigner(self: *HyperliquidConnector) !void {
    // Already initialized
    if (self.signer != null) return;

    // No credentials provided
    if (self.config.api_secret.len == 0) {
        return error.NoCredentials;
    }

    // Initialize signer now
    self.logger.info("Lazy-initializing signer for trading operations...", .{}) catch {};
    self.signer = try self.initializeSigner(self.config.api_secret);

    // Update ExchangeAPI with the new signer
    const signer_ptr = if (self.signer) |*s| s else null;
    self.exchange_api.signer = signer_ptr;
}
```

**修改位置**:
- `src/exchange/hyperliquid/connector.zig`:
  - 第 426 行：`cancelOrder()` 调用 `ensureSigner()`
  - 第 441 行：`cancelAllOrders()` 调用 `ensureSigner()`
  - 第 586 行：`getOpenOrders()` 调用 `ensureSigner()`
  - 第 677 行：`getBalance()` 调用 `ensureSigner()`
  - 第 721 行：`getPositions()` 调用 `ensureSigner()`

**影响范围**:
- `getBalance()`
- `getPositions()`
- `getOpenOrders()`
- `cancelOrder()`
- `cancelAllOrders()`

**测试验证**:
- ✅ 集成测试确认所有认证方法正常工作
- ✅ 懒加载机制正确触发，不影响性能

---

### Bug #5: Missing getOpenOrders() implementation

**发现日期**: 2025-12-24
**修复日期**: 2025-12-24
**严重性**: Medium

**问题描述**:
- `IExchange` 接口定义了 `getOpenOrders()` 方法
- Hyperliquid connector 的 vtable 中引用了该方法，但实际未实现
- 导致运行时调用 `getOpenOrders()` 会失败

**复现步骤**:
1. 创建 Hyperliquid connector
2. 调用 `exchange.getOpenOrders(pair)`
3. 方法不存在或返回 `error.NotImplemented`

**根本原因**:
- `connector.zig` 的 vtable 包含 `.getOpenOrders = getOpenOrders`
- 但文件中缺少 `getOpenOrders()` 函数的实现

**修复方案**:
实现完整的 `getOpenOrders()` 方法：

```zig
fn getOpenOrders(ptr: *anyopaque, pair: ?TradingPair) anyerror![]Order {
    const self: *HyperliquidConnector = @ptrCast(@alignCast(ptr));

    self.logger.debug("getOpenOrders called", .{}) catch {};

    // Ensure signer is initialized (lazy loading)
    try self.ensureSigner();

    // Rate limiting
    self.rate_limiter.wait();

    // Get user's open orders
    const user_address = self.signer.?.address;
    const parsed_orders = try self.info_api.getOpenOrders(user_address);
    defer parsed_orders.deinit();

    // Count matching orders
    var count: usize = 0;
    for (parsed_orders.value) |open_order| {
        if (pair) |p| {
            if (std.mem.eql(u8, open_order.coin, p.base)) {
                count += 1;
            }
        } else {
            count += 1;
        }
    }

    // Allocate result array
    var orders = try self.allocator.alloc(Order, count);
    errdefer self.allocator.free(orders);

    // Convert all matching orders
    var idx: usize = 0;
    for (parsed_orders.value) |open_order| {
        // Check filter and convert to unified Order format
        // ... (详见实现)
        idx += 1;
    }

    return orders;
}
```

**修改位置**:
- `src/exchange/hyperliquid/connector.zig` 第 581-666 行

**功能特性**:
- ✅ 支持查询所有挂单（`pair = null`）
- ✅ 支持按交易对过滤（`pair = TradingPair`）
- ✅ 自动转换 Hyperliquid 格式到统一 Order 格式
- ✅ 正确解析 side、price、amount、filled_amount
- ✅ 自动调用 `ensureSigner()` 确保认证
- ✅ 返回动态分配的数组（调用者负责释放）

**测试验证**:
- ✅ 集成测试确认方法正常工作
- ✅ 支持过滤和不过滤两种模式
- ✅ 正确转换订单数据格式

---

## 报告 Bug

请包含以下信息：
1. Bug 标题
2. 严重性 (Critical | High | Medium | Low)
3. 复现步骤
4. 预期行为 vs 实际行为
5. 环境信息（Zig 版本、操作系统等）
6. 相关代码片段或日志

提交到：[GitHub Issues](https://github.com/your-repo/zigQuant/issues)
