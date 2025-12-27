# Pure Market Making - Bug 追踪

> 已知问题和修复记录

**最后更新**: 2025-12-27

---

## 当前状态

功能处于待开发状态，尚无已知 Bug。

---

## 已知 Bug

*当前无已知 Bug*

---

## 潜在问题

### 问题 #1: 订单取消失败累积

**状态**: 设计考虑
**严重性**: Medium

**描述**:
如果订单取消失败 (网络问题)，可能导致活跃订单列表与实际不一致。

**预期行为**:
- 应该重试取消
- 应该从交易所查询同步状态

**计划解决方案**:
```zig
fn cancelAllOrders(self: *Self) !void {
    var failed = ArrayList(u64).init(self.allocator);
    defer failed.deinit();

    for (self.active_bids.items) |order| {
        self.executor.cancelOrder(order.order_id) catch |err| {
            try failed.append(order.order_id);
        };
    }

    // 重试失败的订单
    for (failed.items) |order_id| {
        // 延迟重试或标记为待同步
    }
}
```

---

### 问题 #2: 仓位不一致

**状态**: 设计考虑
**严重性**: High

**描述**:
如果成交回报丢失，本地仓位可能与交易所不一致。

**缓解措施**:
- 定期从交易所同步仓位
- 策略启动时查询当前仓位

---

### 问题 #3: 价格精度

**状态**: 设计考虑
**严重性**: Low

**描述**:
报价计算可能产生不符合交易所精度要求的价格。

**计划解决方案**:
```zig
fn roundToTickSize(price: Decimal, tick_size: Decimal) Decimal {
    return price.div(tick_size).floor().mul(tick_size);
}
```

---

## 报告 Bug

请包含以下信息：

1. **标题**: 简短描述问题
2. **严重性**: Critical | High | Medium | Low
3. **复现步骤**:
   - 策略配置
   - 市场条件
   - 复现代码
4. **预期行为**: 期望的正确行为
5. **实际行为**: 实际发生的错误

**提交方式**:
- GitHub Issues: https://github.com/DaviRain-Su/zigQuant/issues
- 标签: `bug`, `pure-market-making`

---

*Last updated: 2025-12-27*
