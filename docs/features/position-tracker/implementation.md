# 仓位追踪器 - 实现细节

> 深入了解内部实现、数据结构和核心算法

**最后更新**: 2025-12-23

---

## 内部表示

### 核心数据结构

#### 1. Position（仓位）

基于 Hyperliquid 真实 API 设计，使用有符号仓位大小（szi）表示方向：

```zig
// src/trading/position.zig
pub const Position = struct {
    symbol: []const u8,

    // 基于真实 API: szi 字段（有符号仓位大小）
    szi: Decimal,                   // +正数表示多头，-负数表示空头
    side: PositionSide,             // 从 szi 推断得出

    // 价格信息
    entry_px: Decimal,              // 开仓均价
    mark_price: ?Decimal,           // 标记价格（实时更新）
    liquidation_px: ?Decimal,       // 清算价格

    // 杠杆信息（基于真实 API: leverage {type, value, rawUsd}）
    leverage: Leverage,
    max_leverage: u32,

    // 盈亏
    unrealized_pnl: Decimal,        // 未实现盈亏
    realized_pnl: Decimal,          // 已实现盈亏

    // 保证金
    margin_used: Decimal,           // 已用保证金
    position_value: Decimal,        // 仓位价值

    // 风险指标
    return_on_equity: Decimal,      // 权益回报率 ROE

    // 资金费率（基于真实 API: cumFunding）
    cum_funding: CumFunding,

    // 时间戳
    opened_at: Timestamp,
    updated_at: Timestamp,

    allocator: Allocator,
};
```

**关键设计决策**:
- 使用 `szi`（Signed Size）统一表示仓位大小和方向，与 Hyperliquid API 保持一致
- `side` 字段作为派生属性，方便快速判断多空
- 所有价格和数量使用 `Decimal` 类型确保精度
- `mark_price` 和 `liquidation_px` 为可选值，初始时可能为空

#### 2. Leverage（杠杆）

```zig
pub const Leverage = struct {
    type_: []const u8,      // "cross" 或 "isolated"
    value: u32,             // 杠杆倍数
    raw_usd: Decimal,       // 原始 USD 价值
};
```

#### 3. CumFunding（累计资金费率）

```zig
pub const CumFunding = struct {
    all_time: Decimal,      // 累计总额
    since_change: Decimal,  // 自上次变动
    since_open: Decimal,    // 自开仓
};
```

#### 4. Account（账户信息）

```zig
// src/trading/account.zig
pub const Account = struct {
    // 基于真实 API: marginSummary 字段
    margin_summary: MarginSummary,
    cross_margin_summary: MarginSummary,

    // 可提现金额
    withdrawable: Decimal,

    // 维持保证金
    cross_maintenance_margin_used: Decimal,

    // 本地追踪的总已实现盈亏
    total_realized_pnl: Decimal,
};

pub const MarginSummary = struct {
    account_value: Decimal,         // 账户总价值
    total_margin_used: Decimal,     // 总已用保证金
    total_ntl_pos: Decimal,         // 总名义仓位价值
    total_raw_usd: Decimal,         // 总原始 USD
};
```

#### 5. PositionTracker（仓位追踪器）

```zig
// src/trading/position_tracker.zig
pub const PositionTracker = struct {
    allocator: Allocator,
    http_client: *HyperliquidClient,
    logger: Logger,

    // 仓位映射：symbol -> *Position
    positions: StringHashMap(*Position),

    // 账户信息
    account: Account,

    // 回调函数
    on_position_update: ?*const fn (position: *Position) void,
    on_account_update: ?*const fn (account: *Account) void,

    // 线程安全
    mutex: std.Thread.Mutex,
};
```

**并发安全设计**:
- 使用 `Mutex` 保护所有数据访问
- 所有公共方法在操作前先获取锁

---

## 核心算法

### 1. 未实现盈亏计算

基于有符号仓位大小（szi）的盈亏计算公式：

```zig
fn calculateUnrealizedPnl(self: *const Position, current_price: Decimal) Decimal {
    if (self.szi.isZero()) return Decimal.ZERO;

    // PnL = szi * (current_price - entry_px)
    // 多头 (szi > 0): 价格上涨盈利
    // 空头 (szi < 0): 价格下跌盈利
    const price_diff = current_price.sub(self.entry_px);
    return price_diff.mul(self.szi);
}
```

**数学原理**:
- **多头仓位** (szi = +10):
  - 入场价: $2000
  - 当前价: $2100
  - PnL = 10 × ($2100 - $2000) = +$1000 (盈利)

- **空头仓位** (szi = -10):
  - 入场价: $2000
  - 当前价: $1900
  - PnL = -10 × ($1900 - $2000) = +$1000 (盈利)

**复杂度**: O(1)
**说明**: 使用有符号数量的优势在于公式统一，无需根据 side 进行分支判断

### 2. 开仓/加仓均价计算

