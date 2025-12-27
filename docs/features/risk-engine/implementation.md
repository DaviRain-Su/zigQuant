# RiskEngine - 实现细节

> 深入了解风险引擎的内部实现

**最后更新**: 2025-12-27

---

## 内部表示

### 数据结构

```zig
pub const RiskEngine = struct {
    allocator: Allocator,
    config: RiskConfig,
    positions: *PositionTracker,
    account: *Account,

    // 状态跟踪
    daily_pnl: Decimal,                    // 当日盈亏
    daily_start_equity: Decimal,           // 当日起始权益
    order_count_per_minute: u32,           // 当前分钟订单数
    last_minute_start: i64,                // 当前分钟起始时间
    kill_switch_active: std.atomic.Value(bool), // Kill Switch 状态 (原子操作)

    // 统计
    total_checks: u64,                     // 总检查次数
    rejected_orders: u64,                  // 拒绝订单数
};
```

### 配置结构

```zig
pub const RiskConfig = struct {
    // 仓位限制
    max_position_size: Decimal,        // 单个仓位最大值 (USD)
    max_position_per_symbol: Decimal,  // 单品种最大仓位

    // 杠杆限制
    max_leverage: Decimal,             // 最大杠杆倍数

    // 损失限制
    max_daily_loss: Decimal,           // 日损失限制 (绝对值)
    max_daily_loss_pct: f64,           // 日损失百分比

    // 订单限制
    max_orders_per_minute: u32,        // 每分钟最大订单数
    max_order_value: Decimal,          // 单笔订单最大金额

    // Kill Switch
    kill_switch_threshold: Decimal,     // Kill Switch 触发阈值
    close_positions_on_kill_switch: bool, // 触发时是否平仓
};
```

---

## 核心算法

### 订单风控检查流程

```zig
pub fn checkOrder(self: *Self, order: OrderRequest) RiskCheckResult {
    self.total_checks += 1;

    // 检查顺序按优先级排列，短路返回

    // 0. Kill Switch 检查 (最高优先级)
    if (self.kill_switch_active.load(.acquire)) {
        return reject(.kill_switch_active, "Kill switch is active");
    }

    // 1. 仓位大小检查
    if (try self.checkPositionSize(order)) |result| {
        return result;
    }

    // 2. 杠杆检查
    if (try self.checkLeverage(order)) |result| {
        return result;
    }

    // 3. 日损失检查
    if (try self.checkDailyLoss()) |result| {
        return result;
    }

    // 4. 订单频率检查
    if (try self.checkOrderRate()) |result| {
        return result;
    }

    // 5. 保证金检查
    if (try self.checkAvailableMargin(order)) |result| {
        return result;
    }

    return RiskCheckResult{ .passed = true };
}
```

**复杂度**: O(1) - 所有检查都是常量时间
**说明**: 检查顺序经过优化，最可能失败的检查放在前面以减少平均检查时间

### 仓位大小检查

```zig
fn checkPositionSize(self: *Self, order: OrderRequest) ?RiskCheckResult {
    // 计算订单价值
    const order_value = order.quantity.mul(order.price orelse Decimal.ONE);

    // 检查单笔订单大小
    if (order_value.cmp(self.config.max_position_size) == .gt) {
        return reject(.position_size_exceeded, "Order size exceeds limit");
    }

    // 获取当前持仓
    const current_position = self.positions.get(order.symbol);

    // 计算新的总持仓
    const new_size = if (current_position) |pos|
        calculateNewPosition(pos, order)
    else
        order.quantity;

    // 检查总持仓大小
    if (new_size.abs().cmp(self.config.max_position_per_symbol) == .gt) {
        return reject(.position_size_exceeded, "Total position would exceed limit");
    }

    return null; // 通过
}
```

### 杠杆计算

