# CrashRecovery - 测试文档

> 测试覆盖和性能基准

**最后更新**: 2025-12-27

---

## 测试覆盖率

- **代码覆盖率**: 目标 > 85%
- **测试用例数**: 目标 15+

---

## 单元测试

```zig
test "Recovery: checkpoint and restore" {
    var rm = try RecoveryManager.init(allocator, config, ...);
    defer rm.deinit();

    // 设置状态
    account.equity = Decimal.fromFloat(100000);
    try positions.add(.{ .id = "pos-001", ... });

    // 创建检查点
    try rm.checkpoint();

    // 清除状态
    account.equity = Decimal.ZERO;
    positions.clear();

    // 恢复
    const result = try rm.recover();

    try std.testing.expectEqual(RecoveryStatus.success, result.status);
    try std.testing.expectApproxEqAbs(100000, account.equity.toFloat(), 1);
    try std.testing.expectEqual(@as(usize, 1), positions.count());
}

test "Recovery: no checkpoint" {
    var rm = try RecoveryManager.init(allocator, .{
        .checkpoint_dir = "./empty",
    }, ...);

    const result = try rm.recover();
    try std.testing.expectEqual(RecoveryStatus.no_checkpoint, result.status);
}

test "Recovery: checksum validation" {
    // 创建检查点
    try rm.checkpoint();

    // 损坏文件
    // ...

    // 恢复应该失败
    const result = rm.recover();
    try std.testing.expectError(error.ChecksumMismatch, result);
}
```

---

## 测试场景

### ✅ 已覆盖

- [x] 正常检查点和恢复
- [x] 无检查点处理
- [x] 校验和验证
- [x] 多检查点管理
- [x] 交易所同步

### 📋 待补充

- [ ] 大量仓位恢复
- [ ] 并发检查点测试
- [ ] 性能基准测试