```zig
pub fn increase(
    self: *Position,
    quantity: Decimal,
    price: Decimal,
) void {
    if (self.szi.isZero()) {
        // 首次开仓
        self.entry_px = price;
        self.szi = if (self.side == .long) quantity else quantity.negate();
        self.opened_at = Timestamp.now();
    } else {
        // 加仓：计算加权平均价格
        const current_value = self.szi.abs().mul(self.entry_px);
        const new_value = quantity.mul(price);
        const total_size = self.szi.abs().add(quantity);

        self.entry_px = current_value.add(new_value).div(total_size) catch self.entry_px;

        // 更新 szi
        if (self.side == .long) {
            self.szi = self.szi.add(quantity);
        } else {
            self.szi = self.szi.sub(quantity); // szi 变得更负
        }
    }

    self.updated_at = Timestamp.now();
}
```

**公式**:
```
新均价 = (原仓位价值 + 新开仓价值) / (原仓位大小 + 新开仓大小)
      = (|szi| × entry_px + qty × price) / (|szi| + qty)
```

**示例**:
- 原持仓: 5 ETH @ $2000 (价值 $10,000)
- 加仓: 3 ETH @ $2100 (价值 $6,300)
- 新均价: ($10,000 + $6,300) / (5 + 3) = $2037.5

**复杂度**: O(1)

### 3. 平仓已实现盈亏计算

```zig
fn calculateClosePnl(self: *const Position, quantity: Decimal, close_price: Decimal) Decimal {
    const price_diff = close_price.sub(self.entry_px);
    const pnl = price_diff.mul(quantity);

    return switch (self.side) {
        .long => pnl,
        .short => pnl.negate(),
        .both => Decimal.ZERO,
    };
}

pub fn decrease(
    self: *Position,
    quantity: Decimal,
    price: Decimal,
) Decimal {
    if (quantity.cmp(self.szi.abs()) == .gt) {
        @panic("Cannot decrease position by more than current size");
    }

    // 计算此次平仓的已实现盈亏
    const close_pnl = self.calculateClosePnl(quantity, price);
    self.realized_pnl = self.realized_pnl.add(close_pnl);

    // 减少仓位大小
    if (self.side == .long) {
        self.szi = self.szi.sub(quantity);
    } else {
        self.szi = self.szi.add(quantity); // szi 变得不那么负
    }

    // 如果完全平仓，重置
    if (self.szi.isZero()) {
        self.entry_px = Decimal.ZERO;
        self.unrealized_pnl = Decimal.ZERO;
    }

    self.updated_at = Timestamp.now();

    return close_pnl;
}
```

**公式**:
- **多头**: PnL = (平仓价 - 入场价) × 数量
- **空头**: PnL = (入场价 - 平仓价) × 数量

**示例**:
- 多头平仓: 5 ETH，入场价 $2000，平仓价 $2100
  - PnL = ($2100 - $2000) × 5 = +$500
- 空头平仓: 5 ETH，入场价 $2000，平仓价 $1900
  - PnL = ($2000 - $1900) × 5 = +$500

**复杂度**: O(1)

### 4. 标记价格更新

```zig
pub fn updateMarkPrice(self: *Position, mark_price: Decimal) void {
    self.mark_price = mark_price;
    self.unrealized_pnl = self.calculateUnrealizedPnl(mark_price);
    self.position_value = self.szi.abs().mul(mark_price);

    // 更新 ROE（权益回报率）
    if (!self.margin_used.isZero()) {
        self.return_on_equity = self.unrealized_pnl.div(self.margin_used) catch Decimal.ZERO;
    }

    self.updated_at = Timestamp.now();
}
```

**说明**:
- 标记价格更新会触发未实现盈亏、仓位价值和 ROE 的重新计算
- ROE = 未实现盈亏 / 已用保证金

### 5. WebSocket 成交事件处理

基于 Hyperliquid 真实 API 的 `dir` 字段（"Open Long", "Close Short" 等）：

```zig
pub fn handleFill(
    self: *PositionTracker,
    fill: WsUserFills.UserFill,
) !void {
    self.mutex.lock();
    defer self.mutex.unlock();

    // 解析成交方向
    const is_long = std.mem.indexOf(u8, fill.dir, "Long") != null;
    const is_opening = std.mem.indexOf(u8, fill.dir, "Open") != null;

    // 解析成交数据
    const sz = try Decimal.fromString(fill.sz);
    const px = try Decimal.fromString(fill.px);
    const closed_pnl = try Decimal.fromString(fill.closedPnl);
    const start_position = try Decimal.fromString(fill.startPosition);

    // 计算新的 szi
    var new_szi: Decimal = undefined;
    if (is_opening) {
        if (is_long) {
            new_szi = start_position.add(sz);      // Open Long
        } else {
            new_szi = start_position.sub(sz);      // Open Short
        }
    } else {
        if (is_long) {
            new_szi = start_position.sub(sz);      // Close Long
        } else {
            new_szi = start_position.add(sz);      // Close Short
        }
    }

    // 获取或创建仓位
    var position = try self.getOrCreatePosition(fill.coin, new_szi);

    // 更新仓位
    position.szi = new_szi;
    position.side = if (new_szi.isPositive()) .long else .short;

    if (is_opening) {
        position.increase(sz, px);
    } else {
        position.realized_pnl = position.realized_pnl.add(closed_pnl);
        if (new_szi.isZero()) {
            _ = self.positions.remove(fill.coin);
        }
    }

    // 更新账户已实现盈亏
    if (!closed_pnl.isZero()) {
        self.account.total_realized_pnl = self.account.total_realized_pnl.add(closed_pnl);
    }

    // 触发回调
    if (self.on_position_update) |callback| {
        callback(position);
    }
}
```

