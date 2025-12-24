# Order Manager - 变更日志

> 版本历史和更新记录

**最后更新**: 2025-12-24

---

## [0.1.0] - 2025-12-24

### Added

- ✨ **OrderStore 核心实现**
  - 双索引机制（client_order_id + exchange_order_id）
  - 订单自动分类（active vs history）
  - 高效查询方法（O(1) 复杂度）
  - 自动内存管理（Order 对象和字符串）
  - 支持按交易对过滤历史订单
  - 自动维护索引一致性

- ✨ **OrderManager 核心实现**
  - 订单提交（`submitOrder`）
    - 自动生成 client_order_id（timestamp-{counter} 格式）
    - 参数验证（limit 订单必须有价格）
    - 订单预存储（提交前）
    - 交易所响应同步
  - 订单取消（`cancelOrder`, `cancelAllOrders`）
    - 单个订单取消
    - 批量取消（按交易对或全部）
    - 状态检查（只能取消活跃订单）
  - 状态查询（`getActiveOrders`, `getOrderHistory`）
    - 获取所有活跃订单
    - 历史订单查询（可按交易对过滤、支持分页）
  - 状态刷新（`refreshOrderStatus`）
    - 主动查询交易所
    - 本地状态更新
    - 回调通知

- ✨ **WebSocket 实时事件处理**
  - 新增统一事件类型（`OrderUpdateEvent`, `OrderFillEvent`）
  - 订单状态更新处理（`handleOrderUpdate`）
    - 自动更新订单状态、成交量、均价
    - 状态驱动的订单分类（活跃 → 历史）
    - 触发 `on_order_update` 回调
    - 完全成交时触发 `on_order_fill` 回调
  - 成交事件处理（`handleOrderFill`）
    - 成交量累计
    - 加权平均成交价计算
    - 自动状态转换（partially_filled / filled）
    - 触发回调通知

- ✨ **线程安全保障**
  - 所有公开方法使用 `std.Thread.Mutex` 保护
  - client_order_id 生成器使用原子计数器
  - 支持多线程并发访问

- ✨ **回调机制**
  - `on_order_update`: 订单状态变化通知
  - `on_order_fill`: 订单完全成交通知
  - 用户可自定义回调处理逻辑

### Changed

- 🔧 **Order 类型更新**
  - `exchange_order_id` 改为可选类型（`?u64`）
    - 提交前为 null
    - 交易所确认后才有值
  - 字段名统一：`average_price` → `avg_fill_price`

### Architecture

- 📐 **交易所抽象设计**
  - OrderManager 基于 IExchange 接口（交易所无关）
  - 使用统一的数据类型（exchange/types.zig）
  - WebSocket 事件通过统一事件类型传递
  - 易于扩展新交易所

- 📐 **事件驱动架构**
  - 订单状态自动同步（REST + WebSocket）
  - 回调机制解耦业务逻辑
  - 状态驱动的订单生命周期管理

### Tests

- ✅ **OrderStore 单元测试**
  - init and deinit（资源管理）
  - add and retrieve by client ID（双索引验证）
  - 所有测试通过，无内存泄漏

- ✅ **OrderManager 单元测试**
  - init and deinit（资源管理）
  - handleOrderUpdate（状态更新、索引维护）
  - handleOrderFill（成交处理、加权平均价）
  - 所有测试通过，156/156

### Fixed

- 🐛 修复 OrderStore.add() 未建立 exchange_order_id 索引的问题
- 🐛 修复 OrderStore.deinit() 未释放 Order 对象的内存泄漏
- 🐛 修复 OrderStatus enum 引用不存在的 `.expired` 状态

---

## 版本规范

遵循 [语义化版本](https://semver.org/lang/zh-CN/)：

- **MAJOR**: 不兼容的 API 变更
- **MINOR**: 向后兼容的功能新增
- **PATCH**: 向后兼容的 Bug 修复
