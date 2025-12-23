# Zig 0.15.2 快速参考指南

> 本文档提供 zigQuant 项目从旧版本 Zig 升级到 0.15.2 时的关键 API 变更和常见陷阱。

## 🔥 关键变更一览

| 类别 | 旧版本 API | Zig 0.15.2 API | 影响模块 |
|------|-----------|----------------|---------|
| File I/O | `std.io.getStdOut().writer()` | `std.fs.File.stdout().writer(&buffer)` | Logger |
| ArrayList | `ArrayList.init(allocator)` | `ArrayList.initCapacity(allocator, size)` | Logger, Config |
| ArrayList | `list.deinit()` | `list.deinit(allocator)` | Logger, Config |
| ArrayList | `list.append(item)` | `list.append(allocator, item)` | Logger, Config |
| ArrayList | `list.writer()` | `list.writer(allocator)` | Logger |

## 📌 File I/O 写入器模式

### ⚠️ BufferedWriter 陷阱（常见问题）

**现象：** 代码编译运行正常，但看不到任何 stdout/stderr 输出

**原因：**
```zig
// ❌ 错误：数据写入缓冲区但未刷新
var stderr_buffer: [4096]u8 = undefined;
const stderr_writer = std.fs.File.stderr().writer(&stderr_buffer);
// 数据留在 stderr_buffer 中，不会显示在终端
```

### 标准输出/错误写入（正确方式）

```zig
// ✅ 方式 1：直接使用 File（推荐，最简单）
const stderr = std.fs.File.stderr();
_ = try stderr.writeAll(data);

// ✅ 方式 2：在泛型 Logger 中使用
const ConsoleWriterType = ConsoleWriter(std.fs.File);
var console = ConsoleWriterType.init(allocator, std.fs.File.stderr());

// ⚠️ 方式 3：BufferedWriter（不推荐，需要手动刷新）
var stderr_buffer: [4096]u8 = undefined;
const stderr_writer = std.fs.File.stderr().writer(&stderr_buffer);
// 对于 File.Writer，通过 .interface 访问方法
try stderr_writer.interface.writeAll(data);
// 但问题是：Zig 0.15.2 的 File.Writer 没有 flush() 方法！

// ❌ 旧版本用法（不再有效）
const stderr = std.io.getStdErr();
const writer = stderr.writer();
try writer.writeAll(data);
```

### 泛型 Writer 处理不同类型

```zig
pub fn MyWriter(comptime WriterType: type) type {
    return struct {
        underlying_writer: WriterType,

        fn write(self: *@This(), data: []const u8) !void {
            // 编译时检查 writer 类型
            if (@hasField(WriterType, "interface")) {
                // File.Writer 类型（有 .interface 字段）
                try self.underlying_writer.interface.writeAll(data);
            } else {
                // GenericWriter 类型（直接有方法）
                try self.underlying_writer.writeAll(data);
            }
        }
    };
}

// 使用
const WriterType = @TypeOf(some_writer);
var my_writer = MyWriter(WriterType).init(some_writer);
```

## 📌 ArrayList 完整用法

```zig
// 初始化
var list = try std.ArrayList(u8).initCapacity(allocator, 256);
defer list.deinit(allocator);  // ⚠️ 必须传 allocator

// 添加元素
try list.append(allocator, 'x');  // ⚠️ 必须传 allocator

// 获取 writer
const writer = list.writer(allocator);  // ⚠️ 必须传 allocator
try writer.writeAll("hello");

// 访问数据
const items = list.items;
```

## 📌 避免指针生命周期陷阱

### ❌ 错误：指向栈变量的指针

```zig
pub fn init(underlying: anytype) Self {
    return .{
        .ptr = @constCast(&underlying),  // 💥 underlying 在函数返回后失效
    };
}
```

### ✅ 正确：存储值本身

```zig
pub fn init(underlying: WriterType) Self {
    return .{
        .value = underlying,  // ✅ 存储副本
    };
}
```

### ✅ 正确：使用泛型类型

```zig
pub fn MyStruct(comptime T: type) type {
    return struct {
        value: T,  // ✅ 类型参数化，存储值

        pub fn init(v: T) @This() {
            return .{ .value = v };
        }
    };
}

// 使用
const MyInt = MyStruct(i32).init(42);
```

## 📌 常见编译错误速查

### "代码正常但日志不显示"（运行时问题）

**症状：**
- ✅ 代码编译通过
- ✅ 程序运行无报错
- ❌ 但 stdout/stderr 没有任何输出

**诊断方法：**
```zig
// 添加 debug 打印测试
std.debug.print("Before log\n", .{});
try log.info("Test message", .{});
std.debug.print("After log\n", .{});

// 如果两个 debug.print 都显示，但中间的 log.info 不显示
// → BufferedWriter 问题
```

**原因：** 使用了 `file.writer(&buffer)` 但数据未刷新

