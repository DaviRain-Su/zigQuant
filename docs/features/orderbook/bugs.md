# 订单簿 - Bug 追踪

> 已知问题和修复记录

**最后更新**: 2025-12-25

---

## 当前状态

当前无已知的 Critical 或 High 优先级 Bug。订单簿模块处于 v0.2.1 开发阶段，核心功能已实现并修复了关键内存管理问题，正在进行测试和优化。

---

## 已知 Bug

暂无已知 Bug。

---

## 已修复的 Bug

### BUG-001: OrderBook 符号字符串内存管理问题 (Critical) ✅

**版本**: v0.2.1
**修复日期**: 2025-12-25
**严重性**: **Critical** (系统崩溃)
**发现人**: AI Agent (集成测试中发现)

**问题描述**:
`OrderBook.init()` 未复制符号字符串，直接存储传入的切片。当 WebSocket 消息被释放后，符号字符串变成悬空指针，导致段错误 (Segmentation Fault)。

**复现步骤**:
```zig
// WebSocket 接收消息并解析
const msg = try message_handler.parse(data);
defer msg.deinit(allocator);  // 消息在回调后被释放

// 回调中使用符号创建订单簿
fn messageCallback(msg: Message) void {
    switch (msg) {
        .l2Book => |data| {
            const symbol = data.coin;  // symbol 是 msg 内存的切片
            const ob = orderbook_mgr.getOrCreate(symbol) catch return;
            // HashMap 存储了 symbol 切片，但 msg 即将被释放
        },
        else => {},
    }
}

// 下次访问 HashMap 时，symbol 已是悬空指针 -> 段错误
```

**预期行为**:
- OrderBook 应该拥有符号字符串的内存
- HashMap 键应该指向稳定的内存地址
- 不应该发生段错误

**实际行为**:
```
[DEBUG] Received WebSocket message
✓ Applied snapshot for ETH: 20 bids, 20 asks
[DEBUG] Received WebSocket message
Segmentation fault at address 0x73f0a6380000
/home/davirain/dev/zigQuant/src/market/orderbook.zig:323:32: in getOrCreate
        if (self.orderbooks.get(symbol)) |ob| {
```

**根本原因**:
1. `OrderBook.init()` 直接赋值符号字符串：`self.symbol = symbol`
2. `OrderBookManager.getOrCreate()` 使用输入切片作为 HashMap 键：`try self.orderbooks.put(symbol, ob)`
3. WebSocket 回调后消息被释放，符号字符串失效
4. 下次 `getOrCreate()` 调用 `self.orderbooks.get(symbol)` 时访问悬空指针

**修复方案**:
1. `OrderBook.init()` 使用 `allocator.dupe()` 复制符号字符串
2. `OrderBook.deinit()` 释放拥有的符号字符串
3. `OrderBookManager.getOrCreate()` 使用 OrderBook 拥有的符号作为 HashMap 键

**修复代码**:
```zig
// OrderBook.init() - 修复前
pub fn init(allocator: Allocator, symbol: []const u8) !OrderBook {
    return OrderBook{
        .allocator = allocator,
        .symbol = symbol,  // ❌ 直接存储切片
        ...
    };
}

// OrderBook.init() - 修复后
pub fn init(allocator: Allocator, symbol: []const u8) !OrderBook {
    const owned_symbol = try allocator.dupe(u8, symbol);  // ✅ 复制字符串
    errdefer allocator.free(owned_symbol);

    return OrderBook{
        .allocator = allocator,
        .symbol = owned_symbol,  // ✅ 拥有内存
        ...
    };
}

// OrderBook.deinit() - 修复后
pub fn deinit(self: *OrderBook) void {
    self.allocator.free(self.symbol);  // ✅ 释放拥有的内存
    self.bids.deinit(self.allocator);
    self.asks.deinit(self.allocator);
}

// OrderBookManager.getOrCreate() - 修复后
pub fn getOrCreate(self: *OrderBookManager, symbol: []const u8) !*OrderBook {
    self.mutex.lock();
    defer self.mutex.unlock();

    if (self.orderbooks.get(symbol)) |ob| {
        return ob;
    }

    const ob = try self.allocator.create(OrderBook);
    errdefer self.allocator.destroy(ob);

    ob.* = try OrderBook.init(self.allocator, symbol);
    errdefer ob.deinit();

    // ✅ 使用 OrderBook 拥有的符号作为 HashMap 键
    try self.orderbooks.put(ob.symbol, ob);

    return ob;
}
```