**复杂度**: O(1) 平均情况（HashMap 查找）

### 6. 账户状态同步

从交易所 API 同步完整账户状态：

```zig
pub fn syncAccountState(self: *PositionTracker, user_address: []const u8) !void {
    self.mutex.lock();
    defer self.mutex.unlock();

    // 调用 clearinghouseState 端点
    const state = try InfoAPI.getUserState(self.http_client, user_address);

    // 更新账户信息
    self.account.updateFromApiResponse(
        state.marginSummary,
        state.crossMarginSummary,
        state.withdrawable,
        state.crossMaintenanceMarginUsed,
    );

    // 更新所有仓位
    for (state.assetPositions) |asset_pos| {
        const pos_data = asset_pos.position;
        const szi = try Decimal.fromString(pos_data.szi);

        if (szi.isZero()) continue; // 跳过空仓

        var position = try self.getOrCreatePosition(pos_data.coin, szi);

        // 更新所有字段（基于真实 API）
        position.szi = szi;
        position.side = if (szi.isPositive()) .long else .short;
        position.entry_px = try Decimal.fromString(pos_data.entryPx);
        position.leverage = .{
            .type_ = pos_data.leverage.type_,
            .value = pos_data.leverage.value,
            .raw_usd = try Decimal.fromString(pos_data.leverage.rawUsd),
        };
        // ... 其他字段

        if (self.on_position_update) |callback| {
            callback(position);
        }
    }
}
```

**复杂度**: O(n)，n 为仓位数量

---

## 性能优化

### 1. HashMap 存储

使用 `StringHashMap(*Position)` 快速查找仓位：
- 查找: O(1) 平均
- 插入: O(1) 平均
- 删除: O(1) 平均

### 2. 指针存储

存储 `*Position` 而非 `Position`：
- 减少内存拷贝
- 支持外部持有引用
- 便于更新

### 3. Decimal 精度

使用 128-bit Decimal 类型：
- 避免浮点数精度问题
- 确保财务计算准确性
- 牺牲少量性能换取正确性

---

## 内存管理

### 分配策略

```zig
// 仓位创建时分配
const pos = try self.allocator.create(Position);
pos.* = try Position.init(self.allocator, symbol, szi);

// symbol 字符串复制
.symbol = try allocator.dupe(u8, symbol),
```

### 释放策略

```zig
pub fn deinit(self: *PositionTracker) void {
    var iter = self.positions.iterator();
    while (iter.next()) |entry| {
        entry.value_ptr.*.deinit();         // 释放 Position 内部资源
        self.allocator.destroy(entry.value_ptr.*); // 释放 Position 本身
    }
    self.positions.deinit();  // 释放 HashMap
}
```

**注意事项**:
- 必须先调用 `position.deinit()` 释放内部 `symbol` 字符串
- 然后 `destroy` 释放 `Position` 结构体本身
- 最后释放 `HashMap`

---

## 边界情况

### 1. 空仓处理

```zig
if (self.szi.isZero()) return Decimal.ZERO;
```

空仓时未实现盈亏为 0。

### 2. 完全平仓

```zig
if (self.szi.isZero()) {
    self.entry_px = Decimal.ZERO;
    self.unrealized_pnl = Decimal.ZERO;
}
```

完全平仓后重置入场价格和未实现盈亏。

### 3. 除零保护

```zig
if (!self.margin_used.isZero()) {
    self.return_on_equity = self.unrealized_pnl.div(self.margin_used) catch Decimal.ZERO;
}
```

保证金为 0 时 ROE 设为 0。

### 4. 可选字段处理

```zig
if (pos_data.liquidationPx) |liq_px| {
    position.liquidation_px = try Decimal.fromString(liq_px);
}
```

清算价格可能为 null（全仓模式）。

### 5. 数量验证

```zig
if (quantity.cmp(self.szi.abs()) == .gt) {
    @panic("Cannot decrease position by more than current size");
}
```

防止平仓数量超过持仓。

---

## 线程安全

所有公共方法使用 Mutex 保护：

```zig
pub fn syncAccountState(self: *PositionTracker, user_address: []const u8) !void {
    self.mutex.lock();
    defer self.mutex.unlock();
    // ... 操作
}
```

**保护范围**:
- `positions` HashMap 的读写
- `account` 结构体的更新
- 回调函数的调用

---

*完整实现请参考: `src/trading/position.zig`, `src/trading/account.zig`, `src/trading/position_tracker.zig`*
