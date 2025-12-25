# Story: StrategyContext 和辅助组件实现

**ID**: `STORY-014`
**版本**: `v0.3.0`
**创建日期**: 2025-12-25
**状态**: 📋 待开始
**优先级**: P0 (必须)
**预计工时**: 1 天

---

## 📋 需求描述

### 用户故事
作为策略开发者，我希望有一个完整的 StrategyContext 上下文环境，以便我的策略可以访问市场数据、执行订单、管理风险，而无需关心底层实现细节。

### 背景
参考 Hummingbot V2 的 Controller 模式，StrategyContext 是策略运行的核心环境，它将：
- 提供市场数据访问接口
- 提供订单执行能力
- 提供风险管理功能
- 提供指标管理和缓存
- 提供日志和配置访问

StrategyContext 将策略逻辑与具体的交易所实现、数据源实现解耦，使策略可以独立测试和运行。

### 范围
- **包含**:
  - StrategyContext 核心结构
  - RiskManager 风险管理器
  - OrderExecutor 订单执行器
  - PositionManager 仓位管理器（简化版）
  - MarketDataProvider 接口定义
  - IndicatorManager 接口定义（实现在 Story 016）
  - 单元测试和集成测试

- **不包含**:
  - IndicatorManager 具体实现（Story 016）
  - 技术指标库（Story 015）
  - 真实交易所集成（后续版本）
  - 完整的风控规则（仅实现基础检查）

---

## 🎯 验收标准

- [ ] **AC1**: StrategyContext 结构定义完整
  - 包含 allocator, logger, config
  - 包含所有必需的组件引用
  - 提供初始化和清理方法

- [ ] **AC2**: RiskManager 实现基础风控功能
  - 检查仓位大小是否超过限制
  - 检查账户余额是否足够
  - 检查最大持仓数量限制
  - 提供风险度计算

- [ ] **AC3**: OrderExecutor 实现订单执行逻辑
  - 支持市价单和限价单
  - 订单验证（价格、数量）
  - 模拟执行模式（用于回测）
  - 订单状态管理

- [ ] **AC4**: PositionManager 实现仓位管理
  - 持仓信息跟踪
  - 盈亏计算
  - 持仓列表管理
  - 仓位更新和关闭

- [ ] **AC5**: MarketDataProvider 接口定义清晰
  - 获取最新价格
  - 获取历史 K线
  - 订阅实时数据（接口定义）

- [ ] **AC6**: 编译通过，无警告

- [ ] **AC7**: 单元测试覆盖率 > 85%
  - RiskManager 各项检查测试
  - OrderExecutor 订单验证测试
  - PositionManager 盈亏计算测试
  - StrategyContext 集成测试

- [ ] **AC8**: 内存安全验证通过
  - 无内存泄漏
  - 所有资源正确释放

---

## 🔧 技术设计

### 架构概览

```
StrategyContext
    ├── Allocator              # 内存分配器
    ├── Logger                 # 日志器
    ├── Config                 # 策略配置
    │
    ├── MarketDataProvider     # 市场数据提供者
    ├── OrderExecutor          # 订单执行器
    ├── PositionManager        # 仓位管理器
    ├── RiskManager           # 风险管理器
    └── IndicatorManager      # 指标管理器（接口）
```

### 数据结构

#### 1. StrategyContext (context.zig)

