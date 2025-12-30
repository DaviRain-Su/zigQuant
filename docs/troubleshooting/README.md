# zigQuant 故障排查文档索引

本目录包含 zigQuant 项目开发过程中遇到的重要问题及其解决方案。

## 目录

### Hyperliquid API 问题

- **[Hyperliquid 签名问题排查指南](./hyperliquid-signing-issues.md)** ⭐⭐ **新增**
  - 问题：签名验证失败、地址不存在、价格 tick size 错误
  - 解决方案：移除尾部零、区分双地址、对齐 tick size
  - 难度：⭐⭐⭐⭐ (隐蔽性极强)
  - 状态：✅ 已解决

### Zig 版本兼容性问题

- **[Zig 0.15.2 Logger 模块兼容性问题](./zig-0.15.2-logger-compatibility.md)** ⭐
  - 问题：File.Writer 类型不兼容、VTable 指针生命周期、ArrayList API 变更、BufferedWriter 刷新
  - 解决方案：泛型类型函数、编译时类型检查、直接 File 写入
  - 难度：⭐⭐⭐⭐
  - 状态：✅ 已解决

- **[BufferedWriter 陷阱 - 日志不显示](./bufferedwriter-trap.md)** ⚠️
  - 问题：代码正常但 Console/JSON Logger 完全无输出
  - 原因：BufferedWriter 数据未刷新
  - 难度：⭐⭐⭐ (隐蔽性强)
  - 状态：✅ 已解决

## 问题分类

### 交易所 API
- [Hyperliquid 签名问题排查指南](./hyperliquid-signing-issues.md) ⭐⭐ **签名验证失败**

### 类型系统
- [Zig 0.15.2 Logger 模块兼容性问题](./zig-0.15.2-logger-compatibility.md)

### 内存管理
- [Zig 0.15.2 Logger 模块兼容性问题](./zig-0.15.2-logger-compatibility.md) - VTable 指针生命周期部分

### I/O 和缓冲
- [BufferedWriter 陷阱 - 日志不显示](./bufferedwriter-trap.md) ⚠️ **隐蔽性强**

### API 变更
- [Zig 0.15.2 Logger 模块兼容性问题](./zig-0.15.2-logger-compatibility.md) - ArrayList API 变更部分

## 快速参考

### Zig 0.15.2 常见 API 变更

#### File I/O

⚠️ **重要警告：BufferedWriter 陷阱**

```zig
// ❌ 危险：数据写入缓冲区但不会显示
var buffer: [4096]u8 = undefined;
const writer = std.fs.File.stdout().writer(&buffer);
try writer.interface.writeAll(data);  // 数据留在 buffer 中！

// ✅ 推荐：直接使用 File
const file = std.fs.File.stdout();
_ = try file.writeAll(data);  // 立即输出

// ✅ 用于 Logger
const ConsoleWriter(std.fs.File);  // 直接 File 类型

// ❌ 旧版本（不再有效）
const writer = std.io.getStdOut().writer();
try writer.writeAll(data);
```

#### ArrayList
```zig
// ✅ 正确
var list = try std.ArrayList(u8).initCapacity(allocator, 256);
defer list.deinit(allocator);
try list.append(allocator, item);

// ❌ 错误
var list = std.ArrayList(u8).init(allocator);
defer list.deinit();
try list.append(item);
```

#### 泛型 Writer 模式
```zig
// ✅ 推荐模式
pub fn MyWriter(comptime WriterType: type) type {
    return struct {
        writer: WriterType,  // 存储值

        pub fn init(w: WriterType) @This() {
            return .{ .writer = w };
        }
    };
}

// ❌ 避免模式
pub const MyWriter = struct {
    writer_ptr: *anyopaque,  // 指针可能失效

    pub fn init(w: anytype) MyWriter {
        return .{ .writer_ptr = &w };  // 指向栈变量
    }
};
```

## 提交新问题

如果你在开发过程中遇到新问题并成功解决，请按以下格式创建文档：

1. 创建文件：`docs/troubleshooting/[category]-[brief-description].md`
2. 包含以下章节：
   - 问题背景
   - 核心问题清单
   - 解决方案演进
   - 关键经验总结
   - 测试策略
   - 诊断技巧
   - 相关文件
   - 版本信息
3. 更新本 README.md 添加索引链接

## 贡献指南

编写故障排查文档时，请遵循以下原则：

- ✅ 清晰描述问题表现（错误信息、异常行为）
- ✅ 解释根本原因（为什么会出现这个问题）
- ✅ 记录解决过程（包括失败的尝试）
- ✅ 提供可复现的代码示例
- ✅ 总结可复用的经验和模式
- ✅ 标注 Zig 版本和相关依赖版本
- ❌ 避免只贴代码不解释
- ❌ 避免跳过中间步骤
- ❌ 避免遗漏版本信息

## 相关资源

- [Zig 官方文档](https://ziglang.org/documentation/master/)
- [Zig 标准库源码](https://github.com/ziglang/zig/tree/master/lib/std)
- [zigQuant 项目文档](../README.md)
