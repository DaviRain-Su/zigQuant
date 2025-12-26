# Story: 仓位追踪器

> **更新日期**: 2025-12-23
> **更新内容**: 基于 Hyperliquid 真实 API 规范更新（参考: [API Research](HYPERLIQUID_API_RESEARCH.md)）

**ID**: `STORY-011`
**版本**: `v0.2`
**创建日期**: 2025-12-23
**状态**: 📋 计划中
**优先级**: P0 (必须)
**预计工时**: 3 天

---

## 📋 需求描述

### 用户故事
作为**量化交易开发者**，我希望**实时追踪账户仓位和盈亏**，以便**监控交易表现并进行风险管理**。

### 背景
仓位追踪器（Position Tracker）是交易系统的关键组件，负责：
- 追踪每个币种的持仓数量
- 计算持仓成本和盈亏
- 监控保证金和杠杆使用
- 提供风险指标（如清算价格）

对于永续合约交易，需要精确追踪：
- 仓位方向（多/空）
- 入场均价
- 未实现盈亏
- 已实现盈亏
- 资金费率

### 范围
- **包含**:
  - 仓位数据结构
  - 仓位追踪器
  - 盈亏计算（已实现/未实现）
  - 账户余额追踪
  - WebSocket 同步
  - 风险指标计算

- **不包含**:
  - 风险控制逻辑（见后续 Stories）
  - 仓位报表生成
  - 多账户管理

---

## 🎯 验收标准

- [ ] 仓位数据结构定义完成
- [ ] 仓位追踪器实现完成
- [ ] 盈亏计算正确（已实现/未实现）
- [ ] 支持 WebSocket 实时同步
- [ ] 账户余额和保证金计算正确
- [ ] 支持多币种持仓
- [ ] 所有测试用例通过
- [ ] 集成测试通过

---

## 🔧 技术设计

### 架构概览

```
src/trading/
├── position.zig          # 仓位数据结构
├── position_tracker.zig  # 仓位追踪器
├── account.zig           # 账户信息
└── position_test.zig     # 测试
```

### 核心数据结构

#### 1. 仓位 (基于真实 API)