```zig
const std = @import("std");
const Logger = @import("../log/logger.zig").Logger;
const Decimal = @import("../types/decimal.zig").Decimal;
const StrategyConfig = @import("types.zig").StrategyConfig;
const MarketDataProvider = @import("market_data.zig").MarketDataProvider;
const OrderExecutor = @import("executor.zig").OrderExecutor;
const PositionManager = @import("position_manager.zig").PositionManager;
const RiskManager = @import("risk.zig").RiskManager;
const IndicatorManager = @import("indicators/manager.zig").IndicatorManager;
const IExchange = @import("../exchange/interface.zig").IExchange;

/// 策略执行上下文 - 提供策略所需的所有资源
/// 参考 Hummingbot Controller 设计
pub const StrategyContext = struct {
    allocator: std.mem.Allocator,
    logger: Logger,

    /// 市场数据提供者
    market_data: *MarketDataProvider,

    /// 订单执行器
    executor: *OrderExecutor,

    /// 仓位管理器
    position_manager: *PositionManager,

    /// 风险管理器
    risk_manager: *RiskManager,

    /// 指标管理器
    indicator_manager: *IndicatorManager,

    /// 交易所接口（可选，用于实盘）
    exchange: ?IExchange,

    /// 策略配置
    config: StrategyConfig,

    pub fn init(
        allocator: std.mem.Allocator,
        logger: Logger,
        config: StrategyConfig,
        exchange: ?IExchange,
    ) !StrategyContext {
        // 创建市场数据提供者
        const market_data = try allocator.create(MarketDataProvider);
        market_data.* = try MarketDataProvider.init(allocator, exchange);

        // 创建订单执行器
        const executor = try allocator.create(OrderExecutor);
        executor.* = try OrderExecutor.init(allocator, exchange, logger);

        // 创建仓位管理器
        const position_manager = try allocator.create(PositionManager);
        position_manager.* = try PositionManager.init(allocator);

        // 创建风险管理器
        const risk_manager = try allocator.create(RiskManager);
        risk_manager.* = try RiskManager.init(allocator, config);

        // 创建指标管理器
        const indicator_manager = try allocator.create(IndicatorManager);
        indicator_manager.* = try IndicatorManager.init(allocator);

        return StrategyContext{
            .allocator = allocator,
            .logger = logger,
            .market_data = market_data,
            .executor = executor,
            .position_manager = position_manager,
            .risk_manager = risk_manager,
            .indicator_manager = indicator_manager,
            .exchange = exchange,
            .config = config,
        };
    }

    pub fn deinit(self: *StrategyContext) void {
        self.indicator_manager.deinit();
        self.allocator.destroy(self.indicator_manager);

        self.risk_manager.deinit();
        self.allocator.destroy(self.risk_manager);

        self.position_manager.deinit();
        self.allocator.destroy(self.position_manager);

        self.executor.deinit();
        self.allocator.destroy(self.executor);

        self.market_data.deinit();
        self.allocator.destroy(self.market_data);
    }

    /// 获取当前账户信息
    pub fn getAccount(self: *StrategyContext) !Account {
        return if (self.exchange) |exchange|
            try exchange.getAccount()
        else
            Account.mock();  // 回测模式返回模拟账户
    }

    /// 检查订单是否通过风控
    pub fn validateOrder(self: *StrategyContext, order: Order) !void {
        try self.risk_manager.validateOrder(order, self.position_manager.*);
    }
};
```

#### 2. RiskManager (risk.zig)

```zig
const std = @import("std");
const Decimal = @import("../types/decimal.zig").Decimal;
const Order = @import("../trading/order.zig").Order;
const Position = @import("../trading/position.zig").Position;
const PositionManager = @import("position_manager.zig").PositionManager;
const StrategyConfig = @import("types.zig").StrategyConfig;

/// 风险管理器
pub const RiskManager = struct {
    allocator: std.mem.Allocator,
    config: StrategyConfig,

    // 风控配置
    max_position_size: Decimal,      // 单个仓位最大大小
    max_total_exposure: Decimal,     // 总敞口限制
    max_open_trades: u32,           // 最大持仓数量

    pub fn init(allocator: std.mem.Allocator, config: StrategyConfig) !RiskManager {
        return RiskManager{
            .allocator = allocator,
            .config = config,
            .max_position_size = config.stake_amount,
            .max_total_exposure = try config.stake_amount.mul(try Decimal.fromInt(config.max_open_trades)),
            .max_open_trades = config.max_open_trades,
        };
    }

    pub fn deinit(self: *RiskManager) void {
        _ = self;
    }

    /// 验证订单是否符合风控要求
    pub fn validateOrder(
        self: *RiskManager,
        order: Order,
        position_manager: PositionManager,
    ) !void {
        // 检查 1: 持仓数量限制
        const open_positions = position_manager.getOpenPositionCount();
        if (open_positions >= self.max_open_trades) {
            return error.MaxOpenTradesReached;
        }

        // 检查 2: 仓位大小限制
        const order_value = try order.quantity.mul(order.price);
        if (order_value.gt(self.max_position_size)) {
            return error.PositionSizeTooLarge;
        }

        // 检查 3: 总敞口限制
        const current_exposure = try position_manager.getTotalExposure();
        const new_exposure = try current_exposure.add(order_value);
        if (new_exposure.gt(self.max_total_exposure)) {
            return error.TotalExposureTooLarge;
        }
    }

    /// 计算仓位风险度 [0.0, 1.0]
    pub fn calculateRisk(self: *RiskManager, position_manager: PositionManager) !f64 {
        const current_exposure = try position_manager.getTotalExposure();
        const risk_ratio = try current_exposure.div(self.max_total_exposure);
        return risk_ratio.toFloat();
    }

    /// 计算建议仓位大小（基于凯利公式简化版）
    pub fn calculatePositionSize(
        self: *RiskManager,
        win_rate: f64,
        avg_win: Decimal,
        avg_loss: Decimal,
        account_balance: Decimal,
    ) !Decimal {
        // 简化的凯利公式: f = (p * b - q) / b
        // p = 胜率, q = 1-p, b = 平均盈利/平均亏损
        _ = self;

        if (avg_loss.isZero()) {
            return try Decimal.fromFloat(0.01);  // 默认 1%
        }

        const b = try avg_win.div(avg_loss);
        const p = win_rate;
        const q = 1.0 - win_rate;

        const kelly = (p * b.toFloat() - q) / b.toFloat();
        const kelly_fraction = @max(0.0, @min(kelly, 0.25));  // 限制在 0-25%

        return try account_balance.mul(try Decimal.fromFloat(kelly_fraction));
    }
};
```

