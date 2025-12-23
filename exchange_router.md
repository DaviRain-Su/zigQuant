 Exchange Router 架构实现计划

     背景

     问题: MVP Stories (006-012) 直接使用 Hyperliquid API，没有抽象层。这会导致：
     - CLI 直接依赖 HyperliquidClient
     - 后续添加其他交易所需要大规模重构
     - 违反架构设计原则（ARCHITECTURE.md）

     解决方案: 在 Story 006 之前实现完整的 Exchange Router 抽象层。

     用户选择:
     - ✅ 立即实现完整抽象层
     - ✅ 使用 Interface + VTable 模式（anyopaque + vtable）
     - ✅ 实现 ExchangeRegistry
     - ✅ 重构所有 Stories (006-007, 010-012)

     ---
     实现阶段

     Phase A: 核心类型和接口（2 天）

     目标: 定义统一的数据类型和 IExchange 接口

     新文件:
     1. src/exchange/types.zig - 统一数据类型
       - TradingPair (base, quote)
       - Side (buy, sell)
       - OrderType (limit, market)
       - TimeInForce (gtc, ioc, alo)
       - OrderRequest (统一订单请求格式)
       - Order (统一订单响应格式)
       - OrderStatus (pending, open, filled, cancelled, rejected)
       - Ticker (bid, ask, last, volume_24h)
       - OrderbookLevel (price, quantity, num_orders)
       - Orderbook (bids, asks, timestamp)
       - Balance (asset, total, available, locked)
       - Position (pair, side, size, entry_price, pnl, leverage)
     2. src/exchange/interface.zig - IExchange vtable 接口
     pub const IExchange = struct {
         ptr: *anyopaque,
         vtable: *const VTable,

         pub const VTable = struct {
             // 基础
             getName: *const fn (*anyopaque) []const u8,
             connect: *const fn (*anyopaque) anyerror!void,
             disconnect: *const fn (*anyopaque) void,
             isConnected: *const fn (*anyopaque) bool,

             // 市场数据 (REST)
             getTicker: *const fn (*anyopaque, TradingPair) anyerror!Ticker,
             getOrderbook: *const fn (*anyopaque, TradingPair, u32) anyerror!Orderbook,

             // 交易
             createOrder: *const fn (*anyopaque, OrderRequest) anyerror!Order,
             cancelOrder: *const fn (*anyopaque, u64) anyerror!void,
             cancelAllOrders: *const fn (*anyopaque, ?TradingPair) anyerror!u32,
             getOrder: *const fn (*anyopaque, u64) anyerror!Order,

             // 账户
             getBalance: *const fn (*anyopaque) anyerror![]Balance,
             getPositions: *const fn (*anyopaque) anyerror![]Position,
         };

         // 代理方法 (getName, connect, getTicker, createOrder, etc.)
     };
     3. src/exchange/types_test.zig - 类型测试

     验收标准:
     - ✅ 所有类型定义编译通过
     - ✅ IExchange 接口定义完整
     - ✅ 类型测试通过

     ---
     Phase B: Registry 和 Symbol Mapper（1 天）

     目标: 实现交易所注册表和符号映射

     新文件:
     1. src/exchange/registry.zig - Exchange Registry
     pub const ExchangeRegistry = struct {
         allocator: std.mem.Allocator,
         exchange: ?IExchange,  // MVP: 单交易所
         config: ?ExchangeConfig,
         logger: Logger,

         pub fn init(allocator, logger) ExchangeRegistry
         pub fn setExchange(self, exchange: IExchange, config: ExchangeConfig) !void
         pub fn getExchange(self) !IExchange
         pub fn connectAll(self) !void
         pub fn isConnected(self) bool
     };
     2. src/exchange/symbol_mapper.zig - Symbol Mapper
     pub const SymbolMapper = struct {
         pub fn toHyperliquid(pair: TradingPair) ![]const u8  // ETH-USDC -> "ETH"
         pub fn fromHyperliquid(symbol: []const u8) !TradingPair  // "ETH" -> ETH-USDC
         // Future: toBinance, toOKX, etc.
     };
     3. src/exchange/registry_test.zig - Registry 测试

     验收标准:
     - ✅ Registry 可以注册和获取交易所
     - ✅ Symbol Mapper 正确转换符号
     - ✅ 测试通过

     ---
     Phase C: Hyperliquid Connector 骨架（1 天）

     目标: 创建 HyperliquidConnector 实现 IExchange 接口

     新文件:
     1. src/exchange/hyperliquid/connector.zig - Hyperliquid Connector
     pub const HyperliquidConnector = struct {
         allocator: std.mem.Allocator,
         config: ExchangeConfig,
         http: HyperliquidClient,  // Story 006 实现
         symbol_mapper: SymbolMapper,
         logger: Logger,
         connected: bool,

         pub fn create(allocator, config, logger) !IExchange
         pub fn interface(self) IExchange  // 返回 vtable

         // VTable 实现
         fn getName(ptr: *anyopaque) []const u8
         fn connect(ptr: *anyopaque) !void
         fn getTicker(ptr: *anyopaque, pair: TradingPair) !Ticker
         fn getOrderbook(ptr: *anyopaque, pair: TradingPair, depth: u32) !Orderbook
         fn createOrder(ptr: *anyopaque, request: OrderRequest) !Order
         // ... 其他方法

         const vtable = IExchange.VTable{ .getName = getName, ... };
     };
     2. src/exchange/hyperliquid/connector_test.zig - Connector 测试

     验收标准:
     - ✅ Connector 实现所有 vtable 方法（可以是 stub）
     - ✅ 接口编译通过
     - ✅ 测试通过

     ---
     Phase D: Story 006-007 集成（随 Story 实施）

     修改:
     1. src/exchange/hyperliquid/http.zig - HTTP 客户端（Story 006）
       - 按 Story 006 规划实现
       - 被 connector.zig 调用
     2. src/exchange/hyperliquid/websocket.zig - WebSocket 客户端（Story 007）
       - 按 Story 007 规划实现
       - 被 connector.zig 调用
     3. src/exchange/hyperliquid/info_api.zig - Info API 端点
       - getAllMids, getL2Book, getUserState 等
     4. src/exchange/hyperliquid/exchange_api.zig - Exchange API 端点
       - placeOrder, cancelOrder, cancelOrders 等
     5. src/exchange/hyperliquid/auth.zig - Ed25519 签名
     6. src/exchange/hyperliquid/rate_limiter.zig - 速率限制（20 req/s）
     7. src/exchange/hyperliquid/types.zig - Hyperliquid 特定类型

     Connector 实现示例:
     fn getTicker(ptr: *anyopaque, pair: TradingPair) !Ticker {
         const self: *HyperliquidConnector = @ptrCast(@alignCast(ptr));

         // 1. 转换符号: ETH-USDC -> "ETH"
         const symbol = try self.symbol_mapper.toHyperliquid(pair);

         // 2. 调用 Info API
         const mids = try InfoAPI.getAllMids(&self.http);
         const mid_price = mids.get(symbol) orelse return error.SymbolNotFound;

         // 3. 返回统一格式
         return Ticker{
             .pair = pair,
             .bid = mid_price,
             .ask = mid_price,
             .last = mid_price,
             .volume_24h = Decimal.ZERO,
             .timestamp = Timestamp.now(),
         };
     }

     验收标准:
     - ✅ HTTP 和 WebSocket 客户端完整实现
     - ✅ Connector 所有 vtable 方法实现完整
     - ✅ 集成测试通过（连接 testnet）

     ---
     Phase E: Trading Layer 集成（Story 010-011）

     修改:
     1. src/trading/order_manager.zig - Order Manager
     pub const OrderManager = struct {
         registry: *ExchangeRegistry,  // 不再直接使用 HyperliquidClient

         pub fn submitOrder(self, order: OrderRequest) !Order {
             const exchange = try self.registry.getExchange();
             return try exchange.createOrder(order);
         }

         pub fn cancelOrder(self, order_id: u64) !void {
             const exchange = try self.registry.getExchange();
             return try exchange.cancelOrder(order_id);
         }
     };
     2. src/trading/position_tracker.zig - Position Tracker
     pub const PositionTracker = struct {
         registry: *ExchangeRegistry,

         pub fn syncAccountState(self) !void {
             const exchange = try self.registry.getExchange();
             const positions = try exchange.getPositions();
             const balance = try exchange.getBalance();
             // 更新内部状态
         }
     };

     验收标准:
     - ✅ OrderManager 通过 Registry 访问交易所
     - ✅ PositionTracker 通过 Registry 访问交易所
     - ✅ 测试通过

     ---
     Phase F: CLI 集成（Story 012）

     修改:
     1. src/cli/main.zig 或 src/main.zig - CLI 入口
     pub fn main() !void {
         // 1. 加载配置
         const config = try Config.loadFromFile(allocator, "config.json");

         // 2. 创建 Logger
         var logger = try Logger.init(allocator, config.logging);

         // 3. 创建 Registry
         var registry = ExchangeRegistry.init(allocator, logger);
         defer registry.deinit();

         // 4. 创建 Hyperliquid Connector
         const exchange = try HyperliquidConnector.create(
             allocator,
             config.exchanges[0],  // 第一个配置的交易所
             logger,
         );

         // 5. 注册交易所
         try registry.setExchange(exchange, config.exchanges[0]);
         try registry.connectAll();

         // 6. 创建 Trading 组件
         var order_mgr = try OrderManager.init(allocator, &registry, logger);
         var pos_tracker = try PositionTracker.init(allocator, &registry, logger);

         // 7. 运行 CLI
         try runCLI(&order_mgr, &pos_tracker);
     }

     验收标准:
     - ✅ CLI 通过 Registry 访问交易所
     - ✅ CLI 可以查询市场数据
     - ✅ CLI 可以下单和撤单
     - ✅ CLI 可以查询账户和仓位

     ---
     文件树

     src/
     ├── core/                          # ✅ 已完成
     │   ├── config.zig
     │   ├── decimal.zig
     │   ├── errors.zig
     │   ├── logger.zig
     │   └── time.zig
     │
     ├── exchange/                      # 🆕 NEW
     │   ├── interface.zig              # IExchange vtable (Phase A)
     │   ├── types.zig                  # 统一类型 (Phase A)
     │   ├── registry.zig               # ExchangeRegistry (Phase B)
     │   ├── symbol_mapper.zig          # SymbolMapper (Phase B)
     │   ├── types_test.zig             # 类型测试 (Phase A)
     │   ├── registry_test.zig          # Registry 测试 (Phase B)
     │   │
     │   └── hyperliquid/               # Hyperliquid 实现
     │       ├── connector.zig          # HyperliquidConnector (Phase C)
     │       ├── http.zig               # HTTP 客户端 (Story 006)
     │       ├── websocket.zig          # WebSocket (Story 007)
     │       ├── auth.zig               # Ed25519 (Story 006)
     │       ├── info_api.zig           # Info API (Story 006)
     │       ├── exchange_api.zig       # Exchange API (Story 006)
     │       ├── types.zig              # Hyperliquid 类型 (Story 006)
     │       ├── rate_limiter.zig       # 速率限制 (Story 006)
     │       └── connector_test.zig     # Connector 测试 (Phase C)
     │
     ├── trading/                       # 🆕 Trading Layer
     │   ├── order_manager.zig          # OrderManager (Story 010)
     │   ├── position_tracker.zig      # PositionTracker (Story 011)
     │   └── types.zig                  # Trading 类型
     │
     ├── cli/                           # 🆕 CLI Layer
     │   ├── main.zig                   # CLI 入口 (Story 012)
     │   ├── commands/
     │   │   ├── market.zig
     │   │   ├── order.zig
     │   │   ├── position.zig
     │   │   └── account.zig
     │   └── repl.zig
     │
     ├── main.zig                       # 项目入口
     └── root.zig                       # 模块导出

     ---
     需要更新的文件

     现有文件

     1. src/root.zig - 添加 exchange 模块导出
     // Exchange abstraction
     pub const exchange = @import("exchange/interface.zig");
     pub const IExchange = exchange.IExchange;
     pub const ExchangeRegistry = @import("exchange/registry.zig").ExchangeRegistry;
     pub const SymbolMapper = @import("exchange/symbol_mapper.zig").SymbolMapper;

     // Exchange types
     pub const TradingPair = @import("exchange/types.zig").TradingPair;
     pub const OrderRequest = @import("exchange/types.zig").OrderRequest;
     pub const Order = @import("exchange/types.zig").Order;
     // ... 其他类型
     2. build.zig - 可能需要添加新的依赖（zig-clap for CLI）

     ---
     测试策略

     单元测试

     - types_test.zig - 测试数据类型转换
     - registry_test.zig - 测试 Registry 注册和查询
     - connector_test.zig - 测试 Connector vtable 调用

     集成测试

     - 连接 Hyperliquid testnet
     - 获取 ticker 和 orderbook
     - 查询账户余额和仓位
     - 下单和撤单（小额测试）

     Mock 测试

     // src/exchange/mock/connector.zig
     pub const MockExchange = struct {
         connected: bool = false,

         pub fn interface(self: *MockExchange) IExchange {
             return .{ .ptr = self, .vtable = &vtable };
         }

         fn getName(ptr: *anyopaque) []const u8 {
             return "mock";
         }

         fn connect(ptr: *anyopaque) !void {
             const self: *MockExchange = @ptrCast(@alignCast(ptr));
             self.connected = true;
         }

         // 返回固定的 mock 数据
         fn getTicker(ptr: *anyopaque, pair: TradingPair) !Ticker { ... }

         const vtable = IExchange.VTable{ ... };
     };

     ---
     依赖关系

     实施顺序:
     1. Phase A → Phase B → Phase C (基础设施)
     2. Phase D (Story 006-007 实施时集成)
     3. Phase E (Story 010-011 实施时集成)
     4. Phase F (Story 012 实施时集成)

     关键依赖:
     - Phase C 依赖 Phase A, B
     - Phase D 依赖 Phase C
     - Phase E 依赖 Phase D
     - Phase F 依赖 Phase E

     ---
     风险和注意事项

     风险

     1. VTable 性能: anyopaque + vtable 有轻微性能开销（可接受）
     2. 类型转换复杂度: Hyperliquid → 统一格式 → Hyperliquid
     3. 错误处理: 统一错误类型需要仔细设计

     缓解措施

     1. 使用 benchmark 测试性能（如果有问题再优化）
     2. SymbolMapper 缓存常用映射
     3. 使用现有 errors.zig 错误系统

     ---
     成功标准

     Phase A-C 完成后:
     - ✅ 可以创建 MockExchange 并通过 IExchange 调用
     - ✅ Registry 可以注册和管理交易所
     - ✅ Connector 骨架编译通过

     Phase D 完成后:
     - ✅ 可以连接 Hyperliquid testnet
     - ✅ 可以通过 IExchange 获取市场数据
     - ✅ 可以通过 IExchange 下单和撤单

     Phase E-F 完成后:
     - ✅ OrderManager 和 PositionTracker 通过 Registry 工作
     - ✅ CLI 可以执行完整的交易流程
     - ✅ 所有 Story (006-012) 完成

     ---
     时间估算

     | 阶段           | 工作量 | 说明                                           |
     |----------------|--------|------------------------------------------------|
     | Phase A        | 2 天   | 类型定义 + 接口设计                            |
     | Phase B        | 1 天   | Registry + SymbolMapper                        |
     | Phase C        | 1 天   | Connector 骨架                                 |
     | Phase A-C 小计 | 4 天   | 抽象层基础                                     |
     | Phase D        | 5 天   | Story 006-007 (HTTP + WebSocket)               |
     | Phase E        | 7 天   | Story 010-011 (OrderManager + PositionTracker) |
     | Phase F        | 3 天   | Story 012 (CLI)                                |
     | 总计           | 19 天  | 完整 MVP                                       |

     ---
     下一步行动

     1. 立即开始 Phase A: 创建 types.zig 和 interface.zig
     2. 并行准备: 阅读 Hyperliquid API 文档
     3. 编写测试: 先写测试，后写实现（TDD）
     4. 持续集成: 每个 Phase 完成后立即测试

     ---
     此计划基于 ARCHITECTURE.md 设计，确保 MVP 阶段就具备良好的扩展性