```zig
// src/trading/position.zig
// 基于真实 API: szi (有符号仓位大小), leverage {type, value}, cumFunding

const std = @import("std");
const Decimal = @import("../core/decimal.zig").Decimal;
const Timestamp = @import("../core/time.zig").Timestamp;
const OrderTypes = @import("../core/order_types.zig");

pub const Position = struct {
    symbol: []const u8,

    // 基于真实 API: szi 字段（有符号: +多头, -空头）
    szi: Decimal,               // 仓位大小（有符号）
    side: OrderTypes.PositionSide, // long / short (从 szi 推断)

    // 仓位信息 (基于真实 API)
    entry_px: Decimal,          // 开仓均价 (entryPx)
    mark_price: ?Decimal,       // 标记价格（实时，用于计算 unrealizedPnl）
    liquidation_px: ?Decimal,   // 清算价格 (liquidationPx)

    // 杠杆 (基于真实 API: leverage {type, value, rawUsd})
    leverage: Leverage,
    max_leverage: u32,          // 最大杠杆 (maxLeverage)

    // 盈亏 (基于真实 API)
    unrealized_pnl: Decimal,    // 未实现盈亏 (unrealizedPnl)
    realized_pnl: Decimal,      // 已实现盈亏（累计，从 closedPnl 累加）

    // 保证金 (基于真实 API)
    margin_used: Decimal,       // 已用保证金 (marginUsed)
    position_value: Decimal,    // 仓位价值 (positionValue)

    // ROE (基于真实 API)
    return_on_equity: Decimal,  // 权益回报率 (returnOnEquity)

    // 资金费率 (基于真实 API: cumFunding)
    cum_funding: CumFunding,

    // 时间戳
    opened_at: Timestamp,
    updated_at: Timestamp,

    allocator: std.mem.Allocator,

    /// 杠杆结构 (基于真实 API)
    pub const Leverage = struct {
        type_: []const u8,      // "cross" 或 "isolated"
        value: u32,             // 杠杆倍数
        raw_usd: Decimal,       // 原始 USD 价值
    };

    /// 累计资金费率 (基于真实 API)
    pub const CumFunding = struct {
        all_time: Decimal,      // 累计总额
        since_change: Decimal,  // 自上次变动
        since_open: Decimal,    // 自开仓
    };

    pub fn init(
        allocator: std.mem.Allocator,
        symbol: []const u8,
        szi: Decimal,  // 基于真实 API: 有符号仓位大小
    ) !Position {
        return .{
            .symbol = try allocator.dupe(u8, symbol),
            .szi = szi,
            .side = if (szi.isPositive()) .long else .short,
            .entry_px = Decimal.ZERO,
            .mark_price = null,
            .liquidation_px = null,
            .leverage = .{
                .type_ = "cross",
                .value = 1,
                .raw_usd = Decimal.ZERO,
            },
            .max_leverage = 50,
            .unrealized_pnl = Decimal.ZERO,
            .realized_pnl = Decimal.ZERO,
            .margin_used = Decimal.ZERO,
            .position_value = Decimal.ZERO,
            .return_on_equity = Decimal.ZERO,
            .cum_funding = .{
                .all_time = Decimal.ZERO,
                .since_change = Decimal.ZERO,
                .since_open = Decimal.ZERO,
            },
            .opened_at = Timestamp.now(),
            .updated_at = Timestamp.now(),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Position) void {
        self.allocator.free(self.symbol);
    }

    /// 更新标记价格和未实现盈亏 (基于真实 API)
    pub fn updateMarkPrice(self: *Position, mark_price: Decimal) void {
        self.mark_price = mark_price;
        self.unrealized_pnl = self.calculateUnrealizedPnl(mark_price);
        self.position_value = self.szi.abs().mul(mark_price); // 基于真实 API: positionValue

        // 更新 ROE (基于真实 API: returnOnEquity)
        if (!self.margin_used.isZero()) {
            self.return_on_equity = self.unrealized_pnl.div(self.margin_used) catch Decimal.ZERO;
        }

        self.updated_at = Timestamp.now();
    }

    /// 计算未实现盈亏 (基于真实 API: 使用 szi)
    fn calculateUnrealizedPnl(self: *const Position, current_price: Decimal) Decimal {
        if (self.szi.isZero()) return Decimal.ZERO;

        // 基于真实 API: szi 为正表示多头，为负表示空头
        // PnL = szi * (current_price - entry_px)
        const price_diff = current_price.sub(self.entry_px);
        return price_diff.mul(self.szi);
    }

    /// 增加仓位（开仓或加仓）
    pub fn increase(
        self: *Position,
        quantity: Decimal,
        price: Decimal,
    ) void {
        if (self.size.isZero()) {
            // 首次开仓
            self.entry_price = price;
            self.size = quantity;
            self.opened_at = Timestamp.now();
        } else {
            // 加仓：计算新的平均价格
            const current_value = self.size.mul(self.entry_price);
            const new_value = quantity.mul(price);
            const total_size = self.size.add(quantity);

            self.entry_price = current_value.add(new_value).div(total_size) catch self.entry_price;
            self.size = total_size;
        }

        self.updated_at = Timestamp.now();
    }

    /// 减少仓位（减仓或平仓）
    pub fn decrease(
        self: *Position,
        quantity: Decimal,
        price: Decimal,
    ) Decimal {
        if (quantity.cmp(self.size) == .gt) {
            @panic("Cannot decrease position by more than current size");
        }

        // 计算此次平仓的已实现盈亏
        const close_pnl = self.calculateClosePnl(quantity, price);
        self.realized_pnl = self.realized_pnl.add(close_pnl);

        // 减少仓位大小
        self.size = self.size.sub(quantity);

        // 如果完全平仓，重置入场价格
        if (self.size.isZero()) {
            self.entry_price = Decimal.ZERO;
            self.unrealized_pnl = Decimal.ZERO;
        }

        self.updated_at = Timestamp.now();

        return close_pnl;
    }

    /// 计算平仓盈亏
    fn calculateClosePnl(self: *const Position, quantity: Decimal, close_price: Decimal) Decimal {
        const price_diff = close_price.sub(self.entry_price);
        const pnl = price_diff.mul(quantity);

        return switch (self.side) {
            .long => pnl,
            .short => pnl.negate(),
            .both => Decimal.ZERO,
        };
    }

    /// 是否为空仓
    pub fn isEmpty(self: *const Position) bool {
        return self.size.isZero();
    }

    /// 获取总盈亏
    pub fn getTotalPnl(self: *const Position) Decimal {
        return self.realized_pnl.add(self.unrealized_pnl);
    }
};
```