#### 3. OrderExecutor (executor.zig)

```zig
const std = @import("std");
const Logger = @import("../log/logger.zig").Logger;
const Order = @import("../trading/order.zig").Order;
const OrderType = @import("../trading/order.zig").OrderType;
const OrderStatus = @import("../trading/order.zig").OrderStatus;
const IExchange = @import("../exchange/interface.zig").IExchange;
const Decimal = @import("../types/decimal.zig").Decimal;

/// 订单执行器
pub const OrderExecutor = struct {
    allocator: std.mem.Allocator,
    exchange: ?IExchange,
    logger: Logger,
    simulation_mode: bool,  // 模拟模式（用于回测）

    pub fn init(allocator: std.mem.Allocator, exchange: ?IExchange, logger: Logger) !OrderExecutor {
        return OrderExecutor{
            .allocator = allocator,
            .exchange = exchange,
            .logger = logger,
            .simulation_mode = exchange == null,
        };
    }

    pub fn deinit(self: *OrderExecutor) void {
        _ = self;
    }

    /// 执行订单
    pub fn executeOrder(self: *OrderExecutor, order: *Order) !void {
        // 验证订单
        try self.validateOrder(order.*);

        if (self.simulation_mode) {
            // 模拟执行
            try self.simulateExecution(order);
        } else {
            // 真实执行
            const exchange = self.exchange.?;
            const order_id = try exchange.placeOrder(order.*);
            order.id = order_id;
            order.status = .submitted;

            self.logger.info("Order executed: {s} {s} {} @ {}", .{
                @tagName(order.side),
                order.pair.toString(),
                order.quantity,
                order.price,
            });
        }
    }

    /// 取消订单
    pub fn cancelOrder(self: *OrderExecutor, order: *Order) !void {
        if (order.status != .submitted and order.status != .partial_filled) {
            return error.OrderNotCancellable;
        }

        if (self.simulation_mode) {
            order.status = .cancelled;
        } else {
            const exchange = self.exchange.?;
            try exchange.cancelOrder(order.id.?);
            order.status = .cancelled;

            self.logger.info("Order cancelled: {?s}", .{order.id});
        }
    }

    /// 验证订单
    fn validateOrder(self: *OrderExecutor, order: Order) !void {
        _ = self;

        // 检查价格和数量
        if (order.price.lte(Decimal.ZERO)) {
            return error.InvalidOrderPrice;
        }
        if (order.quantity.lte(Decimal.ZERO)) {
            return error.InvalidOrderQuantity;
        }

        // 市价单特殊检查
        if (order.order_type == .market) {
            // 市价单不需要价格（价格将由交易所确定）
        }
    }

    /// 模拟订单执行（用于回测）
    fn simulateExecution(self: *OrderExecutor, order: *Order) !void {
        _ = self;

        // 模拟订单立即成交
        order.status = .filled;
        order.filled_quantity = order.quantity;
        order.average_price = order.price;
        order.id = try std.fmt.allocPrint(
            self.allocator,
            "SIM-{d}",
            .{std.time.milliTimestamp()},
        );
    }
};
```

#### 4. PositionManager (position_manager.zig)