```zig
fn checkLeverage(self: *Self, order: OrderRequest) ?RiskCheckResult {
    // 计算当前总敞口
    const current_exposure = self.calculateTotalExposure();

    // 计算订单敞口
    const order_exposure = order.quantity.mul(order.price orelse Decimal.ONE);

    // 总敞口
    const total_exposure = current_exposure.add(order_exposure);

    // 计算杠杆 = 总敞口 / 账户权益
    const leverage = total_exposure.div(self.account.equity);

    if (leverage.cmp(self.config.max_leverage) == .gt) {
        return reject(.leverage_exceeded, "Order would exceed max leverage");
    }

    return null;
}

fn calculateTotalExposure(self: *Self) Decimal {
    var exposure = Decimal.ZERO;
    for (self.positions.getAll()) |pos| {
        const pos_value = pos.quantity.mul(pos.current_price);
        exposure = exposure.add(pos_value.abs());
    }
    return exposure;
}
```

### 日损失追踪

```zig
fn checkDailyLoss(self: *Self) ?RiskCheckResult {
    // 更新日内盈亏
    self.updateDailyPnL();

    // 检查绝对损失
    const loss = self.daily_pnl.negate();
    if (loss.cmp(self.config.max_daily_loss) == .gt) {
        return reject(.daily_loss_exceeded, "Daily loss limit reached");
    }

    // 检查百分比损失
    const loss_pct = loss.div(self.daily_start_equity).toFloat();
    if (loss_pct > self.config.max_daily_loss_pct) {
        return reject(.daily_loss_exceeded, "Daily loss percentage limit reached");
    }

    return null;
}

fn updateDailyPnL(self: *Self) void {
    // 检查是否跨日
    const now = std.time.timestamp();
    if (isNewDay(now, self.last_day_start)) {
        self.daily_pnl = Decimal.ZERO;
        self.daily_start_equity = self.account.equity;
        self.last_day_start = now;
    }

    // 计算当前盈亏
    self.daily_pnl = self.account.equity.sub(self.daily_start_equity);
}
```

### 订单频率控制

```zig
fn checkOrderRate(self: *Self) ?RiskCheckResult {
    const now = std.time.timestamp();

    // 检查是否进入新的分钟
    if (now - self.last_minute_start >= 60) {
        self.order_count_per_minute = 0;
        self.last_minute_start = now;
    }

    self.order_count_per_minute += 1;

    if (self.order_count_per_minute > self.config.max_orders_per_minute) {
        return reject(.order_rate_exceeded, "Order rate limit exceeded");
    }

    return null;
}
```

---

## Kill Switch 实现

### 触发 Kill Switch

```zig
pub fn killSwitch(self: *Self, execution: *ExecutionEngine) !void {
    // 使用原子操作设置标志，确保线程安全
    self.kill_switch_active.store(true, .release);

    std.log.warn("[RISK] Kill Switch triggered!", .{});

    // 1. 取消所有未完成订单
    try execution.cancelAllOrders();

    // 2. 如果配置了平仓，则平掉所有仓位
    if (self.config.close_positions_on_kill_switch) {
        for (self.positions.getAll()) |pos| {
            try execution.closePosition(pos);
        }
    }

    // 3. 发送告警 (通过 AlertManager)
    // 在 Story 044 实现
}
```

### 自动触发检查

```zig
pub fn checkKillSwitchConditions(self: *Self) bool {
    self.updateDailyPnL();

    // 检查日损失是否达到 Kill Switch 阈值
    const loss = self.daily_pnl.negate();
    if (loss.cmp(self.config.kill_switch_threshold) == .gt) {
        std.log.warn("[RISK] Kill switch threshold reached: loss={d}", .{
            loss.toFloat(),
        });
        return true;
    }

    return false;
}
```

---

## 性能优化

### 1. 原子操作

Kill Switch 状态使用 `std.atomic.Value(bool)` 实现，确保多线程环境下的安全访问：

```zig
kill_switch_active: std.atomic.Value(bool),

// 读取
if (self.kill_switch_active.load(.acquire)) { ... }

// 写入
self.kill_switch_active.store(true, .release);
```

### 2. 短路检查

风控检查按失败可能性排序，一旦某项检查失败立即返回：

