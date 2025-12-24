# Decimal - 高精度十进制数类型

> 用于金融计算的高精度十进制数类型，避免浮点数精度问题

**状态**: ✅ 已完成
**版本**: v0.1.0
**Story**: [001-decimal-type](../../../stories/v0.1-foundation/001-decimal-type.md)
**最后更新**: 2025-12-24

---

## 📋 概述

Decimal 是 ZigQuant 框架的核心基础类型，提供高精度的十进制数运算能力，专门用于金融计算场景。它基于 **i128 整数 + 固定精度（18位小数）** 的实现方式，确保计算结果的精确性。

### 为什么需要 Decimal？

在金融交易中，使用 `f64` 浮点数会导致精度误差：

```zig
// ❌ 浮点数精度问题
const a: f64 = 0.1;
const b: f64 = 0.2;
const c = a + b;  // 0.30000000000000004 (错误!)

// ✅ Decimal 精确计算
const a = try Decimal.fromString("0.1");
const b = try Decimal.fromString("0.2");
const c = a.add(b);  // 0.3 (正确!)
```

### 核心特性

- ✅ **高精度**: 18 位小数精度，满足绝大多数金融场景
- ✅ **零成本抽象**: 内部使用整数运算，性能接近原生整数
- ✅ **类型安全**: 编译时类型检查，避免运行时错误
- ✅ **易于使用**: 类似浮点数的 API，学习成本低
- ✅ **完整运算**: 支持加减乘除、比较、格式化等所有必要操作

---

## 🚀 快速开始

### 基本使用

```zig
const std = @import("std");
const Decimal = @import("core/decimal.zig").Decimal;

pub fn main() !void {
    // 创建 Decimal
    const price = try Decimal.fromString("43250.50");
    const amount = try Decimal.fromString("0.01");

    // 计算
    const cost = price.mul(amount);  // 432.505

    // 输出
    const stdout = std.io.getStdOut().writer();
    try stdout.print("Cost: {d}\n", .{cost.toFloat()});
}
```

### 金融计算示例

```zig
// 计算交易成本（包含手续费）
const std = @import("std");
const Decimal = @import("core/decimal.zig").Decimal;

pub fn calculateTradingCost() !void {
    const price = try Decimal.fromString("43250.50");
    const amount = try Decimal.fromString("0.01");
    const fee_rate = try Decimal.fromString("0.001");  // 0.1%

    const cost = price.mul(amount);           // 432.505
    const fee = cost.mul(fee_rate);           // 0.432505
    const total = cost.add(fee);              // 432.937505

    // 格式化输出
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const total_str = try total.toString(allocator);
    defer allocator.free(total_str);

    const stdout = std.io.getStdOut().writer();
    try stdout.print("Total: ${s}\n", .{total_str});
    // 输出: Total: $432.937505
}
```

---

## 📚 相关文档

- [API 参考](./api.md) - 完整的 API 文档
- [实现细节](./implementation.md) - 内部实现说明
- [测试文档](./testing.md) - 测试覆盖和基准
- [Bug 追踪](./bugs.md) - 已知问题和修复
- [变更日志](./changelog.md) - 版本历史

---

## 🔧 核心 API

```zig
pub const Decimal = struct {
    // 常量
    pub const ZERO: Decimal;
    pub const ONE: Decimal;

    // 构造
    pub fn fromInt(i: i64) Decimal;
    pub fn fromFloat(f: f64) Decimal;
    pub fn fromString(s: []const u8) !Decimal;

    // 转换
    pub fn toFloat(self: Decimal) f64;
    pub fn toString(self: Decimal, allocator: Allocator) ![]const u8;

    // 运算
    pub fn add(self: Decimal, other: Decimal) Decimal;
    pub fn sub(self: Decimal, other: Decimal) Decimal;
    pub fn mul(self: Decimal, other: Decimal) Decimal;
    pub fn div(self: Decimal, other: Decimal) !Decimal;

    // 比较
    pub fn cmp(self: Decimal, other: Decimal) std.math.Order;
    pub fn eql(self: Decimal, other: Decimal) bool;

    // 工具
    pub fn abs(self: Decimal) Decimal;
    pub fn negate(self: Decimal) Decimal;
    pub fn isZero(self: Decimal) bool;
};
```

---

## 📝 最佳实践

### ✅ DO

```zig
// 1. 使用字符串创建（精确）
const price = try Decimal.fromString("43250.50");

// 2. 检查错误
const result = a.div(b) catch |err| {
    // 处理除零错误
    return err;
};

// 3. 及时释放内存
const str = try decimal.toString(allocator);
defer allocator.free(str);
```

### ❌ DON'T

```zig
// 1. 避免浮点数创建（可能不精确）
const price = Decimal.fromFloat(43250.50);  // ⚠️

// 2. 不检查错误
const result = a.div(b);  // 可能 panic

// 3. 频繁转换
const f = a.toFloat() / b.toFloat();  // 低效
```

---

## 🎯 使用场景

### ✅ 适用

- 交易价格计算
- 手续费计算
- 账户余额管理
- 盈亏计算
- 风控指标

### ❌ 不适用

- 科学计算（需要更高精度）
- 性能极致要求（使用整数）
- 超大数运算（超出 i128 范围）

---

## 📊 性能指标

- **测试用例**: 12 tests (all passing)
- **代码覆盖率**: High coverage of core functionality
- **运算性能**: Integer-based arithmetic (very fast)
- **内存占用**: 16 bytes (i128) + 1 byte (u8 scale)
- **精度范围**: 18 位小数 (10^-18)

---

## 💡 未来改进

- [ ] 可配置精度
- [ ] 更多数学函数（sqrt, pow）
- [ ] 货币格式化
- [ ] JSON 序列化
- [ ] SIMD 优化

---

*Last updated: 2025-12-23*