```zig
const std = @import("std");
const Decimal = @import("../types/decimal.zig").Decimal;
const Position = @import("../trading/position.zig").Position;
const TradingPair = @import("../types/market.zig").TradingPair;

/// 仓位管理器
pub const PositionManager = struct {
    allocator: std.mem.Allocator,
    positions: std.ArrayList(Position),

    pub fn init(allocator: std.mem.Allocator) !PositionManager {
        return PositionManager{
            .allocator = allocator,
            .positions = std.ArrayList(Position).init(allocator),
        };
    }

    pub fn deinit(self: *PositionManager) void {
        self.positions.deinit();
    }

    /// 添加仓位
    pub fn addPosition(self: *PositionManager, position: Position) !void {
        try self.positions.append(position);
    }

    /// 关闭仓位
    pub fn closePosition(self: *PositionManager, pair: TradingPair, exit_price: Decimal) !?Position {
        for (self.positions.items, 0..) |pos, i| {
            if (pos.pair.equals(pair) and pos.status == .open) {
                var closed_position = pos;
                closed_position.exit_price = exit_price;
                closed_position.status = .closed;
                closed_position.pnl = try self.calculatePnL(closed_position);

                _ = self.positions.swapRemove(i);
                return closed_position;
            }
        }
        return null;
    }

    /// 获取指定交易对的持仓
    pub fn getPosition(self: *PositionManager, pair: TradingPair) ?Position {
        for (self.positions.items) |pos| {
            if (pos.pair.equals(pair) and pos.status == .open) {
                return pos;
            }
        }
        return null;
    }

    /// 获取开仓数量
    pub fn getOpenPositionCount(self: *PositionManager) u32 {
        var count: u32 = 0;
        for (self.positions.items) |pos| {
            if (pos.status == .open) {
                count += 1;
            }
        }
        return count;
    }

    /// 获取总敞口
    pub fn getTotalExposure(self: *PositionManager) !Decimal {
        var total = Decimal.ZERO;
        for (self.positions.items) |pos| {
            if (pos.status == .open) {
                const value = try pos.size.mul(pos.entry_price);
                total = try total.add(value);
            }
        }
        return total;
    }

    /// 计算盈亏
    fn calculatePnL(self: *PositionManager, position: Position) !Decimal {
        _ = self;

        if (position.exit_price == null) {
            return Decimal.ZERO;
        }

        const exit_price = position.exit_price.?;
        const entry_value = try position.size.mul(position.entry_price);
        const exit_value = try position.size.mul(exit_price);

        return switch (position.side) {
            .long => try exit_value.sub(entry_value),
            .short => try entry_value.sub(exit_value),
        };
    }
};
```

#### 5. MarketDataProvider (market_data.zig)

```zig
const std = @import("std");
const Candle = @import("../types/market.zig").Candle;
const TradingPair = @import("../types/market.zig").TradingPair;
const Timeframe = @import("../types/market.zig").Timeframe;
const Timestamp = @import("../types/time.zig").Timestamp;
const Decimal = @import("../types/decimal.zig").Decimal;
const IExchange = @import("../exchange/interface.zig").IExchange;

/// 市场数据提供者
pub const MarketDataProvider = struct {
    allocator: std.mem.Allocator,
    exchange: ?IExchange,

    // 数据缓存
    candle_cache: std.StringHashMap([]Candle),

    pub fn init(allocator: std.mem.Allocator, exchange: ?IExchange) !MarketDataProvider {
        return MarketDataProvider{
            .allocator = allocator,
            .exchange = exchange,
            .candle_cache = std.StringHashMap([]Candle).init(allocator),
        };
    }

    pub fn deinit(self: *MarketDataProvider) void {
        var iter = self.candle_cache.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.value_ptr.*);
        }
        self.candle_cache.deinit();
    }

    /// 获取最新价格
    pub fn getLatestPrice(self: *MarketDataProvider, pair: TradingPair) !Decimal {
        if (self.exchange) |exchange| {
            const ticker = try exchange.getTicker(pair);
            return ticker.last_price;
        }
        return error.NoExchangeConnected;
    }

    /// 获取历史 K线
    pub fn getCandles(
        self: *MarketDataProvider,
        pair: TradingPair,
        timeframe: Timeframe,
        start: Timestamp,
        end: Timestamp,
    ) ![]Candle {
        // 生成缓存键
        const cache_key = try std.fmt.allocPrint(
            self.allocator,
            "{s}_{s}_{d}_{d}",
            .{ pair.toString(), @tagName(timeframe), start.unix, end.unix },
        );
        defer self.allocator.free(cache_key);

        // 检查缓存
        if (self.candle_cache.get(cache_key)) |cached| {
            return cached;
        }

        // 从交易所获取
        if (self.exchange) |exchange| {
            const candles = try exchange.getCandles(pair, timeframe, start, end);
            try self.candle_cache.put(cache_key, candles);
            return candles;
        }

        return error.NoExchangeConnected;
    }
};
```

