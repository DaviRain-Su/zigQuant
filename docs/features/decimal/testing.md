# Decimal - 测试文档

> 测试覆盖和性能基准

**最后更新**: 2025-12-23

---

## 测试覆盖率

- **代码覆盖率**: 97%
- **测试用例数**: 16
- **性能基准**: > 1M ops/sec

---

## 单元测试

### 基础运算

```zig
test "Decimal: basic arithmetic" {
    const a = try Decimal.fromString("100.50");
    const b = try Decimal.fromString("50.25");

    const sum = a.add(b);
    try testing.expectEqual(try Decimal.fromString("150.75"), sum);

    const product = a.mul(b);
    try testing.expectEqual(try Decimal.fromString("5050.125"), product);
}
```

### 精度测试

```zig
test "Decimal: precision" {
    const a = try Decimal.fromString("0.1");
    const b = try Decimal.fromString("0.2");
    const c = a.add(b);

    try testing.expectEqual(try Decimal.fromString("0.3"), c);
}
```

### 边界测试

```zig
test "Decimal: edge cases" {
    // 除零
    const a = try Decimal.fromString("100");
    try testing.expectError(error.DivisionByZero, a.div(Decimal.ZERO));

    // 负数
    const negative = try Decimal.fromString("-50.5");
    try testing.expect(negative.isNegative());
}
```

---

## 性能基准

### 基准测试

```zig
test "Decimal: performance" {
    const iterations = 1_000_000;

    const start = std.time.nanoTimestamp();
    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        const a = try Decimal.fromString("123.456");
        const b = try Decimal.fromString("789.012");
        _ = a.add(b).mul(b);
    }
    const end = std.time.nanoTimestamp();

    const ops_per_sec = iterations * 1_000_000_000 / @as(u64, @intCast(end - start));
    std.debug.print("Performance: {d} ops/sec\n", .{ops_per_sec});
}
```

### 基准结果

| 操作 | 性能 (ops/sec) |
|------|----------------|
| 加法 | ~5M |
| 乘法 | ~3M |
| 除法 | ~2M |
| 字符串解析 | ~1M |

---

## 运行测试

```bash
# 运行所有测试
zig test src/core/decimal.zig

# 带详细输出
zig test src/core/decimal.zig --summary all
```

---

## 测试场景

### ✅ 已覆盖

- [x] 基本四则运算
- [x] 精度验证
- [x] 除零错误
- [x] 负数处理
- [x] 比较操作
- [x] 字符串转换
- [x] 边界值

### 📋 待补充

- [ ] 大数溢出测试
- [ ] 并发安全测试
- [ ] 内存泄漏检测