```zig
// Kill Switch 最先检查 (最可能在特殊情况下失败)
// 然后是仓位、杠杆等常规检查
```

### 3. 缓存计算结果

避免重复计算：

```zig
// 缓存总敞口，避免多次遍历持仓
var cached_exposure: ?Decimal = null;

fn getTotalExposure(self: *Self) Decimal {
    if (self.cached_exposure) |exp| return exp;
    const exp = self.calculateTotalExposure();
    self.cached_exposure = exp;
    return exp;
}

// 在状态变化时清除缓存
fn invalidateCache(self: *Self) void {
    self.cached_exposure = null;
}
```

---

## 内存管理

### 分配策略

RiskEngine 本身不进行动态内存分配：

```zig
pub fn init(allocator: Allocator, config: RiskConfig, ...) RiskEngine {
    return .{
        .allocator = allocator,  // 保留用于未来扩展
        .config = config,        // 值拷贝
        .positions = positions,  // 指针引用
        .account = account,      // 指针引用
        // 其他字段都是基本类型
    };
}

pub fn deinit(self: *RiskEngine) void {
    // 目前不需要释放任何资源
    _ = self;
}
```

### 依赖管理

RiskEngine 依赖外部的 PositionTracker 和 Account：
- 不拥有这些资源的所有权
- 不负责它们的生命周期管理
- 调用者需确保这些对象在 RiskEngine 使用期间有效

---

## 边界情况

### 情况 1: 账户权益为零

```zig
fn checkLeverage(self: *Self, order: OrderRequest) ?RiskCheckResult {
    if (self.account.equity.cmp(Decimal.ZERO) == .eq) {
        return reject(.insufficient_margin, "Account equity is zero");
    }
    // ...
}
```

### 情况 2: 第一次检查 (无历史数据)

```zig
fn updateDailyPnL(self: *Self) void {
    if (self.daily_start_equity.cmp(Decimal.ZERO) == .eq) {
        // 首次初始化
        self.daily_start_equity = self.account.equity;
        self.last_day_start = std.time.timestamp();
    }
    // ...
}
```

### 情况 3: 时间回退 (系统时钟调整)

```zig
fn checkOrderRate(self: *Self) ?RiskCheckResult {
    const now = std.time.timestamp();

    // 处理时间回退
    if (now < self.last_minute_start) {
        self.last_minute_start = now;
        self.order_count_per_minute = 0;
    }
    // ...
}
```

### 情况 4: 订单价格为 null (市价单)

```zig
fn checkPositionSize(self: *Self, order: OrderRequest) ?RiskCheckResult {
    // 市价单使用最新市场价格估算
    const price = order.price orelse self.getLatestPrice(order.symbol);
    const order_value = order.quantity.mul(price);
    // ...
}
```

---

## 与其他模块集成

### 与 ExecutionEngine 集成

```zig
// ExecutionEngine 在提交订单前调用风控
pub fn submitOrder(self: *Self, order: OrderRequest) !OrderResult {
    // 风控检查
    const risk_check = self.risk_engine.checkOrder(order);
    if (!risk_check.passed) {
        return OrderResult{
            .status = .rejected,
            .reason = risk_check.message,
        };
    }

    // 检查 Kill Switch 条件
    if (self.risk_engine.checkKillSwitchConditions()) {
        try self.risk_engine.killSwitch(self);
        return OrderResult{
            .status = .rejected,
            .reason = "Kill switch triggered",
        };
    }

    // 提交订单
    return self.doSubmitOrder(order);
}
```

### 与 AlertManager 集成 (Story 044)

```zig
pub fn killSwitch(self: *Self, execution: *ExecutionEngine) !void {
    self.kill_switch_active.store(true, .release);

    // ... 取消订单和平仓 ...

    // 发送告警
    if (self.alert_manager) |alerts| {
        try alerts.riskAlert(.risk_kill_switch, .{
            .threshold = self.config.kill_switch_threshold,
            .actual = self.daily_pnl.negate(),
        });
    }
}
```

---

*完整实现请参考: `src/risk/risk_engine.zig`*