**解决：**
```zig
// ❌ 问题代码
var buf: [4096]u8 = undefined;
const w = std.fs.File.stderr().writer(&buf);
var console = ConsoleWriter(@TypeOf(w)).init(allocator, w);

// ✅ 修复代码
const ConsoleType = ConsoleWriter(std.fs.File);
var console = ConsoleType.init(allocator, std.fs.File.stderr());
```

### "no field or member function named 'writeAll'"

**原因：** File.Writer 的方法在 `.interface` 字段中

**解决：**
```zig
// ❌
try file_writer.writeAll(data);

// ✅
try file_writer.interface.writeAll(data);
```

### "no field named 'interface'"

**原因：** 不是所有 writer 都有 `.interface` 字段（如 GenericWriter）

**解决：** 使用编译时检查
```zig
if (@hasField(WriterType, "interface")) {
    try writer.interface.writeAll(data);
} else {
    try writer.writeAll(data);
}
```

### "member function expected N argument(s), found M"

**原因：** ArrayList 方法现在需要传 allocator

**解决：**
```zig
// ❌
defer list.deinit();
try list.append(item);

// ✅
defer list.deinit(allocator);
try list.append(allocator, item);
```

### "General protection exception"

**原因：** 访问了已失效的栈指针

**排查：**
1. 检查是否有 `&parameter` 这样的代码
2. 检查 vtable 或闭包是否捕获了局部变量
3. 使用泛型类型替代 anytype + 指针

## 📌 调试技巧

### 1. 打印类型信息

```zig
const T = @TypeOf(some_value);
@compileError("Type: " ++ @typeName(T));
```

### 2. 检查字段存在性

```zig
comptime {
    if (@hasField(SomeType, "field_name")) {
        @compileLog("Has field!");
    }
}
```

### 3. 查看完整错误追踪

```bash
zig build test -freference-trace=10
```

### 4. 单步调试类型问题

```zig
test "debug type" {
    const writer = some_function();
    const T = @TypeOf(writer);

    // 编译时打印
    @compileLog(@typeName(T));
    @compileLog(@hasField(T, "interface"));
}
```

## 📌 迁移检查清单

升级到 Zig 0.15.2 时，请检查：

### File I/O 相关
- [ ] 所有 `std.io.getStdOut()` 改为 `std.fs.File.stdout()`
- [ ] 所有 `std.io.getStdErr()` 改为 `std.fs.File.stderr()`
- [ ] **避免使用 `file.writer(&buffer)` 创建 BufferedWriter**
- [ ] Console/JSON Logger 改用直接 File 类型：`ConsoleWriter(std.fs.File)`
- [ ] 如果必须用 BufferedWriter，确保通过 `.interface` 访问方法

### ArrayList 相关
- [ ] ArrayList.init 改为 initCapacity
- [ ] ArrayList 的 deinit/append/writer 添加 allocator 参数

### 内存安全
- [ ] 检查所有 `&parameter` 确保不是指向栈变量
- [ ] Writer 抽象改用泛型类型而非 anytype + vtable

### 测试验证
- [ ] 运行完整测试套件
- [ ] **验证 Console Logger 有实际输出**（避免 BufferedWriter 陷阱）
- [ ] 检查日志文件是否正确写入

## 📌 性能考虑

### 泛型类型 vs. 运行时多态

```zig
// ✅ 编译时泛型（零开销）
pub fn Writer(comptime T: type) type {
    return struct {
        writer: T,
        // 每个 T 都会生成独立的代码，内联优化好
    };
}

// ⚠️ 运行时多态（有开销）
pub const Writer = struct {
    ptr: *anyopaque,
    writeFn: *const fn(*anyopaque, []const u8) anyerror!void,
    // 每次调用都是间接调用，无法内联
};
```

对于 Logger 这种性能敏感的模块，优先使用泛型类型。

## 📌 测试策略

```zig
test "支持多种 Writer 类型" {
    // 测试 FixedBufferStream
    {
        var buf: [1024]u8 = undefined;
        var fbs = std.io.fixedBufferStream(&buf);
        const W = MyWriter(@TypeOf(fbs.writer()));
        var w = W.init(fbs.writer());
        try w.write("test");
    }

    // 测试 File.Writer
    {
        var buf: [1024]u8 = undefined;
        const writer = std.fs.File.stdout().writer(&buf);
        const W = MyWriter(@TypeOf(writer));
        var w = W.init(writer);
        try w.write("test");
    }
}
```

## 🔗 相关资源

- [详细问题排查文档](./zig-0.15.2-logger-compatibility.md)
- [Zig 0.15.2 发行说明](https://ziglang.org/download/0.15.2/release-notes.html)
- [标准库变更](https://github.com/ziglang/zig/blob/0.15.2/lib/std/CHANGELOG.md)

---

**最后更新：** 2025-12-23
**适用版本：** Zig 0.15.2
**维护者：** zigQuant Team
