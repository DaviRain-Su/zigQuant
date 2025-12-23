# Decimal - 实现细节

> 深入了解 Decimal 类型的内部实现

**最后更新**: 2025-12-23

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
    const result = @as(i256, self.value) * @as(i256, other.value);
    const scaled = @divTrunc(result, MULTIPLIER);
    return .{
        .value = @intCast(scaled),
        .scale = self.scale,
    };
}
```

### 除法

```zig
pub fn div(self: Decimal, other: Decimal) !Decimal {
    if (other.value == 0) return error.DivisionByZero;

    // 扩大被除数以保持精度
    const scaled = @as(i256, self.value) * MULTIPLIER;
    const result = @divTrunc(scaled, other.value);
    return .{
        .value = @intCast(result),
        .scale = self.scale,
    };
}
```

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

```zig
// TODO: 添加溢出检测
// 当前实现依赖 Zig 的运行时检查
```

### 除零处理

```zig
if (other.value == 0) return error.DivisionByZero;
```

---

*完整实现请参考: `src/core/decimal.zig`*
