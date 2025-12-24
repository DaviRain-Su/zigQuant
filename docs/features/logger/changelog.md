# Logger - 变更日志

> 版本历史和更新记录

**最后更新**: 2025-12-24

---

## [0.1.2] - 2025-12-24

### Added

- ✨ **双模式日志**: Logger 现在支持自动检测参数类型，提供两种日志模式
  - **结构化模式**：当 `fields` 为 struct（非 tuple）时，使用键值对结构化日志
  - **Printf 模式**：当 `fields` 为 tuple 时，使用 printf 风格格式化
  - 编译时自动检测，零运行时开销
- ✨ **灵活的使用方式**: 同一应用中可根据场景混合使用两种模式

### Fixed

- 🐛 **Bug #6: Logger format issue** - 修复了日志格式化问题，现在支持 printf 风格和结构化两种模式

### Technical Details

- 实现位置：`src/core/logger.zig` lines 150-174
- 检测逻辑：使用 `@typeInfo(FieldsType).@"struct".is_tuple` 判断是否为 tuple
- Printf 模式：使用 `std.fmt.allocPrint(allocator, msg, fields)` 格式化消息
- 结构化模式：保持消息不变，将字段转换为 `Field` 数组
- 零性能损失：类型检测在编译时完成

### Usage Examples

```zig
// Printf 模式（tuple）
try log.info("User {} logged in from {s}", .{user_id, ip_address});
// 输出: [info] 1737541845000 User 456 logged in from 192.168.1.1

// 结构化模式（struct）
try log.info("User login", .{
    .user_id = 456,
    .ip = "192.168.1.1",
});
// 输出: [info] 1737541845000 User login user_id=456 ip=192.168.1.1
```

---

## [0.1.1] - 2025-01-24

### Added

- ✨ **彩色日志输出**: 新增 `AnsiColors` 结构体，包含完整的 ANSI 颜色代码
- ✨ **颜色级别映射**: 每个日志级别使用不同颜色（TRACE=灰色, DEBUG=青色, INFO=绿色, WARN=黄色, ERROR=红色, FATAL=粗体红色）
- ✨ **`initWithColors()` 方法**: ConsoleWriter 新增 `initWithColors(allocator, writer, use_colors)` 方法，显式控制彩色输出
- ✨ **整行彩色**: 整个日志行应用颜色（包括时间戳、消息和字段），不仅仅是级别标签
- ✨ **默认启用彩色**: ConsoleWriter 默认启用彩色输出，可通过 `initWithColors()` 禁用

### Changed

- 🔄 **泛型 ConsoleWriter**: `ConsoleWriter` 改为泛型函数 `ConsoleWriter(WriterType)`，支持不同类型的底层 Writer
- 🔄 **泛型 JSONWriter**: `JSONWriter` 改为泛型函数 `JSONWriter(WriterType)`
- 🔄 **API 更新**: 使用 `std.fs.File.stdout()` 和 `std.fs.File.stderr()` 替代已废弃的 `std.io.getStdOut()` 和 `std.io.getStdErr()`
- 🔄 **Zig 0.15.2 兼容**: 所有代码和示例更新为 Zig 0.15.2 语法

### Technical Details

- `AnsiColors.forLevel()` 根据日志级别返回相应的 ANSI 颜色代码
- ConsoleWriter 的 `use_colors` 字段控制是否应用颜色（默认 `true`）
- 颜色在行首应用，在行尾重置（`RESET`）
- 支持 TTY 检测以自动启用/禁用彩色（参见 usage-guide.md）

---

## [0.1.0] - 2025-01-23

### Added

- ✨ 初始版本发布
- ✨ 6 个日志级别：trace, debug, info, warn, error, fatal
- ✨ 结构化日志支持（键值对字段）
- ✨ `Logger` 核心类型
- ✨ `LogWriter` 接口（vtable 模式）
- ✨ `ConsoleWriter`: 控制台输出
- ✨ `FileWriter`: 文件输出
- ✨ `JSONWriter`: JSON 格式输出
- ✨ `StdLogWriter`: std.log 桥接，集成标准库日志
- ✨ 日志级别过滤（零分配快速路径）
- ✨ 编译时字段转换
- ✨ 支持 comptime_int、comptime_float
- ✨ 支持字符串字面量（`*const [N:0]u8`）
- ✨ 线程安全（Mutex 保护）
- ✨ 完整的单元测试覆盖（8 个测试）

### Technical Details

- 使用 vtable 模式实现可扩展 Writer
- 编译时类型推导和字段转换
- 级别过滤提前返回，避免不必要分配
- 所有 Writer 使用 Mutex 保证线程安全
- StdLogWriter 使用全局单例模式，支持 scope 字段
- 使用 Zig 0.15 语法（`.@"struct"`、`.@"int"` 等）
- 时间戳使用 `std.time.milliTimestamp()`

---

## [Unreleased]

### Planned

- [ ] `RotatingFileWriter`: 自动轮转文件输出
- [ ] 异步日志（后台线程）
- [ ] JSON 字符串完整转义
- [ ] 日志采样（高频场景）
- [ ] 日志压缩（gzip）
- [ ] 远程日志（HTTP/gRPC）
- [ ] 日志聚合（多个 Logger）
- [ ] 结构化查询
- [ ] 日志归档策略

---

## 版本规范

遵循 [语义化版本](https://semver.org/lang/zh-CN/)

---

*Last updated: 2025-12-24*
