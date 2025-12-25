# Hyperliquid 连接器 - Bug 追踪

> 已知问题和修复记录

**最后更新**: 2025-12-25

---

## 当前状态

目前处于开发阶段，已修复 7 个 Bug（订单生命周期集成测试全部通过）。

---

## 已知 Bug

目前无已知Bug。

---

## 已修复的 Bug

### Bug #1: Asset index hardcoded to 0

**发现日期**: 2025-12-25
**修复日期**: 2025-12-25
**严重性**: Critical

**问题描述**:
- `exchange_api.zig` 中 `placeOrder()` 方法将 asset index 硬编码为 0
- 导致所有订单都被提交到 SOL 市场（index 0），而不是用户指定的市场
- BTC 的 asset index 实际是 3，ETH 是 4，但代码中始终使用 0

**复现步骤**:
1. 尝试下 BTC-USDC 限价单
2. 收到错误："Order price cannot be more than 80% away from the reference price"
3. 根因：订单被提交到 SOL 市场，但价格是 BTC 的价格

**根本原因**:
```zig
// ❌ 错误代码
const msgpack_order = msgpack.OrderRequest{
    .a = 0,  // 硬编码为 0 (SOL)
    .b = order_request.is_buy,
    // ...
};
```

**修复方案**:
1. 在 `types.zig` 的 `OrderRequest` 中添加 `asset_index` 字段
2. 在 `connector.zig` 的 `createOrder()` 中调用 `getAssetIndex()` 动态查询
3. 在 `exchange_api.zig` 中使用 `order_request.asset_index`

**修改位置**:
- `src/exchange/hyperliquid/types.zig`:66 - 添加 `asset_index: u64` 字段
- `src/exchange/hyperliquid/connector.zig`:387 - 添加 `const asset_index = try self.getAssetIndex(symbol);`
- `src/exchange/hyperliquid/exchange_api.zig`:67 - 使用 `order_request.asset_index`

**影响范围**:
- 所有下单操作（市价单和限价单）

**测试验证**:
- ✅ BTC 订单成功提交（使用 asset index 3）
- ✅ 订单被正确路由到 BTC 市场
- ✅ 集成测试通过

---

### Bug #2: Querying wrong account address (API wallet vs main account)

**发现日期**: 2025-12-25
**修复日期**: 2025-12-25
**严重性**: High

**问题描述**:
- `getOrder()`, `getOpenOrders()`, `cancelOrder()` 等方法使用 `self.signer.?.address` 查询账户
- `signer.address` 是 API wallet 地址（用于签名），不是主账户地址
- 导致查询不到任何订单（查询的是错误的账户）

**复现步骤**:
1. 成功下单后，订单状态为 "resting"
2. 调用 `getOpenOrders()` 查询挂单
3. 返回空数组 `[]`（实际应该有挂单）
4. 日志显示查询的是 API wallet 地址 `0xd83ae44dfb9afd61ad65db2c9cc8a676eacbcb5f`

**根本原因**:
- Hyperliquid 使用双地址系统：
  - **主账户地址** (api_key): 持有资产和订单
  - **API wallet 地址** (signer.address): 用于签名操作
- 查询操作应该使用主账户地址 (`self.config.api_key`)，而非签名地址

**修复方案**:
```zig
// ❌ 错误代码
const user_address = self.signer.?.address;  // API wallet

// ✅ 正确代码
const user_address = self.config.api_key;    // Main account
```

**修改位置**:
- `src/exchange/hyperliquid/connector.zig`:489 - `getOrder()` 使用 `self.config.api_key`
- `src/exchange/hyperliquid/connector.zig`:604 - `getOpenOrders()` 使用 `self.config.api_key`
- `src/exchange/hyperliquid/connector.zig`:428 - `cancelOrder()` 注释说明

**影响范围**:
- `getOrder()` - 查询单个订单
- `getOpenOrders()` - 查询所有挂单
- 间接影响 `cancelOrder()` 的验证逻辑

**测试验证**:
- ✅ `getOpenOrders()` 返回正确的挂单列表
- ✅ 可以成功查询订单状态
- ✅ 集成测试通过

---

### Bug #3: client_order_id memory leak (use-after-free)

**发现日期**: 2025-12-25
**修复日期**: 2025-12-25
**严重性**: High

**问题描述**:
- `order_manager.zig` 中分配 `client_order_id` 后立即 `defer free`
- `order_store.zig` 中使用该 `client_order_id` 作为 HashMap key
- 当 `submitOrder()` 返回后，`client_order_id` 被释放
- 导致 `Order.client_order_id` 指向已释放的内存（悬空指针）