#### 2. 账户信息 (基于真实 API)

```zig
// src/trading/account.zig
// 基于真实 API: marginSummary, crossMarginSummary, withdrawable

const std = @import("std");
const Decimal = @import("../core/decimal.zig").Decimal;

pub const Account = struct {
    // 基于真实 API: marginSummary 字段
    margin_summary: MarginSummary,

    // 基于真实 API: crossMarginSummary 字段
    cross_margin_summary: MarginSummary,

    // 基于真实 API: withdrawable 字段
    withdrawable: Decimal,          // 可提现金额

    // 基于真实 API: crossMaintenanceMarginUsed
    cross_maintenance_margin_used: Decimal,

    // 本地追踪的盈亏（非 API 返回）
    total_realized_pnl: Decimal,    // 总已实现盈亏（从成交累计）

    /// 保证金摘要 (基于真实 API)
    pub const MarginSummary = struct {
        account_value: Decimal,     // 账户总价值 (accountValue)
        total_margin_used: Decimal, // 总已用保证金 (totalMarginUsed)
        total_ntl_pos: Decimal,     // 总名义仓位价值 (totalNtlPos)
        total_raw_usd: Decimal,     // 总原始 USD (totalRawUsd)
    };

    pub fn init() Account {
        return .{
            .margin_summary = .{
                .account_value = Decimal.ZERO,
                .total_margin_used = Decimal.ZERO,
                .total_ntl_pos = Decimal.ZERO,
                .total_raw_usd = Decimal.ZERO,
            },
            .cross_margin_summary = .{
                .account_value = Decimal.ZERO,
                .total_margin_used = Decimal.ZERO,
                .total_ntl_pos = Decimal.ZERO,
                .total_raw_usd = Decimal.ZERO,
            },
            .withdrawable = Decimal.ZERO,
            .cross_maintenance_margin_used = Decimal.ZERO,
            .total_realized_pnl = Decimal.ZERO,
        };
    }

    /// 从 API 响应更新账户信息 (基于真实 API: clearinghouseState)
    pub fn updateFromApiResponse(
        self: *Account,
        margin_summary: MarginSummary,
        cross_margin_summary: MarginSummary,
        withdrawable: Decimal,
        cross_maintenance_margin_used: Decimal,
    ) void {
        self.margin_summary = margin_summary;
        self.cross_margin_summary = cross_margin_summary;
        self.withdrawable = withdrawable;
        self.cross_maintenance_margin_used = cross_maintenance_margin_used;
    }
};
```

#### 3. 仓位追踪器

