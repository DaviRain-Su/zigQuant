# 下一步行动计划

**更新时间**: 2025-12-25
**当前阶段**: 文档完成 → 代码实现

---

## ✅ 已完成工作

### 文档工作 (95%+)
- ✅ 12个功能模块完整文档 (87个文件)
- ✅ 每个模块6个标准文件 (README, api, implementation, testing, bugs, changelog)
- ✅ 项目架构文档 (ARCHITECTURE.md)
- ✅ 项目状态和路线图 (PROJECT_STATUS_AND_ROADMAP.md)

### 代码实现 (~70%)
- ✅ Core层: time, decimal, errors, logger, config (100%)
- ✅ Exchange层: 抽象层 + Hyperliquid完整实现 (95%)
- ✅ Trading层: OrderManager, PositionTracker (85%)
- ✅ CLI层: 11个命令全部测试通过 (100%)

---

## 🚀 立即开始: 代码开发

### Option 1: 完善MVP (推荐) ⭐⭐⭐

**目标**: 完成 MVP v0.2.0 发布

#### Step 1: 实现 Orderbook (2天)

```bash
# 创建实现文件
touch src/market/orderbook.zig

# 参考文档
cat docs/features/orderbook/implementation.md
cat docs/features/orderbook/api.md
```

**需要实现的结构**:
```zig
// src/market/orderbook.zig

pub const Level = struct {
    price: Decimal,
    quantity: Decimal,
    num_orders: u32,
};

pub const OrderBook = struct {
    pair: TradingPair,
    bids: std.ArrayList(Level),  // 买单,从高到低
    asks: std.ArrayList(Level),  // 卖单,从低到高
    timestamp: i64,

    pub fn init(allocator: Allocator, pair: TradingPair) OrderBook;
    pub fn deinit(self: *OrderBook) void;

    pub fn applySnapshot(self: *OrderBook, snapshot: OrderbookSnapshot) !void;
    pub fn applyUpdate(self: *OrderBook, update: OrderbookUpdate) !void;
    pub fn getBestBid(self: OrderBook) ?Level;
    pub fn getBestAsk(self: OrderBook) ?Level;
    pub fn getMidPrice(self: OrderBook) ?Decimal;
    pub fn getSpread(self: OrderBook) ?Decimal;
    pub fn getSlippage(self: OrderBook, side: Side, amount: Decimal) !Decimal;
};

pub const OrderBookManager = struct {
    allocator: Allocator,
    orderbooks: std.StringHashMap(OrderBook),

    pub fn init(allocator: Allocator) OrderBookManager;
    pub fn deinit(self: *OrderBookManager) void;

    pub fn getOrCreate(self: *OrderBookManager, pair: TradingPair) !*OrderBook;
    pub fn get(self: *OrderBookManager, pair: TradingPair) ?*OrderBook;
};
```

**测试**:
```bash
zig test src/market/orderbook.zig
```

#### Step 2: WebSocket集成测试 (1天)

```bash
# 创建集成测试
touch tests/integration/websocket_test.zig
```

**测试流程**:
1. 连接 Hyperliquid testnet WebSocket
2. 订阅 orderbook 更新
3. 验证 orderbook 正确更新
4. 订阅订单更新
5. 提交订单 → 验证收到订单更新事件
6. 撤销订单 → 验证收到撤销事件

#### Step 3: 发布 MVP v0.2.0 (1天)

```bash
# 创建 CHANGELOG
vim CHANGELOG.md

# 创建项目 README
vim README.md

# 打标签
git add .
git commit -m "feat: Complete MVP v0.2.0"
git tag v0.2.0
git push origin main --tags
```

**MVP v0.2.0 功能清单**:
- ✅ Hyperliquid DEX 完整集成
- ✅ 实时市场数据 (HTTP + WebSocket)
- ✅ Orderbook 管理
- ✅ 订单管理 (下单、撤单、查询)
- ✅ 仓位跟踪和 PnL 计算
- ✅ CLI 界面 (11个命令 + REPL)
- ✅ 完整文档

---

### Option 2: 开始策略框架 (进阶) ⭐⭐

如果你想直接开始更有趣的工作:

#### Step 1: 策略接口设计 (1天)

```bash
mkdir -p src/strategy
touch src/strategy/interface.zig
```

**接口定义**:
```zig
// src/strategy/interface.zig

pub const IStrategy = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        // 生命周期
        onInit: *const fn (*anyopaque, *StrategyContext) anyerror!void,
        onStart: *const fn (*anyopaque) anyerror!void,
        onStop: *const fn (*anyopaque) void,

        // 市场数据事件
        onTick: *const fn (*anyopaque, Ticker) anyerror!void,
        onOrderbook: *const fn (*anyopaque, Orderbook) anyerror!void,

        // 订单事件
        onOrderUpdate: *const fn (*anyopaque, Order) anyerror!void,
        onOrderFill: *const fn (*anyopaque, Fill) anyerror!void,
    };
};

pub const StrategyContext = struct {
    allocator: Allocator,
    exchange: *ExchangeRegistry,
    order_mgr: *OrderManager,
    position_tracker: *PositionTracker,
    logger: Logger,

    // 策略API
    pub fn submitOrder(self: *StrategyContext, req: OrderRequest) !Order;
    pub fn cancelOrder(self: *StrategyContext, order_id: u64) !void;
    pub fn getPosition(self: *StrategyContext, pair: TradingPair) ?Position;
};
```

#### Step 2: 第一个技术指标 (1天)

```bash
mkdir -p src/strategy/indicators
touch src/strategy/indicators/sma.zig
```