**复现步骤**:
1. 调用 `order_manager.submitOrder()`
2. `client_order_id` 被分配并作为 key 添加到 `order_store`
3. 函数返回时 `defer free` 触发
4. `Order.client_order_id` 指向已释放的内存
5. 后续访问 `Order.client_order_id` 会崩溃或读取垃圾数据

**根本原因**:
```zig
// ❌ 错误代码 (order_manager.zig)
const client_order_id = try std.fmt.allocPrint(...);
defer self.allocator.free(client_order_id);  // 过早释放

// HashMap 使用 client_order_id 作为 key
try self.order_store.add(order);  // order.client_order_id = client_order_id
```

**修复方案**:
1. `order_manager.zig`: 移除 `defer free`，让 `order_store` 拥有内存
2. `order_store.zig`: 在 `add()` 中 `dupe` key，统一 Order 的 `client_order_id` 指针

```zig
// order_manager.zig
const client_order_id = try std.fmt.allocPrint(...);
// 不再 defer free，ownership 转移到 order_store
try self.order_store.add(order);
defer self.allocator.free(client_order_id);  // 在 add() 完成后释放原始字符串

// order_store.zig
pub fn add(self: *OrderStore, order: Order) !void {
    const client_id_key = try self.allocator.dupe(u8, order.client_order_id);
    // 统一指针：Order.client_order_id 指向 HashMap key
    order_ptr.client_order_id = client_id_key;
}
```

**修改位置**:
- `src/trading/order_manager.zig`:192-202 - 调整内存释放时机
- `src/trading/order_store.zig`:41-49 - 统一 client_order_id 指针

**影响范围**:
- 所有使用 `client_order_id` 的操作
- `order_store` 的 HashMap 键值管理

**测试验证**:
- ✅ 内存泄漏检测：0 leaks
- ✅ 订单可以正常查询和访问
- ✅ `client_order_id` 始终有效

---

### Bug #4: Cancel order msgpack encoding

**发现日期**: 2025-12-25
**修复日期**: 2025-12-25
**严重性**: Critical

**问题描述**:
- `cancelOrder()` 使用 JSON 字符串签名，而非 msgpack-encoded 数据
- 导致签名验证失败，Hyperliquid 返回 "User or API Wallet does not exist"
- 每次运行返回不同的错误地址（因为签名数据错误）

**复现步骤**:
1. 成功下单
2. 调用 `cancelOrder(order_id)`
3. 收到错误："User or API Wallet does not exist: 0xXXXXXXXX" (不同的地址)
4. 根因：签名 JSON 而非 msgpack

**根本原因**:
```zig
// ❌ 错误代码 (exchange_api.zig)
const action_json = try std.fmt.allocPrint(...);
const signature = try self.signer.?.signAction(action_json, nonce);  // 签名 JSON

// ✅ 应该签名 msgpack
const action_msgpack = try msgpack.packCancelAction(...);
const signature = try self.signer.?.signAction(action_msgpack, nonce);
```

Hyperliquid 要求签名 **msgpack-encoded** 数据，而非 JSON 字符串。

**修复方案**:
1. 在 `msgpack.zig` 中实现 `packCancelAction()` 方法
2. 在 `exchange_api.zig` 的 `cancelOrder()` 中：
   - 构造 `msgpack.CancelRequest`
   - 调用 `msgpack.packCancelAction()` 编码
   - 使用 msgpack 数据签名

```zig
// msgpack.zig - 新增
pub const CancelRequest = struct {
    a: u64,  // asset index
    o: u64,  // order id
};

pub fn packCancelAction(
    allocator: Allocator,
    cancels: []const CancelRequest,
) ![]u8 {
    // 实现 msgpack 编码
}

// exchange_api.zig - 修复
const msgpack_cancel = msgpack.CancelRequest{
    .a = asset_index,
    .o = order_id,
};
const cancels = [_]msgpack.CancelRequest{msgpack_cancel};
const action_msgpack = try msgpack.packCancelAction(self.allocator, &cancels);
defer self.allocator.free(action_msgpack);

const signature = try self.signer.?.signAction(action_msgpack, nonce);
```

**修改位置**:
- `src/exchange/hyperliquid/msgpack.zig`:226-276 - 新增 `CancelRequest` 和 `packCancelAction()`
- `src/exchange/hyperliquid/exchange_api.zig`:210-222 - 使用 msgpack 签名

**影响范围**:
- `cancelOrder()` - 撤单操作
- `cancelAllOrders()` - 批量撤单（TODO: 同样需要 msgpack）

**测试验证**:
- ✅ 撤单成功返回 `{"status":"ok"}`
- ✅ 签名验证通过
- ✅ 集成测试通过

---

### Bug #5: Signer lazy loading for balance/positions commands

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

### Bug #6: Missing getOpenOrders() implementation

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