```zig
// src/trading/position_tracker.zig

const std = @import("std");
const Position = @import("position.zig").Position;
const Account = @import("account.zig").Account;
const OrderTypes = @import("../core/order_types.zig");
const HyperliquidClient = @import("../exchange/hyperliquid/http.zig").HyperliquidClient;
const InfoAPI = @import("../exchange/hyperliquid/info_api.zig");
const Logger = @import("../core/logger.zig").Logger;

pub const PositionTracker = struct {
    allocator: std.mem.Allocator,
    http_client: *HyperliquidClient,
    logger: Logger,

    // 仓位映射：symbol -> Position
    positions: std.StringHashMap(*Position),

    // 账户信息
    account: Account,

    // 回调
    on_position_update: ?*const fn (position: *Position) void,
    on_account_update: ?*const fn (account: *Account) void,

    mutex: std.Thread.Mutex,

    pub fn init(
        allocator: std.mem.Allocator,
        http_client: *HyperliquidClient,
        logger: Logger,
    ) !PositionTracker {
        return .{
            .allocator = allocator,
            .http_client = http_client,
            .logger = logger,
            .positions = std.StringHashMap(*Position).init(allocator),
            .account = Account.init(),
            .on_position_update = null,
            .on_account_update = null,
            .mutex = std.Thread.Mutex{},
        };
    }

    pub fn deinit(self: *PositionTracker) void {
        var iter = self.positions.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.*.deinit();
            self.allocator.destroy(entry.value_ptr.*);
        }
        self.positions.deinit();
    }

    /// 同步账户状态（从交易所） (基于真实 API: clearinghouseState)
    pub fn syncAccountState(self: *PositionTracker, user_address: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.logger.info("Syncing account state...", .{});

        // 基于真实 API: 调用 clearinghouseState 端点
        const state = try InfoAPI.getUserState(self.http_client, user_address);

        // 更新账户信息 (基于真实 API 字段)
        self.account.updateFromApiResponse(
            state.marginSummary,
            state.crossMarginSummary,
            state.withdrawable,
            state.crossMaintenanceMarginUsed,
        );

        // 更新仓位 (基于真实 API: assetPositions)
        for (state.assetPositions) |asset_pos| {
            const pos_data = asset_pos.position;

            // 基于真实 API: szi 有符号仓位大小
            const szi = try Decimal.fromString(pos_data.szi);
            if (szi.isZero()) continue; // 跳过空仓

            var position = try self.getOrCreatePosition(
                pos_data.coin,
                szi,
            );

            // 更新仓位数据 (基于真实 API 字段)
            position.szi = szi;
            position.side = if (szi.isPositive()) .long else .short;
            position.entry_px = try Decimal.fromString(pos_data.entryPx);
            position.leverage = .{
                .type_ = pos_data.leverage.type_,
                .value = pos_data.leverage.value,
                .raw_usd = try Decimal.fromString(pos_data.leverage.rawUsd),
            };
            position.max_leverage = pos_data.maxLeverage;
            position.margin_used = try Decimal.fromString(pos_data.marginUsed);
            position.position_value = try Decimal.fromString(pos_data.positionValue);
            position.unrealized_pnl = try Decimal.fromString(pos_data.unrealizedPnl);
            position.return_on_equity = try Decimal.fromString(pos_data.returnOnEquity);

            // 基于真实 API: cumFunding
            position.cum_funding = .{
                .all_time = try Decimal.fromString(pos_data.cumFunding.allTime),
                .since_change = try Decimal.fromString(pos_data.cumFunding.sinceChange),
                .since_open = try Decimal.fromString(pos_data.cumFunding.sinceOpen),
            };

            // 基于真实 API: liquidationPx (可能为 null)
            if (pos_data.liquidationPx) |liq_px| {
                position.liquidation_px = try Decimal.fromString(liq_px);
            }

            position.updated_at = Timestamp.now();

            if (self.on_position_update) |callback| {
                callback(position);
            }
        }

        self.logger.info("Account state synced: Value=${}", .{
            self.account.margin_summary.account_value.toFloat(),
        });
    }

    /// 处理成交事件（更新仓位） (基于真实 API: dir, closedPnl, startPosition)
    pub fn handleFill(
        self: *PositionTracker,
        fill: WsUserFills.UserFill,
    ) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // 基于真实 API: dir 字段 ("Open Long", "Close Short", "Open Short", "Close Long")
        const is_long = std.mem.indexOf(u8, fill.dir, "Long") != null;
        const is_opening = std.mem.indexOf(u8, fill.dir, "Open") != null;

        // 解析成交数据 (基于真实 API: 字符串格式)
        const sz = try Decimal.fromString(fill.sz);
        const px = try Decimal.fromString(fill.px);
        const closed_pnl = try Decimal.fromString(fill.closedPnl);
        const start_position = try Decimal.fromString(fill.startPosition);

        // 计算新的仓位大小 (基于真实 API: startPosition + 成交方向)
        var new_szi: Decimal = undefined;
        if (is_opening) {
            if (is_long) {
                // Open Long: szi 增加
                new_szi = start_position.add(sz);
            } else {
                // Open Short: szi 减少（变为负数或更负）
                new_szi = start_position.sub(sz);
            }
        } else {
            if (is_long) {
                // Close Long: szi 减少
                new_szi = start_position.sub(sz);
            } else {
                // Close Short: szi 增加（从负数变小或为零）
                new_szi = start_position.add(sz);
            }
        }

        // 获取或创建仓位
        var position = try self.getOrCreatePosition(fill.coin, new_szi);

        // 更新仓位
        position.szi = new_szi;
        position.side = if (new_szi.isPositive()) .long else .short;

        if (is_opening) {
            // 开仓或加仓: 更新均价
            position.increase(sz, px);
            self.logger.info("Position increased: {s} {s} {} @ {} (new szi: {})", .{
                fill.coin, fill.dir, fill.sz, fill.px, new_szi.toFloat(),
            });
        } else {
            // 平仓: 记录已实现盈亏 (基于真实 API: closedPnl)
            position.realized_pnl = position.realized_pnl.add(closed_pnl);
            self.logger.info("Position decreased: {s} {s} {} @ {} (closedPnl: {}, new szi: {})", .{
                fill.coin, fill.dir, fill.sz, fill.px, fill.closedPnl, new_szi.toFloat(),
            });

            // 如果完全平仓，移除仓位
            if (new_szi.isZero()) {
                _ = self.positions.remove(fill.coin);
                self.logger.info("Position closed: {s}", .{fill.coin});
            }
        }

        // 更新账户的已实现盈亏 (基于真实 API: closedPnl)
        if (!closed_pnl.isZero()) {
            self.account.total_realized_pnl = self.account.total_realized_pnl.add(closed_pnl);
        }

        if (self.on_position_update) |callback| {
            callback(position);
        }

        if (self.on_account_update) |callback| {
            callback(&self.account);
        }
    }

    /// 更新标记价格（用于计算未实现盈亏）
    pub fn updateMarkPrice(
        self: *PositionTracker,
        symbol: []const u8,
        mark_price: Decimal,
    ) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.positions.get(symbol)) |position| {
            position.updateMarkPrice(mark_price);

            if (self.on_position_update) |callback| {
                callback(position);
            }
        }
    }

    /// 获取所有仓位
    pub fn getAllPositions(self: *PositionTracker) ![]const *Position {
        self.mutex.lock();
        defer self.mutex.unlock();

        var list = std.ArrayList(*Position).init(self.allocator);
        defer list.deinit();

        var iter = self.positions.valueIterator();
        while (iter.next()) |pos| {
            try list.append(pos.*);
        }

        return try list.toOwnedSlice();
    }

    /// 获取单个仓位
    pub fn getPosition(self: *PositionTracker, symbol: []const u8) ?*Position {
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.positions.get(symbol);
    }

    // 内部辅助函数
    fn getOrCreatePosition(
        self: *PositionTracker,
        symbol: []const u8,
        szi: Decimal,  // 基于真实 API: 有符号仓位大小
    ) !*Position {
        if (self.positions.get(symbol)) |pos| {
            return pos;
        }

        const pos = try self.allocator.create(Position);
        pos.* = try Position.init(self.allocator, symbol, szi);
        try self.positions.put(symbol, pos);

        return pos;
    }
};
```

