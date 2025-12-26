# TODO 审查报告

**审查时间**: 2025-12-26
**审查范围**: 整个 src/ 目录
**发现数量**: 9个TODO标记
**修复状态**: 4个已修复 ✅ | 5个保留到未来版本 📅
**测试结果**: 359/359 测试通过 ✅

---

## 📊 TODO 分类

### ✅ 已解决 (4个)

#### 1. ISO8601 时间戳解析 ✅ FIXED
- **文件**: `src/cli/commands/backtest.zig:292`
- **状态**: ✅ 已修复 (2025-12-26)
- **修复**: 使用 `Timestamp.fromISO8601(allocator, s)` 解析 ISO8601 格式
- **测试**: 通过 - parseTimestamp 函数现在支持 Unix 毫秒和 ISO8601 格式

#### 2. Msgpack测试数据 ✅ FIXED
- **文件**: `src/exchange/hyperliquid/auth.zig:360`
- **状态**: ✅ 已修复 (2025-12-26)
- **修复**:
  - 使用真实 msgpack.OrderRequest 结构
  - 使用 msgpack.packOrderAction() 编码
  - 移除 JSON placeholder
- **测试**: 通过 - "Signer: sign action" 测试使用真实 msgpack

#### 3. Cancel操作的Msgpack编码 ✅ FIXED
- **文件**: `src/exchange/hyperliquid/exchange_api.zig:307`
- **状态**: ✅ 已修复 (2025-12-26)
- **修复**:
  - CancelRequest 支持可选字段 (a: ?u64, o: ?u64)
  - 实现 msgpack.packCancelAction()
  - packCancel() 支持 null 值编码
  - cancelAllOrders() 使用 msgpack 代替 JSON
- **测试**: 通过 - 所有 cancel 操作现在使用 msgpack

#### 4. 签名Msgpack数据 ✅ FIXED
- **文件**: `src/exchange/hyperliquid/exchange_api.zig:313`
- **状态**: ✅ 已修复 (2025-12-26)
- **修复**:
  - placeOrder() 签名 msgpack 编码数据
  - cancelOrder() 签名 msgpack 编码数据
  - cancelAllOrders() 签名 msgpack 编码数据
- **测试**: 通过 - 所有签名操作使用 msgpack

---

### 📅 计划中的功能 (4个 - Phase D)

#### 5-8. Hyperliquid Connector 客户端初始化
- **文件**: `src/exchange/hyperliquid/connector.zig:181,184,201,204`
- **代码**:
  ```zig
  // TODO Phase D: Initialize HTTP client
  // TODO Phase D: Optionally initialize WebSocket client
  // TODO Phase D: Cleanup HTTP client
  // TODO Phase D: Cleanup WebSocket client if exists
  ```
- **优先级**: P3 - 低（计划功能）
- **说明**: Phase D的实盘交易功能，当前connector是stub
- **依赖**: Phase D开发计划
- **建议**: 保留，等待Phase D实施

---

### 🔮 依赖未来增强 (1个)

#### 9. Decimal NaN支持
- **文件**: `src/market/candles.zig:123`
- **代码**:
  ```zig
  v.* = Decimal.ZERO; // TODO: Use NaN when Decimal supports it
  ```
- **优先级**: P3 - 低
- **说明**: 当前使用ZERO表示未设置值，理想情况应使用NaN
- **依赖**: Decimal类型增强
- **建议**: 保留，等待Decimal支持NaN

---

## 🎯 行动计划总结

### ✅ 已完成 (2025-12-26)

1. **ISO8601时间戳解析** ✅ DONE
   - 文件: `src/cli/commands/backtest.zig:292`
   - 修复: 使用 `Timestamp.fromISO8601(allocator, s)`
   - 测试: 通过

2. **Msgpack完整实现** ✅ DONE
   - auth.zig 测试使用真实 msgpack 编码
   - exchange_api.zig cancel 操作使用 msgpack
   - msgpack.CancelRequest 支持可选字段
   - Encoder 添加 writeNull() 方法
   - 测试: 所有 359 测试通过

### 📅 保留 (未来版本)

3. **Phase D相关TODO** - 等待实盘交易开发 (v0.5.0+)
4. **Decimal NaN** - 等待类型系统增强 (v0.6.0+)

---

## 📝 修复详情

### Msgpack 增强 (2025-12-26)

#### 新增功能:
- `Encoder.writeNull()` - 编码 MessagePack null 值 (0xc0)
- `CancelRequest` 可选字段 - 支持 "cancel all" 操作
- `packCancel()` null 值处理 - 正确编码可选字段

#### 修复文件:
1. `src/exchange/hyperliquid/msgpack.zig` (+25 行)
   - 添加 writeNull() 方法
   - CancelRequest.a 改为 ?u64
   - CancelRequest.o 改为 ?u64
   - packCancel() 支持 null 值

2. `src/cli/commands/backtest.zig` (~10 行)
   - parseTimestamp() 添加 allocator 参数
   - 调用 Timestamp.fromISO8601() 解析 ISO 格式
   - 更新所有调用点

3. `src/exchange/hyperliquid/auth.zig` (~5 行)
   - 测试使用真实 msgpack.OrderRequest
   - 使用 msgpack.packOrderAction()
   - 移除 JSON placeholder

4. `src/exchange/hyperliquid/exchange_api.zig` (~30 行)
   - cancelAllOrders() 使用 msgpack 编码
   - 正确处理可选 asset_index
   - 签名 msgpack 数据而非 JSON

#### 测试结果:
- ✅ 359/359 测试通过
- ✅ 零编译错误
- ✅ 零内存泄漏

---

## 总结

- **总计**: 9个TODO标记
- **已解决**: 4个 ✅
- **保留功能**: 4个（Phase D）
- **依赖增强**: 1个（Decimal NaN）

**成果**:
✅ 所有当前阶段可解决的 TODO 已完成
✅ Msgpack 模块功能完整
✅ 所有测试通过
📅 剩余 TODO 记录到未来版本计划