**SMA实现**:
```zig
// src/strategy/indicators/sma.zig

pub const SMA = struct {
    period: u32,
    values: std.ArrayList(Decimal),
    sum: Decimal,

    pub fn init(allocator: Allocator, period: u32) SMA;
    pub fn deinit(self: *SMA) void;

    pub fn update(self: *SMA, value: Decimal) !void;
    pub fn getValue(self: SMA) ?Decimal;
    pub fn isFull(self: SMA) bool;
};
```

#### Step 3: 第一个策略 (2天)

```bash
mkdir -p src/strategy/builtin
touch src/strategy/builtin/dual_ma.zig
```

**Dual MA策略**:
```zig
// src/strategy/builtin/dual_ma.zig

pub const DualMAStrategy = struct {
    fast_ma: SMA,
    slow_ma: SMA,
    position: ?Position,

    pub fn interface(self: *DualMAStrategy) IStrategy;

    fn onTick(ptr: *anyopaque, ticker: Ticker) !void {
        const self: *DualMAStrategy = @ptrCast(@alignCast(ptr));

        // 更新MA
        try self.fast_ma.update(ticker.last);
        try self.slow_ma.update(ticker.last);

        if (!self.fast_ma.isFull() or !self.slow_ma.isFull()) return;

        const fast = self.fast_ma.getValue().?;
        const slow = self.slow_ma.getValue().?;

        // 金叉: 快线上穿慢线 → 买入
        if (fast.cmp(slow) == .gt and self.position == null) {
            // 买入信号
        }

        // 死叉: 快线下穿慢线 → 卖出
        if (fast.cmp(slow) == .lt and self.position != null) {
            // 卖出信号
        }
    }
};
```

---

## 📅 推荐时间线

### 本周 (2025-12-25 ~ 12-31)
- [ ] 实现 Orderbook (2天)
- [ ] WebSocket 集成测试 (1天)
- [ ] 发布 MVP v0.2.0 (1天)

### 下周 (2026-01-01 ~ 01-07)
- [ ] 策略接口设计 (1天)
- [ ] 实现 SMA/EMA 指标 (1天)
- [ ] 实现 Dual MA 策略 (2天)
- [ ] 策略回测测试 (1天)

### 中期 (1-2月)
- [ ] 回测系统 (2周)
- [ ] 风险管理 (1周)
- [ ] 更多策略 (持续)

---

## 🎯 选择你的路径

### 路径 A: 稳扎稳打 (推荐新手)
```
完善MVP → 发布v0.2.0 → 策略框架 → 回测系统 → 风险管理
```

### 路径 B: 快速原型 (推荐有经验开发者)
```
策略框架 → Dual MA策略 → 简单回测 → 完善MVP → 风险管理
```

### 路径 C: 并行开发 (推荐团队)
```
开发者1: Orderbook + WebSocket测试
开发者2: 策略框架 + 技术指标
开发者3: 回测系统
```

---

## 🔧 开发环境准备

### 1. 确认环境

```bash
cd /home/davirain/dev/zigQuant

# 检查Zig版本
zig version  # 应该是 0.15.2+

# 编译测试
zig build

# 运行CLI测试
zig build run -- -c config.test.json help
```

### 2. 创建开发分支

```bash
# 如果选择 Option 1: 完善MVP
git checkout -b feature/orderbook

# 如果选择 Option 2: 策略框架
git checkout -b feature/strategy-framework
```

### 3. 设置测试环境

```bash
# 确保有 Hyperliquid testnet 配置
cat config.test.json

# 确保有测试资金
# https://app.hyperliquid-testnet.xyz
```

---

## 📝 开发工作流

### 每个功能的开发流程:

1. **设计**: 查看文档,确定API
2. **TDD**: 先写测试
3. **实现**: 实现功能
4. **测试**: 运行测试,确保通过
5. **文档**: 更新文档(如果API有变化)
6. **提交**: Git commit
7. **集成**: 测试与其他模块的集成

### Git提交规范:

```
feat: 新功能
fix: Bug修复
docs: 文档更新
refactor: 重构
test: 测试
perf: 性能优化
```

---

## 📚 参考文档

### 已完成文档
- [PROJECT_STATUS_AND_ROADMAP.md](./PROJECT_STATUS_AND_ROADMAP.md) - 项目状态和路线图
- [ARCHITECTURE.md](./ARCHITECTURE.md) - 系统架构
- [docs/features/orderbook/](./features/orderbook/) - Orderbook文档
- [docs/features/order-system/](./features/order-system/) - 订单系统文档

### 需要创建的文档
- [ ] README.md - 项目介绍
- [ ] CHANGELOG.md - 版本历史
- [ ] CONTRIBUTING.md - 贡献指南 (可选)

---

## ❓ 选择建议

### 如果你想要:
- **快速看到交易结果** → 选择 Option 2 (策略框架)
- **稳定可靠的MVP** → 选择 Option 1 (完善MVP)
- **学习量化交易** → 选择 Option 1 → Option 2 → 回测
- **生产环境部署** → 完成所有(MVP → 策略 → 回测 → 风控)

### 我的推荐:
**先完成 Option 1 (Orderbook),然后立即转到 Option 2 (策略框架)**

原因:
1. Orderbook 是核心数据结构,很多功能依赖它
2. 只需2天就能完成
3. 完成后可以发布 v0.2.0,建立里程碑
4. 然后开始有趣的策略开发,保持动力

---

## 🎯 今天就开始!

选择你的路径,然后:

```bash
cd /home/davirain/dev/zigQuant

# 创建你的第一个实现文件
touch src/market/orderbook.zig

# 或者
touch src/strategy/interface.zig

# 开始编码!
vim src/market/orderbook.zig
```

**Good luck! 🚀**

---

*更新时间: 2025-12-25*
*作者: Claude (Sonnet 4.5)*
