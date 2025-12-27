# SQLite Storage Bug 追踪

> 数据持久化模块的已知问题和潜在风险

**版本**: v0.7.0
**状态**: 📋 待开发
**最后更新**: 2025-12-27

---

## 当前状态

```
开放 Bug: 0
已修复: 0
待验证: 0
```

---

## 潜在问题

开发前识别的潜在风险点:

### P-001: WAL 文件清理

**风险等级**: 低

**描述**: WAL 模式下可能产生较大的 WAL 文件，需要定期 checkpoint。

**预防措施**:
```zig
// 定期执行 checkpoint
try db.exec("PRAGMA wal_checkpoint(TRUNCATE)");
```

### P-002: 并发写入冲突

**风险等级**: 中

**描述**: SQLite 写操作是串行的，高并发写入可能造成 SQLITE_BUSY。

**预防措施**:
- 使用连接池
- 实现重试逻辑
- 批量写入减少事务数

```zig
fn executeWithRetry(db: *Db, sql: []const u8, max_retries: u32) !void {
    var retries: u32 = 0;
    while (retries < max_retries) : (retries += 1) {
        db.exec(sql) catch |err| {
            if (err == error.Busy) {
                std.time.sleep(10_000_000); // 10ms
                continue;
            }
            return err;
        };
        return;
    }
    return error.MaxRetriesExceeded;
}
```

### P-003: Decimal 解析失败

**风险等级**: 中

**描述**: 从数据库读取的字符串可能无法解析为 Decimal。

**预防措施**:
- 写入时验证 Decimal 格式
- 读取时使用 try 处理错误
- 记录解析失败的数据

### P-004: 磁盘空间不足

**风险等级**: 低

**描述**: 大量数据可能耗尽磁盘空间。

**预防措施**:
- 定期清理旧数据
- 监控数据库大小
- 提供数据保留策略配置

### P-005: 缓存内存泄漏

**风险等级**: 中

**描述**: LRU 缓存可能因引用计数问题导致内存泄漏。

**预防措施**:
- 使用 defer 确保释放
- 定期验证缓存大小
- 提供手动清理接口

### P-006: Schema 迁移失败

**风险等级**: 高

**描述**: Schema 升级过程中断可能导致数据库损坏。

**预防措施**:
- 迁移前备份数据库
- 使用事务包装迁移
- 保留回滚脚本

---

## Bug 模板

```markdown
### BUG-XXX: [简短描述]

**状态**: 🔴 开放 | 🟡 进行中 | 🟢 已修复
**优先级**: P0 | P1 | P2
**发现版本**: v0.7.0
**修复版本**: -

**描述**:
[详细描述问题]

**复现步骤**:
1. 步骤 1
2. 步骤 2
3. 预期结果 vs 实际结果

**根因分析**:
[分析原因]

**修复方案**:
[描述修复]

**测试验证**:
- [ ] 单元测试
- [ ] 集成测试
- [ ] 手动验证

**相关代码**:
- `src/storage/data_store.zig:XXX`
```

---

## 修复历史

暂无修复记录。

---

*Last updated: 2025-12-27*