---

## 📝 任务分解

### Phase 1: 数据结构 📋
- [ ] 任务 1.1: 定义 Position 结构体
- [ ] 任务 1.2: 定义 Account 结构体
- [ ] 任务 1.3: 实现盈亏计算逻辑

### Phase 2: 仓位操作 📋
- [ ] 任务 2.1: 实现仓位增加（开仓/加仓）
- [ ] 任务 2.2: 实现仓位减少（减仓/平仓）
- [ ] 任务 2.3: 实现标记价格更新
- [ ] 任务 2.4: 实现已实现盈亏计算

### Phase 3: 仓位追踪器 📋
- [ ] 任务 3.1: 实现 PositionTracker
- [ ] 任务 3.2: 实现账户状态同步
- [ ] 任务 3.3: 实现成交事件处理
- [ ] 任务 3.4: 实现仓位查询

### Phase 4: 测试与文档 📋
- [ ] 任务 4.1: 编写单元测试
- [ ] 任务 4.2: 编写集成测试
- [ ] 任务 4.3: 编写盈亏计算测试
- [ ] 任务 4.4: 更新文档
- [ ] 任务 4.5: 代码审查

---

## 🧪 测试策略

### 单元测试

```zig
test "Position: increase (open/add)" {
    var pos = try Position.init(testing.allocator, "ETH", .long);
    defer pos.deinit();

    // 开仓
    pos.increase(try Decimal.fromString("1.0"), try Decimal.fromString("2000.0"));
    try testing.expect(pos.size.toFloat() == 1.0);
    try testing.expect(pos.entry_price.toFloat() == 2000.0);

    // 加仓
    pos.increase(try Decimal.fromString("1.0"), try Decimal.fromString("2100.0"));
    try testing.expect(pos.size.toFloat() == 2.0);
    try testing.expect(pos.entry_price.toFloat() == 2050.0); // 平均价格
}

test "Position: decrease (close)" {
    var pos = try Position.init(testing.allocator, "ETH", .long);
    defer pos.deinit();

    pos.increase(try Decimal.fromString("2.0"), try Decimal.fromString("2000.0"));

    // 部分平仓
    const pnl = pos.decrease(try Decimal.fromString("1.0"), try Decimal.fromString("2100.0"));
    try testing.expect(pnl.toFloat() == 100.0); // (2100 - 2000) * 1.0
    try testing.expect(pos.size.toFloat() == 1.0);

    // 完全平仓
    _ = pos.decrease(try Decimal.fromString("1.0"), try Decimal.fromString("2100.0"));
    try testing.expect(pos.isEmpty());
}

test "Position: unrealized PnL" {
    var pos = try Position.init(testing.allocator, "ETH", .long);
    defer pos.deinit();

    pos.increase(try Decimal.fromString("1.0"), try Decimal.fromString("2000.0"));
    pos.updateMarkPrice(try Decimal.fromString("2100.0"));

    try testing.expect(pos.unrealized_pnl.toFloat() == 100.0);
}
```

