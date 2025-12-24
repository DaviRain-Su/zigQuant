# Decimal - 实现细节

> 深入了解 Decimal 类型的内部实现

**最后更新**: 2025-12-24

---

## 内部表示

### 数据结构

```zig
pub const Decimal = struct {
    value: i128,    // 实际值 = 原始值 × 10^18
    scale: u8,      // 固定为 18
};
```

### 表示示例

| 原始值 | value (i128) | scale | 说明 |
|--------|--------------|-------|------|
| 0 | 0 | 18 | 零值 |
| 1 | 1_000_000_000_000_000_000 | 18 | 1.0 |
| 123.456 | 123_456_000_000_000_000_000 | 18 | 123.456 |
| 0.000000000000000001 | 1 | 18 | 最小精度 |

---

## 核心算法

### 加法

```zig
pub fn add(self: Decimal, other: Decimal) Decimal {
    std.debug.assert(self.scale == other.scale);
    return .{
        .value = self.value + other.value,
        .scale = self.scale,
    };
}
```

### 乘法

```zig
pub fn mul(self: Decimal, other: Decimal) Decimal {
    // 使用 i256 避免溢出
    const a = @as(i256, self.value);
    const b = @as(i256, other.value);
    const product = a * b;
    const scaled = @divTrunc(product, MULTIPLIER);

    return .{
        .value = @as(i128, @intCast(scaled)),
        .scale = self.scale,
    };
}
```

**说明**:
- 先将两个 i128 值扩展到 i256 以避免中间结果溢出
- 两个 18 位精度的数相乘会产生 36 位精度
- 除以 MULTIPLIER (10^18) 恢复到 18 位精度
- 最后转换回 i128 存储

### 除法

```zig
pub fn div(self: Decimal, other: Decimal) !Decimal {
    if (other.value == 0) {
        return error.DivisionByZero;
    }

    const a = @as(i256, self.value) * MULTIPLIER;
    const b = @as(i256, other.value);
    const quotient = @divTrunc(a, b);

    return .{
        .value = @as(i128, @intCast(quotient)),
        .scale = self.scale,
    };
}
```

**说明**:
- 首先检查除数是否为零，避免运行时错误
- 被除数乘以 MULTIPLIER (10^18) 以保持精度
- 使用 i256 避免中间计算溢出
- 结果自动具有 18 位精度

---

## 性能优化

### 1. 整数运算

所有运算都基于整数，无浮点运算开销。

### 2. 溢出处理

- 乘法/除法使用 i256 临时变量
- 编译时检测可能的溢出

### 3. 内存布局

- 16 bytes (i128)
- 对齐到 16 字节边界

---

## 精度考虑

### 精度范围

- **小数精度**: 18 位
- **整数范围**: ±10^20
- **最小值**: 1e-18
- **最大值**: ~1.7e+20

### 精度损失场景

1. **浮点数转换**: `fromFloat()` 可能损失精度
2. **除法截断**: 除法结果向下取整

---

## 边界情况

### 溢出检测

当前实现使用 i256 中间类型来处理乘法和除法，可以防止大多数溢出情况：

- **乘法**: i128 × i128 → i256 (中间结果) → i128
- **除法**: i128 × 10^18 → i256 (中间结果) → i128
- **加减法**: 直接 i128 运算，依赖 Zig 的运行时安全检查

**可能溢出的场景**:
- 加减法结果超出 i128 范围 (±1.7 × 10^38)
- 乘除法最终结果超出 i128 范围

### 除零处理

```zig
if (other.value == 0) {
    return error.DivisionByZero;
}
```

除法操作会返回错误类型 `!Decimal`，调用者必须处理 `error.DivisionByZero`。

### 精度截断

字符串解析时，超过 18 位小数的部分会被截断（不是四舍五入）：

```zig
// "123.123456789012345678999" 会被截断为 "123.123456789012345678"
for (s[frac_start..]) |c| {
    if (frac_digits >= SCALE) break; // 截断额外精度
    // ...
}
```

---

*完整实现请参考: `src/core/decimal.zig`*
