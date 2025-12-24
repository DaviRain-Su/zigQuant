# Position Tracker - 变更日志

> 版本历史和更新记录

**最后更新**: 2025-12-24

---

## [0.1.0] - 2025-12-24

### Added

- ✨ **Position 数据结构完整实现**
  - 基于 Hyperliquid API 规范的 szi（有符号仓位大小）
  - 杠杆和保证金管理
  - 未实现盈亏计算（基于标记价格）
  - 已实现盈亏累计
  - 资金费率追踪（cumFunding）
  - 仓位操作方法：
    - `increase()` - 开仓/加仓（自动计算平均价格）
    - `decrease()` - 减仓/平仓（返回已实现盈亏）
    - `updateMarkPrice()` - 更新标记价格和未实现盈亏
  - 辅助方法：
    - `isEmpty()` - 检查是否空仓
    - `getTotalPnl()` - 获取总盈亏
    - `getAbsSize()` - 获取绝对仓位大小

- ✨ **Account 数据结构完整实现**
  - 基于 Hyperliquid API 规范的账户字段
  - 保证金摘要（marginSummary, crossMarginSummary）
  - 可提现金额（withdrawable）
  - 已实现盈亏追踪（本地累计）
  - 辅助方法：
    - `getAccountValue()` - 获取账户总价值
    - `getAvailableMargin()` - 获取可用保证金
    - `getMarginUsageRate()` - 获取保证金使用率

- ✨ **PositionTracker 完整实现**
  - 多币种仓位管理（StringHashMap）
  - 账户状态同步（`syncAccountState()`）
    - 从交易所获取仓位列表
    - 从交易所获取账户余额
    - 自动更新本地仓位数据
  - 订单成交处理（`handleOrderFill()`）
    - 自动判断开仓/平仓
    - 计算 szi 变化
    - 更新已实现盈亏
    - 完全平仓时自动清理
  - 标记价格更新（`updateMarkPrice()`）
    - 实时更新未实现盈亏
    - 触发仓位更新回调
  - 查询方法：
    - `getAllPositions()` - 获取所有仓位
    - `getPosition()` - 获取单个仓位
    - `getAccount()` - 获取账户信息
    - `getStats()` - 获取统计信息

- ✨ **回调机制**
  - `on_position_update`: 仓位更新通知
  - `on_account_update`: 账户更新通知

- ✨ **线程安全保障**
  - 所有公开方法使用 `std.Thread.Mutex` 保护
  - 支持多线程并发访问

### Architecture

- 📐 **交易所抽象设计**
  - PositionTracker 基于 IExchange 接口（交易所无关）
  - 使用统一的 Position 和 Balance 类型
  - 易于扩展新交易所

- 📐 **数据模型**
  - trading/position.zig: 完整的仓位数据（包含 Hyperliquid 特定字段）
  - exchange/types.zig: 简化的 Position 类型（接口返回）
  - 两者可以互相转换

### Tests

- ✅ **Position 单元测试**
  - init and deinit
  - increase (open and add)
  - decrease (close)
  - unrealized PnL calculation
  - 所有测试通过

- ✅ **Account 单元测试**
  - init
  - updateFromApiResponse
  - getAvailableMargin
  - getMarginUsageRate
  - 所有测试通过

- ✅ **PositionTracker 单元测试**
  - init and deinit
  - 所有测试通过，165/165

### Fixed

- ✅ 正确处理有符号仓位大小（szi）
- ✅ 平均价格计算（加仓时）
- ✅ 已实现盈亏计算（多头和空头）
- ✅ 内存管理（Position 对象和字符串）

---

## 版本规范

遵循 [语义化版本](https://semver.org/lang/zh-CN/)：

- **MAJOR**: 不兼容的 API 变更
- **MINOR**: 向后兼容的功能新增
- **PATCH**: 向后兼容的 Bug 修复