### 文件结构

```
src/strategy/
├── context.zig              # StrategyContext
├── risk.zig                 # RiskManager
├── executor.zig             # OrderExecutor
├── position_manager.zig     # PositionManager
├── market_data.zig          # MarketDataProvider
├── context_test.zig         # Context 测试
├── risk_test.zig            # 风控测试
├── executor_test.zig        # 执行器测试
└── position_manager_test.zig # 仓位管理测试
```

---

## 📝 任务分解

### Phase 1: 基础组件实现 (0.5天)
- [ ] 任务 1.1: 实现 PositionManager
  - 仓位列表管理
  - 盈亏计算
  - 总敞口计算
- [ ] 任务 1.2: 实现 MarketDataProvider 接口
  - 数据获取接口定义
  - 缓存机制
- [ ] 任务 1.3: 编写基础组件测试

### Phase 2: 风控和执行器 (0.25天)
- [ ] 任务 2.1: 实现 RiskManager
  - 订单验证逻辑
  - 仓位大小检查
  - 风险度计算
- [ ] 任务 2.2: 实现 OrderExecutor
  - 订单验证
  - 模拟执行
  - 真实执行接口
- [ ] 任务 2.3: 编写风控和执行器测试

### Phase 3: 上下文集成 (0.25天)
- [ ] 任务 3.1: 实现 StrategyContext
  - 组件初始化
  - 资源管理
  - 辅助方法
- [ ] 任务 3.2: 集成测试
  - 完整工作流测试
  - 内存泄漏测试
- [ ] 任务 3.3: 更新文档

---

## 🧪 测试策略

### 单元测试

#### risk_test.zig

```zig
const std = @import("std");
const testing = std.testing;
const RiskManager = @import("risk.zig").RiskManager;
const PositionManager = @import("position_manager.zig").PositionManager;
const Order = @import("../trading/order.zig").Order;
const Decimal = @import("../types/decimal.zig").Decimal;

test "RiskManager: reject order exceeding max open trades" {
    const allocator = testing.allocator;

    const config = StrategyConfig.init(
        TradingPair.init("BTC", "USDT"),
        .m15,
        2,  // max 2 open trades
        try Decimal.fromFloat(1000.0),
    );

    var risk_manager = try RiskManager.init(allocator, config);
    defer risk_manager.deinit();

    var position_manager = try PositionManager.init(allocator);
    defer position_manager.deinit();

    // 添加 2 个持仓
    try position_manager.addPosition(Position{
        .pair = TradingPair.init("BTC", "USDT"),
        .side = .long,
        .size = try Decimal.fromFloat(0.1),
        .entry_price = try Decimal.fromFloat(50000.0),
        .status = .open,
        // ...
    });
    try position_manager.addPosition(Position{
        .pair = TradingPair.init("ETH", "USDT"),
        .side = .long,
        .size = try Decimal.fromFloat(1.0),
        .entry_price = try Decimal.fromFloat(3000.0),
        .status = .open,
        // ...
    });

    // 尝试第 3 个订单
    const order = Order{
        .pair = TradingPair.init("SOL", "USDT"),
        .side = .buy,
        .order_type = .market,
        .quantity = try Decimal.fromFloat(10.0),
        .price = try Decimal.fromFloat(100.0),
        // ...
    };

    try testing.expectError(error.MaxOpenTradesReached, risk_manager.validateOrder(order, position_manager));
}

test "RiskManager: reject oversized position" {
    const allocator = testing.allocator;

    const config = StrategyConfig.init(
        TradingPair.init("BTC", "USDT"),
        .m15,
        5,
        try Decimal.fromFloat(1000.0),  // max $1000 per position
    );

    var risk_manager = try RiskManager.init(allocator, config);
    defer risk_manager.deinit();

    var position_manager = try PositionManager.init(allocator);
    defer position_manager.deinit();

    // 订单价值 = 0.1 * 50000 = $5000 > $1000
    const order = Order{
        .pair = TradingPair.init("BTC", "USDT"),
        .side = .buy,
        .order_type = .market,
        .quantity = try Decimal.fromFloat(0.1),
        .price = try Decimal.fromFloat(50000.0),
        // ...
    };

    try testing.expectError(error.PositionSizeTooLarge, risk_manager.validateOrder(order, position_manager));
}

test "RiskManager: calculate risk ratio" {
    const allocator = testing.allocator;

    const config = StrategyConfig.init(
        TradingPair.init("BTC", "USDT"),
        .m15,
        5,
        try Decimal.fromFloat(1000.0),
    );

    var risk_manager = try RiskManager.init(allocator, config);
    defer risk_manager.deinit();

    var position_manager = try PositionManager.init(allocator);
    defer position_manager.deinit();

    // 添加持仓，总价值 $2500
    try position_manager.addPosition(Position{
        .pair = TradingPair.init("BTC", "USDT"),
        .side = .long,
        .size = try Decimal.fromFloat(0.05),
        .entry_price = try Decimal.fromFloat(50000.0),  // $2500
        .status = .open,
        // ...
    });

    const risk = try risk_manager.calculateRisk(position_manager);
    // 风险度 = 2500 / (1000 * 5) = 0.5
    try testing.expectApproxEqAbs(@as(f64, 0.5), risk, 0.01);
}
```

