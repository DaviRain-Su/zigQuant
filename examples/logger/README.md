# Logger 示例

本目录包含 zigQuant Logger 模块的使用示例。

## 📋 示例列表

### 1. `basic_usage.zig` - 基本使用

展示 Logger 的基本功能：
- ✅ ConsoleWriter - 控制台输出
- ✅ JSONWriter - JSON 格式输出
- ✅ FileWriter - 文件输出
- ✅ 日志级别过滤

**运行**:
```bash
zig build-exe basic_usage.zig --dep zigQuant -MzigQuant=../../src/root.zig
./basic_usage
```

或使用项目构建系统（如果已配置）。

---

### 2. `std_log_bridge.zig` - std.log 桥接

展示如何使用 StdLogWriter 将 `std.log` 调用路由到自定义 Logger：
- ✅ 配置 `std_options.logFn`
- ✅ Scoped logging 支持
- ✅ 格式化参数支持

**运行**:
```bash
zig build-exe std_log_bridge.zig --dep zigQuant -MzigQuant=../../src/root.zig
./std_log_bridge
```

---

## 🔑 关键要点

### Zig 0.15 正确的 stdout/stderr 使用方式

```zig
// ✅ 正确
var stderr_buffer: [4096]u8 = undefined;
var stderr_writer = std.fs.File.stderr().writer(&stderr_buffer);
var console = ConsoleWriter.init(&stderr_writer.interface);

// ❌ 错误 - 这些 API 不存在
var console = ConsoleWriter.init(std.io.getStdErr().writer().any());
```

### 缓冲区大小建议

- 一般日志：4096 字节 (4KB)
- 高频日志：8192-16384 字节

---

## 📚 相关文档

- [使用指南](../../docs/features/logger/usage-guide.md) - 详细的使用说明
- [API 参考](../../docs/features/logger/api.md) - 完整的 API 文档
- [StdLogWriter 桥接](../../docs/features/logger/std-log-bridge.md) - std.log 集成指南
- [实现细节](../../docs/features/logger/implementation.md) - 内部实现说明

---

## 💡 提示

1. **选择合适的 Writer**:
   - 开发调试：ConsoleWriter
   - 生产环境：FileWriter + JSONWriter
   - 日志分析：JSONWriter

2. **设置合适的日志级别**:
   - 开发：`.debug` 或 `.trace`
   - 生产：`.info` 或 `.warn`
   - 性能关键：`.warn` 或 `.err`

3. **结构化字段**:
   - 使用键值对而不是格式化字符串
   - 便于日志解析和查询

---

*Last updated: 2025-01-23*