**测试验证**:
- ✅ WebSocket 集成测试运行 10 秒，接收 17 个快照，无段错误
- ✅ 无内存泄漏（GeneralPurposeAllocator 检测）
- ✅ 所有 173 个单元测试通过

**影响范围**:
- 文件: `src/market/orderbook.zig:81-101,323-343`
- 模块: OrderBook, OrderBookManager
- 功能: WebSocket 订单簿更新、多币种管理

**经验教训**:
1. **内存所有权**: 结构体应该明确拥有或借用数据
2. **生命周期**: 注意数据的生命周期，特别是跨回调边界
3. **HashMap 键**: HashMap 的键必须指向稳定的内存地址
4. **集成测试**: 集成测试能发现单元测试无法发现的内存管理问题

**相关 Issue**:
- MVP v0.2.1 OrderBook 内存管理改进
- WebSocket 集成测试实现

---

---

## 报告 Bug

如果发现订单簿相关的问题，请提供以下信息：

### 1. Bug 标题
简洁描述问题（例如：订单簿更新后排序错误）

### 2. 严重性
- **Critical**: 系统崩溃或数据丢失
- **High**: 核心功能无法使用
- **Medium**: 功能部分失效或性能问题
- **Low**: 边界情况或优化建议

### 3. 复现步骤
提供最小化的复现代码：

```zig
const std = @import("std");
const OrderBook = @import("core/orderbook.zig").OrderBook;

test "reproduce bug" {
    // 复现步骤
}
```

### 4. 预期/实际行为
- **预期行为**: 描述应该发生什么
- **实际行为**: 描述实际发生了什么

### 5. 环境信息
- Zig 版本: `zig version`
- 操作系统: Linux/macOS/Windows
- 订单簿版本: v0.2.0
- 相关配置或数据

---

## Bug 优先级定义

### Critical
- 系统崩溃（Panic/Segfault）
- 数据损坏或丢失
- 内存泄漏导致 OOM
- 安全漏洞

**处理时间**: 立即修复

### High
- 核心功能失效（无法更新订单簿）
- 计算结果错误（价格、深度、滑点）
- 性能严重劣化（>10x 预期）
- 线程安全问题

**处理时间**: 1-2 天

### Medium
- 边界情况处理不当
- 性能未达标（2-10x 预期）
- 错误处理不完善
- API 设计问题

**处理时间**: 1 周

### Low
- 代码优化建议
- 文档错误或遗漏
- 测试覆盖不足
- 非关键性能优化

**处理时间**: 下一个版本

---

## 潜在风险点

虽然尚未发现 Bug，但以下是已识别的潜在风险点：

### 1. 排序一致性
**描述**: 增量更新后可能导致订单簿排序不正确

**缓解措施**:
- 添加 `validate()` 函数检查排序
- 单元测试覆盖各种更新场景

### 2. 并发访问
**描述**: 多线程同时访问可能导致数据竞争

**缓解措施**:
- `OrderBookManager` 使用 `Mutex` 保护
- 建议使用 `OrderBookManager` 而非直接访问 `OrderBook`

### 3. 内存分配
**描述**: 频繁更新可能导致内存碎片

**缓解措施**:
- 使用 `clearRetainingCapacity()` 保留容量
- 支持 `initWithCapacity()` 预分配

### 4. Decimal 精度
**描述**: 价格计算可能存在精度问题

**缓解措施**:
- 使用 `Decimal` 类型而非浮点数
- 测试极大/极小价格边界

### 5. 序列号跳跃
**描述**: WebSocket 消息丢失可能导致订单簿不一致

**缓解措施**:
- 记录 `sequence` 字段
- 检测跳跃并重新同步快照（待实现）

---

## 测试覆盖

为降低 Bug 风险，已实现以下测试：

- ✅ 快照应用
- ✅ 增量更新
- ✅ 最优价格查询
- ✅ 深度和滑点计算
- ✅ 空订单簿处理
- ✅ 流动性不足处理
- ✅ 性能基准测试
- ✅ **WebSocket 集成测试** ✨ (v0.2.1)
- ✅ **内存泄漏检测** ✨ (v0.2.1)

待补充：
- [ ] 并发访问测试
- [ ] 大规模订单簿测试（1000+ 档）
- [ ] 模糊测试（Fuzz Testing）

---

*如有任何问题，请参考 [测试文档](./testing.md) 或联系维护者。*