#### executor_test.zig

```zig
const std = @import("std");
const testing = std.testing;
const OrderExecutor = @import("executor.zig").OrderExecutor;
const Order = @import("../trading/order.zig").Order;
const Logger = @import("../log/logger.zig").Logger;

test "OrderExecutor: simulate order execution" {
    const allocator = testing.allocator;
    const logger = try Logger.init(allocator, .info);
    defer logger.deinit();

    var executor = try OrderExecutor.init(allocator, null, logger);
    defer executor.deinit();

    var order = Order{
        .pair = TradingPair.init("BTC", "USDT"),
        .side = .buy,
        .order_type = .market,
        .quantity = try Decimal.fromFloat(0.1),
        .price = try Decimal.fromFloat(50000.0),
        .status = .pending,
        // ...
    };

    try executor.executeOrder(&order);

    try testing.expectEqual(OrderStatus.filled, order.status);
    try testing.expect(order.id != null);
    try testing.expect(order.filled_quantity.equals(order.quantity));
}

test "OrderExecutor: reject invalid order" {
    const allocator = testing.allocator;
    const logger = try Logger.init(allocator, .info);
    defer logger.deinit();

    var executor = try OrderExecutor.init(allocator, null, logger);
    defer executor.deinit();

    var order = Order{
        .pair = TradingPair.init("BTC", "USDT"),
        .side = .buy,
        .order_type = .market,
        .quantity = try Decimal.fromFloat(-0.1),  // Invalid: negative
        .price = try Decimal.fromFloat(50000.0),
        .status = .pending,
        // ...
    };

    try testing.expectError(error.InvalidOrderQuantity, executor.executeOrder(&order));
}
```

#### position_manager_test.zig

```zig
const std = @import("std");
const testing = std.testing;
const PositionManager = @import("position_manager.zig").PositionManager;
const Position = @import("../trading/position.zig").Position;
const Decimal = @import("../types/decimal.zig").Decimal;

test "PositionManager: add and close position" {
    const allocator = testing.allocator;

    var manager = try PositionManager.init(allocator);
    defer manager.deinit();

    const position = Position{
        .pair = TradingPair.init("BTC", "USDT"),
        .side = .long,
        .size = try Decimal.fromFloat(0.1),
        .entry_price = try Decimal.fromFloat(50000.0),
        .status = .open,
        // ...
    };

    try manager.addPosition(position);
    try testing.expectEqual(@as(u32, 1), manager.getOpenPositionCount());

    const closed = try manager.closePosition(
        TradingPair.init("BTC", "USDT"),
        try Decimal.fromFloat(51000.0),
    );

    try testing.expect(closed != null);
    try testing.expectEqual(@as(u32, 0), manager.getOpenPositionCount());

    // PnL = (51000 - 50000) * 0.1 = $100
    const expected_pnl = try Decimal.fromFloat(100.0);
    try testing.expect(closed.?.pnl.?.equals(expected_pnl));
}

test "PositionManager: calculate total exposure" {
    const allocator = testing.allocator;

    var manager = try PositionManager.init(allocator);
    defer manager.deinit();

    try manager.addPosition(Position{
        .pair = TradingPair.init("BTC", "USDT"),
        .side = .long,
        .size = try Decimal.fromFloat(0.1),
        .entry_price = try Decimal.fromFloat(50000.0),  // $5000
        .status = .open,
        // ...
    });

    try manager.addPosition(Position{
        .pair = TradingPair.init("ETH", "USDT"),
        .side = .long,
        .size = try Decimal.fromFloat(1.0),
        .entry_price = try Decimal.fromFloat(3000.0),  // $3000
        .status = .open,
        // ...
    });

    const exposure = try manager.getTotalExposure();
    const expected = try Decimal.fromFloat(8000.0);
    try testing.expect(exposure.equals(expected));
}
```

