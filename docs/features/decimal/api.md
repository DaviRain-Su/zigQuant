# Decimal - API 参考

> 完整的 API 文档

**最后更新**: 2025-12-24

---

## 常量

```zig
pub const SCALE: u8 = 18;
pub const MULTIPLIER: i128 = 1_000_000_000_000_000_000;
pub const ZERO: Decimal = .{ .value = 0, .scale = SCALE };
pub const ONE: Decimal = .{ .value = MULTIPLIER, .scale = SCALE };
```

---

## 构造函数

### `fromInt`

```zig
pub fn fromInt(i: i64) Decimal
```

从整数创建 Decimal。

**参数**:
- `i`: i64 整数

**返回**: Decimal

**示例**:
```zig
const d = Decimal.fromInt(100);  // 100.0
```

---

### `fromFloat`

```zig
pub fn fromFloat(f: f64) Decimal
```

从浮点数创建 Decimal。

⚠️ **警告**: 可能损失精度，优先使用 `fromString`。

**参数**:
- `f`: f64 浮点数

**返回**: Decimal

---

### `fromString`

```zig
pub fn fromString(s: []const u8) !Decimal
```

从字符串创建 Decimal（推荐）。

**参数**:
- `s`: 字符串，如 "123.456"

**返回**: `!Decimal`

**错误**:
- `error.EmptyString`: 空字符串
- `error.InvalidFormat`: 格式错误（如仅有符号、小数点后无数字）
- `error.InvalidCharacter`: 包含非数字字符
- `error.MultipleDecimalPoints`: 多个小数点

**支持的格式**:
- "123" (整数)
- "123.456" (小数)
- "-123.456" (负数)
- "+123.456" (带正号)

**示例**:
```zig
const d = try Decimal.fromString("123.456");
const negative = try Decimal.fromString("-0.5");
```

---

## 转换函数

### `toFloat`

```zig
pub fn toFloat(self: Decimal) f64
```

转换为 f64。

⚠️ **警告**: 可能损失精度。

---

### `toString`

```zig
pub fn toString(self: Decimal, allocator: std.mem.Allocator) ![]const u8
```

转换为字符串。

**参数**:
- `allocator`: 内存分配器

**返回**: `![]const u8`

**注意**: 调用者需要释放返回的字符串。

**示例**:
```zig
const str = try d.toString(allocator);
defer allocator.free(str);
```

---

## 算术运算

### `add`

```zig
pub fn add(self: Decimal, other: Decimal) Decimal
```

加法。

**示例**:
```zig
const c = a.add(b);
```

---

### `sub`

```zig
pub fn sub(self: Decimal, other: Decimal) Decimal
```

减法。

---

### `mul`

```zig
pub fn mul(self: Decimal, other: Decimal) Decimal
```

乘法。

---

### `div`

```zig
pub fn div(self: Decimal, other: Decimal) !Decimal
```

除法。

**错误**:
- `error.DivisionByZero`: 除数为零

**示例**:
```zig
const c = try a.div(b);
```

---

## 比较函数

### `cmp`

```zig
pub fn cmp(self: Decimal, other: Decimal) std.math.Order
```

比较两个 Decimal。

**返回**: `.lt` | `.eq` | `.gt`

---

### `eql`

```zig
pub fn eql(self: Decimal, other: Decimal) bool
```

相等性比较。

---

## 工具函数

### `isZero`

```zig
pub fn isZero(self: Decimal) bool
```

检查是否为零。

---

### `isPositive`

```zig
pub fn isPositive(self: Decimal) bool
```

检查是否为正数。

---

### `isNegative`

```zig
pub fn isNegative(self: Decimal) bool
```

检查是否为负数。

---

### `abs`

```zig
pub fn abs(self: Decimal) Decimal
```

绝对值。

---

### `negate`

```zig
pub fn negate(self: Decimal) Decimal
```

取反。

---

## 完整示例

```zig
const std = @import("std");
const Decimal = @import("core/decimal.zig").Decimal;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建
    const a = try Decimal.fromString("100.50");
    const b = try Decimal.fromString("50.25");

    // 运算
    const sum = a.add(b);
    const diff = a.sub(b);
    const product = a.mul(b);
    const quotient = try a.div(b);

    // 比较
    if (a.cmp(b) == .gt) {
        const stdout = std.io.getStdOut().writer();
        try stdout.print("a is greater than b\n", .{});
    }

    // 工具函数
    const abs_value = a.abs();
    const negated = a.negate();
    if (a.isPositive()) {
        const stdout = std.io.getStdOut().writer();
        try stdout.print("a is positive\n", .{});
    }

    // 格式化输出
    const sum_str = try sum.toString(allocator);
    defer allocator.free(sum_str);

    const stdout = std.io.getStdOut().writer();
    try stdout.print("Sum: {s}\n", .{sum_str});
}
```
