# Exchange Router - Bug 追踪

> 已知问题和修复记录

**最后更新**: 2025-12-24

---

## 当前状态

**开发阶段**: ✅ 核心组件已实现 (Phase A-C 完成)

**已知 Bug 数量**: 0

**说明**: Exchange Router 核心组件 (types, interface, registry, symbol_mapper, connector) 已实现并通过测试。Phase D (HTTP/WebSocket 集成) 正在进行中。

---

## Bug 追踪流程

### 报告 Bug

当发现 Bug 时，请按以下格式报告：

**必需信息**:
1. **标题**: 简短描述问题
2. **严重性**: Critical | High | Medium | Low
3. **组件**: types | interface | registry | connector | symbol_mapper
4. **复现步骤**: 详细的复现方法
5. **预期行为**: 应该如何工作
6. **实际行为**: 实际发生了什么
7. **环境**: Zig 版本、操作系统、测试环境（testnet/mainnet）

**可选信息**:
- 错误日志
- 最小复现代码
- 截图或录屏

---

## 已知 Bug

（当前无已知 Bug）

---

## 已修复的 Bug

（当前无已修复的 Bug）

---

## 潜在风险和注意事项

### 实现过程中识别的潜在问题

以下是在实现过程中需要特别注意的问题点：

#### 1. 符号映射歧义

**风险**: Medium
**组件**: symbol_mapper
**描述**:
不同交易所对同一资产可能使用不同符号。例如：
- Hyperliquid: "ETH" (永续合约，USDC 结算)
- Binance: "ETHUSDT" (现货), "ETH-PERP" (永续合约)
- OKX: "ETH-USDT" (现货), "ETH-USDT-SWAP" (永续合约)

**缓解措施** (已实现):
- ✅ SymbolMapper 已实现 Hyperliquid, Binance, OKX 格式转换
- ✅ 每个交易所有独立的转换函数
- ✅ 通过 ExchangeType 枚举区分交易所
- 🚧 待添加: 市场类型字段 (spot vs perpetual) - 未来扩展

#### 2. 订单状态映射不一致

**风险**: Medium
**组件**: types
**描述**:
不同交易所的订单状态定义可能不同：
- Hyperliquid: "resting", "filled"
- Binance: "NEW", "PARTIALLY_FILLED", "FILLED", "CANCELED"
- 需要统一映射到 OrderStatus 枚举

**缓解措施** (已实现):
- ✅ 已定义统一的 OrderStatus 枚举: pending, open, filled, partially_filled, cancelled, rejected
- ✅ 每个 OrderStatus 提供 toString/fromString 方法
- 🚧 待实现: Hyperliquid Connector 中的状态映射逻辑

#### 3. 精度丢失

**风险**: High
**组件**: types (Decimal)
**描述**:
价格和数量在不同交易所的精度要求不同：
- Hyperliquid: szDecimals 定义每个币种的精度
- 需要确保 Decimal 类型能保持足够精度

**缓解措施** (已实现):
- ✅ 所有价格和数量字段使用 Decimal 类型
- ✅ Decimal 提供精确的十进制运算
- ✅ 避免浮点数运算和精度损失
- 🚧 待实现: 在 Connector 中验证交易所精度要求

#### 4. 时区和时间戳问题

**风险**: Low
**组件**: types (Timestamp)
**描述**:
不同交易所可能使用不同的时间戳格式：
- UTC 时间戳（毫秒）
- UTC 时间戳（微秒）
- 本地时区字符串

**缓解措施**:
- 统一使用 UTC 毫秒时间戳（Timestamp）
- Connector 负责转换
- 时间比较使用 Timestamp 的方法

#### 5. VTable 指针生命周期

**风险**: High
**组件**: interface
**描述**:
VTable 模式使用 `*anyopaque` 指针，如果底层对象被释放而接口仍在使用，会导致悬空指针。

**缓解措施** (已实现):
- ✅ Connector 由 Registry 管理生命周期
- ✅ HyperliquidConnector.create() 返回堆分配的指针
- ✅ HyperliquidConnector.destroy() 负责清理资源
- ✅ Registry.deinit() 自动断开所有连接
- ✅ 文档明确说明所有权规则
- 🚧 待考虑: Arc (Atomic Reference Counting) 用于并发场景

#### 6. 并发访问安全

**风险**: Medium
**组件**: registry, connector
**描述**:
如果多个线程同时访问同一个 Exchange，可能导致竞态条件。

**缓解措施**:
- MVP 阶段不支持并发访问（文档明确说明）
- 未来使用互斥锁或原子操作
- HTTP 客户端本身需要线程安全

---

## 性能问题追踪

### 潜在性能瓶颈

#### 1. 符号转换开销

**描述**: 每次 API 调用都需要符号转换
**影响**: 每次调用增加 ~100ns 开销
**优化方案**:
- 使用 HashMap 缓存常用符号映射
- 考虑在 Connector 初始化时预加载所有符号

#### 2. JSON 序列化/反序列化

**描述**: HTTP API 需要频繁序列化和反序列化 JSON
**影响**: 每次 API 调用增加 ~1-10ms 开销
**优化方案**:
- 使用流式 JSON 解析（std.json.Scanner）
- 考虑使用 MessagePack（Hyperliquid 支持）
- 重用 JSON 解析器

#### 3. 内存分配

**描述**: 每次 API 调用分配临时缓冲区
**影响**: 频繁的 allocate/free 调用
**优化方案**:
- 使用 ArenaAllocator
- 重用缓冲区（buffer pool）
- 栈分配小缓冲区

---

## 测试发现的问题（待实施后更新）

此部分将在测试实施后填充：

```markdown
### 测试类别 1

- [ ] 问题 1
- [ ] 问题 2

### 测试类别 2

- [ ] 问题 3
```

---

## Bug 优先级定义

### Critical（严重）
- 导致程序崩溃
- 数据丢失或损坏
- 资金安全问题
- 无法下单或撤单

**处理**: 立即修复，阻塞发布

### High（高）
- 核心功能无法使用
- 严重性能问题
- 内存泄漏
- 订单状态错误

**处理**: 优先修复，本版本内解决

### Medium（中）
- 次要功能问题
- 轻微性能问题
- 不影响核心流程的错误

**处理**: 计划修复，可能延后到下一版本

### Low（低）
- 文档错误
- 日志格式问题
- 非关键边界情况

**处理**: 有时间时修复

---

## Bug 修复流程

1. **确认**: 复现 Bug，确认严重性
2. **分析**: 定位根本原因
3. **修复**: 实现修复方案
4. **测试**: 编写测试用例，确保不会重现
5. **审查**: 代码审查
6. **文档**: 更新 changelog 和本文档
7. **关闭**: 标记为已修复

---

## 回归测试

修复每个 Bug 后，应添加回归测试防止重现：

```zig
test "regression: Bug #X - description" {
    // 复现场景
    // 验证修复
}
```

---

## 联系方式

**报告 Bug**:
- GitHub Issues: (待添加仓库链接)
- 邮件: (待添加)

**紧急问题**:
- 对于 Critical 级别的 Bug，请直接联系维护者

---

## Bug 统计（实施后更新）

| 月份 | 新增 | 修复 | 未修复 |
|------|------|------|--------|
| 2025-12 | 0 | 0 | 0 |

---

## 相关文档

- [测试文档](./testing.md) - 测试策略和用例
- [实现细节](./implementation.md) - 实现细节和设计决策
- [变更日志](./changelog.md) - 版本历史

---

*Last updated: 2025-12-23*
