# Logger - Bug 追踪

> 已知问题、修复记录和解决方案

**最后更新**: 2025-01-22

---

## 当前已知问题

### 无重大问题

Logger 模块当前没有已知的重大 Bug。

---

## 潜在改进

### 1. JSON 字符串转义

**描述**: JSONWriter 未实现完整的字符串转义

**影响**:
- 包含 `"`, `\`, 换行符的字符串可能导致无效 JSON
- 示例: `log.info("含有\"引号", .{})` 输出错误

**解决方案**:
```zig
fn escapeJSON(s: []const u8, writer: anytype) !void {
    for (s) |c| {
        switch (c) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            else => try writer.writeByte(c),
        }
    }
}
```

**优先级**: 中

---

### 2. 异步日志

**描述**: 当前所有日志都是同步写入

**影响**:
- I/O 操作阻塞调用线程
- 高频日志影响性能

**解决方案**:
- 添加 `AsyncLogger` 使用后台线程
- 使用环形缓冲区

**优先级**: 中

---

### 3. 日志轮转时的原子性

**描述**: RotatingFileWriter 轮转时可能丢失日志

**影响**:
- 轮转期间的日志可能丢失
- 并发写入时可能出现竞态条件

**解决方案**:
- 使用临时文件原子重命名
- 加强锁保护

**优先级**: 低

---

## 边界情况

### 1. 空消息

```zig
try log.info("", .{});
```

**状态**: ✅ 正常工作

---

### 2. 超大消息

```zig
const huge_msg = "x" ** 1_000_000;
try log.info(huge_msg, .{});
```

**状态**: ⚠️ 可能内存不足

**建议**: 限制消息长度 < 10KB

---

### 3. 高频日志

```zig
while (true) {
    try log.info("High frequency", .{});
}
```

**状态**: ⚠️ 可能影响性能

**建议**: 使用日志采样或异步日志

---

## 测试清单

- [ ] 所有单元测试通过
- [ ] 基准测试达标
- [ ] 内存泄漏检查通过
- [ ] 并发压力测试通过
- [ ] 文件轮转测试通过

---

*Last updated: 2025-01-22*
