# Grid Trading 测试文档

> 网格交易策略的测试指南

**版本**: v0.10.0
**最后更新**: 2025-12-28

---

## 目录

- [测试类型](#测试类型)
- [单元测试](#单元测试)
- [集成测试](#集成测试)
- [手动测试](#手动测试)
- [性能测试](#性能测试)

---

## 测试类型

| 测试类型 | 覆盖范围 | 位置 |
|----------|----------|------|
| 单元测试 | GridConfig, GridStrategy | `src/strategy/builtin/grid.zig` |
| 集成测试 | CLI 命令 | `tests/integration/` |
| 手动测试 | Paper/Testnet 交易 | CLI |
| 性能测试 | 延迟、内存 | Benchmark |

---

## 单元测试

### 运行测试

```bash
# 运行所有测试
zig build test

# 运行特定模块测试
zig test src/strategy/builtin/grid.zig
```

### GridConfig 测试

```zig
test "GridConfig: validate" {
    // 有效配置
    const valid_config = Config{
        .pair = .{ .base = "BTC", .quote = "USDC" },
        .upper_price = Decimal.fromFloat(100000),
        .lower_price = Decimal.fromFloat(90000),
        .grid_count = 10,
        .order_size = Decimal.fromFloat(0.001),
    };
    try valid_config.validate();

    // 无效价格范围
    const invalid_range = Config{
        .pair = .{ .base = "BTC", .quote = "USDC" },
        .upper_price = Decimal.fromFloat(90000),  // upper <= lower
        .lower_price = Decimal.fromFloat(100000),
        .grid_count = 10,
    };
    try std.testing.expectError(error.InvalidPriceRange, invalid_range.validate());

    // 无效网格数量
    const invalid_grids = Config{
        .pair = .{ .base = "BTC", .quote = "USDC" },
        .upper_price = Decimal.fromFloat(100000),
        .lower_price = Decimal.fromFloat(90000),
        .grid_count = 0,  // < 2
    };
    try std.testing.expectError(error.InvalidGridCount, invalid_grids.validate());
}

test "GridConfig: gridInterval" {
    const config = Config{
        .pair = .{ .base = "BTC", .quote = "USDC" },
        .upper_price = Decimal.fromFloat(100000),
        .lower_price = Decimal.fromFloat(90000),
        .grid_count = 10,
    };

    const interval = config.gridInterval();
    // (100000 - 90000) / 10 = 1000
    try std.testing.expect(interval.eql(Decimal.fromFloat(1000)));
}

test "GridConfig: priceAtLevel" {
    const config = Config{
        .pair = .{ .base = "BTC", .quote = "USDC" },
        .upper_price = Decimal.fromFloat(100000),
        .lower_price = Decimal.fromFloat(90000),
        .grid_count = 10,
    };

    // Level 0 = 90000
    try std.testing.expect(config.priceAtLevel(0).eql(Decimal.fromFloat(90000)));

    // Level 5 = 95000
    try std.testing.expect(config.priceAtLevel(5).eql(Decimal.fromFloat(95000)));

    // Level 10 = 100000
    try std.testing.expect(config.priceAtLevel(10).eql(Decimal.fromFloat(100000)));
}
```

### GridStrategy 测试

```zig
test "GridStrategy: init and deinit" {
    const allocator = std.testing.allocator;

    const config = Config{
        .pair = .{ .base = "BTC", .quote = "USDC" },
        .upper_price = Decimal.fromFloat(100000),
        .lower_price = Decimal.fromFloat(90000),
        .grid_count = 10,
    };

    var strategy = try GridStrategy.init(allocator, config);
    defer strategy.deinit();

    // 检查网格层级数量
    try std.testing.expectEqual(@as(usize, 11), strategy.grid_levels.len);  // grid_count + 1
}

test "GridStrategy: asStrategy interface" {
    const allocator = std.testing.allocator;

    const config = Config{
        .pair = .{ .base = "BTC", .quote = "USDC" },
        .upper_price = Decimal.fromFloat(100000),
        .lower_price = Decimal.fromFloat(90000),
        .grid_count = 10,
    };

    var strategy = try GridStrategy.init(allocator, config);
    defer strategy.deinit();

    const iface = strategy.asStrategy();

    // 测试 getName
    try std.testing.expectEqualStrings("GridStrategy", iface.getName());
}
```

---

## 集成测试

### CLI 命令测试

```bash
# 测试帮助信息
./zig-out/bin/zigQuant grid --help

# 测试缺少必需参数
./zig-out/bin/zigQuant grid --pair BTC-USDC
# 预期: 错误 - Missing required argument: --upper

# 测试无效价格范围
./zig-out/bin/zigQuant grid --pair BTC-USDC --upper 90000 --lower 100000
# 预期: 错误 - InvalidPriceRange
```

### Paper Trading 测试

```bash
# 短时间 Paper Trading 测试
timeout 15 ./zig-out/bin/zigQuant grid \
    --pair BTC-USDC \
    --upper 100000 \
    --lower 90000 \
    --grids 5 \
    --duration 1 \
    --interval 2000

# 预期输出:
# - 配置信息显示
# - 风险管理初始化
# - 初始订单放置
# - 状态更新
```

### 配置文件测试

```bash
# 创建测试配置
cat > /tmp/test_config.json << 'EOF'
{
  "exchanges": [{
    "name": "hyperliquid",
    "api_key": "0xTestWallet",
    "api_secret": "test_private_key",
    "testnet": true
  }],
  "trading": {
    "max_position_size": 500.0,
    "leverage": 1,
    "risk_limit": 0.01
  }
}
EOF

# 测试配置加载
./zig-out/bin/zigQuant grid \
    --config /tmp/test_config.json \
    --pair BTC-USDC \
    --upper 100000 \
    --lower 90000 \
    --paper

# 预期: 显示 "Config loaded successfully"
# 预期: Max position: 500.00, Daily loss limit: 1.00%
```

---

## 手动测试

### Paper Trading 手动测试

**测试步骤**:

1. 启动 Paper Trading
   ```bash
   ./zig-out/bin/zigQuant grid \
       --pair BTC-USDC \
       --upper 100000 \
       --lower 90000 \
       --grids 10 \
       --paper
   ```

2. 观察输出:
   - [ ] 配置信息正确显示
   - [ ] 风险管理初始化成功
   - [ ] 初始买单数量正确 (当前价格以下)
   - [ ] 状态每 10 次迭代更新

3. 等待模拟成交:
   - [ ] 买单成交后显示 `[FILL] BUY`
   - [ ] 自动放置卖单
   - [ ] 卖单成交后显示利润

4. 停止 (Ctrl+C):
   - [ ] 显示最终统计
   - [ ] 正确取消剩余订单

### Testnet 手动测试

**前置条件**:
- Hyperliquid Testnet 账户
- 测试币余额

**测试步骤**:

1. 准备配置文件 `config.test.json`

2. 启动 Testnet 交易
   ```bash
   ./zig-out/bin/zigQuant grid \
       --config config.test.json \
       --pair BTC-USDC \
       --upper 100000 \
       --lower 90000 \
       --grids 5 \
       --size 0.001 \
       --testnet
   ```

3. 验证:
   - [ ] 成功连接到 Testnet
   - [ ] 订单出现在 Hyperliquid Testnet UI
   - [ ] 成交后仓位更新
   - [ ] PnL 计算正确

**测试检查清单**:

| 功能 | 测试结果 | 备注 |
|------|----------|------|
| 配置加载 | ✅ / ❌ | |
| 交易所连接 | ✅ / ❌ | |
| 订单放置 | ✅ / ❌ | |
| 风险检查 | ✅ / ❌ | |
| 成交处理 | ✅ / ❌ | |
| 告警通知 | ✅ / ❌ | |
| 状态显示 | ✅ / ❌ | |
| 优雅退出 | ✅ / ❌ | |

---

## 性能测试

### 延迟测试

```zig
test "benchmark: risk check latency" {
    const allocator = std.testing.allocator;

    var account = Account.init();
    account.cross_margin_summary.account_value = Decimal.fromFloat(100000);

    var engine = RiskEngine.init(allocator, RiskConfig.default(), null, &account);
    defer engine.deinit();

    const order = OrderRequest{
        .pair = TradingPair{ .base = "BTC", .quote = "USDT" },
        .side = .buy,
        .order_type = .limit,
        .amount = Decimal.fromFloat(0.1),
        .price = Decimal.fromFloat(50000),
    };

    // 预热
    for (0..100) |_| {
        _ = engine.checkOrder(order);
    }

    // 测量
    const start = std.time.nanoTimestamp();
    const iterations: u64 = 10000;

    for (0..iterations) |_| {
        _ = engine.checkOrder(order);
    }

    const elapsed = std.time.nanoTimestamp() - start;
    const avg_ns = @divFloor(elapsed, iterations);

    std.debug.print("\nRisk check latency: {} ns/check\n", .{avg_ns});

    // 断言 < 1ms
    try std.testing.expect(avg_ns < 1_000_000);
}
```

### 内存测试

```bash
# 使用 valgrind 检测内存泄漏
valgrind --leak-check=full ./zig-out/bin/zigQuant grid \
    --pair BTC-USDC \
    --upper 100000 \
    --lower 90000 \
    --grids 10 \
    --duration 1 \
    --paper
```

### 长时间运行测试

```bash
# 运行 24 小时稳定性测试
nohup ./zig-out/bin/zigQuant grid \
    --pair BTC-USDC \
    --upper 100000 \
    --lower 90000 \
    --grids 20 \
    --duration 1440 \
    --paper \
    > grid_24h.log 2>&1 &

# 监控内存使用
watch -n 60 'ps aux | grep zigQuant'
```

---

## 测试矩阵

| 场景 | Paper | Testnet | Mainnet |
|------|-------|---------|---------|
| 基本功能 | ✅ | ✅ | ⚠️ |
| 风险管理 | ✅ | ✅ | ✅ |
| 配置加载 | ✅ | ✅ | ✅ |
| 长时间运行 | ✅ | ✅ | - |
| 压力测试 | ✅ | - | - |

**图例**:
- ✅ 应该测试
- ⚠️ 谨慎测试
- \- 不建议测试

---

## 已知测试限制

1. **Paper Trading 局限性**
   - 无真实市场滑点
   - 无订单簿深度影响
   - 模拟价格不反映真实波动

2. **Testnet 局限性**
   - 流动性可能与主网不同
   - 延迟可能不代表主网

3. **自动化测试**
   - 目前主要依赖手动测试
   - CI 集成待完善

---

*Last updated: 2025-12-28*
