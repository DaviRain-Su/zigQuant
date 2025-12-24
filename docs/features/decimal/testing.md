# Decimal - 测试文档

> 测试覆盖和性能基准

**最后更新**: 2025-12-24

---

## 测试覆盖率

- **测试用例数**: 12 (实际代码中的测试)
- **测试类型**: 单元测试 (内嵌在 decimal.zig 文件中)
- **覆盖范围**: 构造、运算、比较、转换、工具函数

---

## 单元测试

以下是实际代码中存在的 12 个测试用例：

### 1. 常量测试 (`test "Decimal: constants"`)
验证 ZERO、ONE 常量和 SCALE 值的正确性。

### 2. fromInt 测试 (`test "Decimal: fromInt"`)
验证整数转换的正确性。

### 3. fromFloat 测试 (`test "Decimal: fromFloat"`)
验证浮点数转换（带精度容差）。

### 4. fromString - 整数 (`test "Decimal: fromString - integers"`)
测试解析整数字符串，包括正数、负数、带符号。

### 5. fromString - 小数 (`test "Decimal: fromString - decimals"`)
测试解析小数字符串。

### 6. fromString - 错误处理 (`test "Decimal: fromString - errors"`)
验证各种错误情况：
- EmptyString
- InvalidFormat (仅有符号、小数点后无数字)
- InvalidCharacter
- MultipleDecimalPoints

### 7. toString 测试 (`test "Decimal: toString"`)
验证字符串格式化输出。

### 8. 加法测试 (`test "Decimal: add"`)
```zig
test "Decimal: add" {
    const a = try Decimal.fromString("100.5");
    const b = try Decimal.fromString("50.25");
    const sum = a.add(b);

    const expected = try Decimal.fromString("150.75");
    try testing.expect(sum.eql(expected));
}
```

### 9. 减法测试 (`test "Decimal: sub"`)
验证减法运算。

### 10. 乘法测试 (`test "Decimal: mul"`)
验证乘法运算。

### 11. 除法测试 (`test "Decimal: div"` 和 `test "Decimal: div by zero"`)
- 正常除法
- 除零错误处理

### 12. 精度测试 (`test "Decimal: precision - floating point trap"`)
经典的 0.1 + 0.2 = 0.3 测试，验证 Decimal 避免浮点误差：
```zig
test "Decimal: precision - floating point trap" {
    const a = try Decimal.fromString("0.1");
    const b = try Decimal.fromString("0.2");
    const c = a.add(b);

    const expected = try Decimal.fromString("0.3");
    try testing.expect(c.eql(expected));

    const s = try c.toString(testing.allocator);
    defer testing.allocator.free(s);
    try testing.expectEqualStrings("0.3", s);
}
```

### 13. 比较测试 (`test "Decimal: comparison"`)
验证 cmp 和 eql 函数。

### 14. 工具函数测试 (`test "Decimal: utility functions"`)
测试 isZero、isPositive、isNegative、abs、negate。

### 15. 往返转换测试 (`test "Decimal: round trip string conversion"`)
验证字符串 → Decimal → 字符串的一致性。

---

## 性能基准

**注意**: 当前代码中没有包含性能基准测试。

建议添加基准测试来衡量：
- 加法/减法性能
- 乘法性能（i256 中间转换开销）
- 除法性能
- 字符串解析性能
- toString 性能

### 示例基准测试（建议添加）

```zig
test "Decimal: benchmark arithmetic" {
    const iterations = 100_000;
    const a = try Decimal.fromString("123.456");
    const b = try Decimal.fromString("789.012");

    const start = std.time.nanoTimestamp();
    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        _ = a.add(b);
    }
    const end = std.time.nanoTimestamp();

    const elapsed_ms = @divTrunc(end - start, 1_000_000);
    const ops_per_sec = @divTrunc(iterations * 1000, @as(usize, @intCast(elapsed_ms)));

    std.debug.print("Addition: {} ops/sec\n", .{ops_per_sec});
}
```

---

## 运行测试

```bash
# 运行所有测试
zig test src/core/decimal.zig

# 带详细输出
zig test src/core/decimal.zig --summary all

# 使用 Zig 0.15.2
zig test src/core/decimal.zig
```

测试输出示例：
```
Test [1/12] Decimal: constants... OK
Test [2/12] Decimal: fromInt... OK
Test [3/12] Decimal: fromFloat... OK
...
All 12 tests passed.
```

---

## 测试场景

### ✅ 已覆盖 (实际代码中的测试)

- [x] 常量 (ZERO, ONE, SCALE)
- [x] fromInt 转换
- [x] fromFloat 转换
- [x] fromString 解析（整数、小数、带符号）
- [x] fromString 错误处理（空字符串、无效格式、无效字符、多个小数点）
- [x] toString 格式化
- [x] 基本四则运算 (add, sub, mul, div)
- [x] 除零错误处理
- [x] 精度验证（0.1 + 0.2 = 0.3）
- [x] 比较操作 (cmp, eql)
- [x] 工具函数 (isZero, isPositive, isNegative, abs, negate)
- [x] 往返字符串转换

### 📋 建议补充

- [ ] 边界值测试（最大/最小 i128 值）
- [ ] 溢出检测测试
- [ ] 性能基准测试
- [ ] 精度截断测试（超过 18 位小数）
- [ ] 大数运算测试
- [ ] 内存泄漏检测
- [ ] 并发安全性测试（如果需要）