### 集成测试场景

```bash
# 编译测试
$ zig build test --summary all

# 运行特定模块测试
$ zig test src/strategy/risk_test.zig
$ zig test src/strategy/executor_test.zig
$ zig test src/strategy/position_manager_test.zig
$ zig test src/strategy/context_test.zig

# 内存泄漏检测
$ zig test src/strategy/context_test.zig -ftest-filter "no memory leak"
```

---

## 📚 相关文档

### 设计文档
- [ ] `docs/features/strategy/context.md` - StrategyContext 文档
- [ ] `docs/features/strategy/risk.md` - 风险管理文档
- [ ] `docs/features/strategy/execution.md` - 订单执行文档

### 参考资料
- [Story 013]: `STORY_013_ISTRATEGY_INTERFACE.md`
- [设计文档]: `/home/davirain/dev/zigQuant/docs/v0.3.0_STRATEGY_FRAMEWORK_DESIGN.md`
- [Hummingbot Controllers]: https://hummingbot.org/v2-strategies/controllers/

---

## 🔗 依赖关系

### 前置条件
- [x] Story 013: IStrategy 接口定义完成
- [x] `src/trading/order.zig` - Order 类型已实现
- [x] `src/trading/position.zig` - Position 类型已实现
- [x] `src/trading/account.zig` - Account 类型已实现
- [x] `src/exchange/interface.zig` - IExchange 接口已定义

### 被依赖
- Story 015: 技术指标实现需要 StrategyContext
- Story 017-019: 内置策略需要 StrategyContext
- Story 020: 回测引擎需要 StrategyContext

---

## ⚠️ 风险与挑战

### 已识别风险

1. **风险 1**: 风控逻辑复杂性
   - **影响**: 中
   - **缓解措施**:
     - Week 1 仅实现基础风控
     - 复杂风控规则在后续版本迭代
     - 提供扩展接口

2. **风险 2**: 模拟执行与真实执行的一致性
   - **影响**: 高
   - **缓解措施**:
     - 明确标记模拟模式
     - 提供统一的执行接口
     - 回测时严格使用模拟模式

### 技术挑战

1. **挑战 1**: 组件生命周期管理
   - **解决方案**: 统一由 StrategyContext 管理所有组件的创建和销毁

2. **挑战 2**: 缓存失效策略
   - **解决方案**: 简单的基于键的缓存，后续可优化为 LRU

---

## 📊 进度追踪

### 时间线
- 开始日期: 待定
- 预计完成: 开始后 1 天
- 实际完成: -

### 工作日志
| 日期 | 进展 | 备注 |
|------|------|------|
| - | - | - |

---

## ✅ 验收检查清单

Story 完成前的最终检查：

- [ ] 所有验收标准已满足
- [ ] 所有任务已完成
- [ ] 单元测试通过 (覆盖率 > 85%)
- [ ] 集成测试通过
- [ ] 代码已审查
- [ ] 文档已更新
- [ ] 无编译警告
- [ ] 内存泄漏测试通过
- [ ] API 文档注释完整
- [ ] 相关 OVERVIEW 已更新

---

## 💡 未来改进

完成此 Story 后可以考虑的优化方向:

- 优化 1: 实现更复杂的风控规则（波动率调整、相关性检查）
- 优化 2: 添加订单路由功能（智能订单拆分）
- 扩展 1: 支持多交易所仓位聚合
- 扩展 2: 实现实时风险监控和告警

---

*Last updated: 2025-12-25*
*Assignee: Claude*
