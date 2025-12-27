# CrashRecovery - 崩溃恢复机制

> 确保系统在崩溃后能快速恢复状态

**状态**: 📋 待开始
**版本**: v0.8.0
**Story**: [STORY-045](../../stories/v0.8.0/STORY_045_CRASH_RECOVERY.md)
**最后更新**: 2025-12-27

---

## 📋 概述

CrashRecovery 模块实现崩溃恢复机制，通过定期检查点确保系统在意外崩溃后能够快速恢复状态，避免订单丢失和仓位不一致。

### 核心特性

- ✅ **状态持久化**: 定期保存关键状态到磁盘
- ✅ **快速恢复**: 从检查点快速重建状态
- ✅ **数据完整性**: 校验和验证确保数据正确
- ✅ **交易所同步**: 恢复后与交易所状态对账
- ✅ **孤立订单处理**: 自动取消遗留订单

---

## 🚀 快速开始

```zig
const recovery = @import("zigQuant").recovery;

// 创建恢复管理器
var rm = try recovery.RecoveryManager.init(
    allocator,
    .{
        .checkpoint_dir = "./checkpoints",
        .checkpoint_interval_ms = 60000,
        .auto_recover = true,
        .sync_with_exchange = true,
    },
    &execution,
    &positions,
    &account,
);
defer rm.deinit();

// 启动时自动恢复
if (try rm.autoRecover()) |result| {
    std.debug.print("Recovered from {d}\n", .{result.checkpoint_time});
}

// 启动定期检查点
rm.startPeriodicCheckpoint();

// 交易后创建检查点
try rm.checkpointOnTrade();
```

---

## 📚 相关文档

- [API 参考](./api.md)
- [实现细节](./implementation.md)
- [测试文档](./testing.md)
- [Bug 追踪](./bugs.md)
- [变更日志](./changelog.md)

---

## 🔧 核心 API

```zig
pub const RecoveryManager = struct {
    pub fn init(allocator: Allocator, config: RecoveryConfig, ...) !RecoveryManager;
    pub fn checkpoint(self: *Self) !void;
    pub fn checkpointOnTrade(self: *Self) !void;
    pub fn recover(self: *Self) !RecoveryResult;
    pub fn autoRecover(self: *Self) !?RecoveryResult;
    pub fn syncWithExchange(self: *Self) !SyncResult;
    pub fn startPeriodicCheckpoint(self: *Self) void;
    pub fn getStats(self: *Self) RecoveryStats;
};
```

---

## 📊 检查点内容

| 数据 | 说明 |
|------|------|
| 账户状态 | 权益、余额、保证金 |
| 仓位信息 | 所有活跃仓位 |
| 未完成订单 | 所有 pending 订单 |
| 策略状态 | 策略自定义状态 |
| 时间戳 | 检查点创建时间 |
| 校验和 | CRC32 验证 |

---

## 📝 恢复流程

1. **加载检查点**: 读取最新的检查点文件
2. **验证完整性**: 校验 CRC32
3. **恢复账户**: 重建账户状态
4. **恢复仓位**: 重建仓位信息
5. **恢复订单**: 重建未完成订单
6. **交易所同步**: 与交易所对账
7. **处理差异**: 取消孤立订单，更新仓位

---

*Last updated: 2025-12-27*