---

## 📚 相关文档

### 设计文档
- [ ] `docs/features/position-tracker/README.md` - 仓位追踪器概览
- [ ] `docs/features/position-tracker/pnl-calculation.md` - 盈亏计算详解

---

## 🔗 依赖关系

### 前置条件
- [x] Story 001: Decimal 类型
- [x] Story 002: Time Utils
- [ ] Story 006: Hyperliquid HTTP 客户端
- [ ] Story 007: Hyperliquid WebSocket 客户端
- [ ] Story 009: 订单类型定义

### 被依赖
- Story 012: CLI 界面
- 未来: 风险管理、策略引擎

---

## ⚠️ 风险与挑战

### 已识别风险
1. **精度问题**: 盈亏计算涉及多次浮点运算
   - **影响**: 高
   - **缓解措施**: 使用 Decimal 类型

2. **状态同步**: 仓位状态可能与交易所不一致
   - **影响**: 中
   - **缓解措施**: 定期同步，以交易所为准

---

## 📊 进度追踪

### 时间线
- 开始日期: 待定
- 预计完成: 待定

---

## ✅ 验收检查清单

- [ ] 所有验收标准已满足
- [ ] 所有任务已完成
- [ ] 单元测试通过
- [ ] 集成测试通过
- [ ] 盈亏计算验证正确
- [ ] 文档已更新
- [ ] 代码已审查

---

## 📸 演示

### 使用示例

```zig
const std = @import("std");
const PositionTracker = @import("trading/position_tracker.zig").PositionTracker;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var http_client = try HyperliquidClient.init(...);
    defer http_client.deinit();

    var tracker = try PositionTracker.init(allocator, &http_client, logger);
    defer tracker.deinit();

    // 设置回调
    tracker.on_position_update = handlePositionUpdate;
    tracker.on_account_update = handleAccountUpdate;

    // 同步账户状态
    try tracker.syncAccountState("0x1234...");

    // 查询所有仓位
    const positions = try tracker.getAllPositions();
    defer allocator.free(positions);

    for (positions) |pos| {
        std.debug.print("Position: {s} {} @ {} (PnL: {})\n", .{
            pos.symbol,
            pos.size.toFloat(),
            pos.entry_price.toFloat(),
            pos.getTotalPnl().toFloat(),
        });
    }

    // 查询账户信息
    std.debug.print("Account Value: ${}\n", .{tracker.account.account_value.toFloat()});
}

fn handlePositionUpdate(pos: *Position) void {
    std.debug.print("Position updated: {s}\n", .{pos.symbol});
}

fn handleAccountUpdate(account: *Account) void {
    std.debug.print("Account updated: ${}\n", .{account.account_value.toFloat()});
}
```

---

## 💡 未来改进

- [ ] 支持多账户管理
- [ ] 实现仓位报表
- [ ] 添加风险指标（Sharpe ratio, max drawdown）
- [ ] 实现仓位持久化
- [ ] 支持资金费率计算

---

*Last updated: 2025-12-23*
*Assignee: TBD*
*Status: 📋 Planning*
