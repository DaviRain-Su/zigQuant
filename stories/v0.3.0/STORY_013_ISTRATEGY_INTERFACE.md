# Story: IStrategy 接口和核心类型定义

**ID**: `STORY-013`
**版本**: `v0.3.0`
**创建日期**: 2025-12-25
**状态**: 📋 待开始
**优先级**: P0 (必须)
**预计工时**: 2 天

---

## 📋 需求描述

### 用户故事
作为策略开发者，我希望有一个清晰定义的 IStrategy 接口，以便我可以基于标准化的接口实现自定义交易策略，并确保策略可以被回测引擎和实时交易引擎使用。

### 背景
参考 Freqtrade 的 IStrategy 接口设计，我们需要为 zigQuant 创建一个基于 Zig 的策略接口。这个接口将：
- 定义策略的生命周期方法（初始化、清理）
- 定义信号生成方法（入场、出场）
- 定义指标计算接口
- 支持策略元数据和参数定义
- 使用 VTable 模式实现运行时多态

该接口是整个策略框架的核心，所有后续的策略实现、回测引擎、参数优化都将依赖于此接口。

### 范围
- **包含**:
  - IStrategy VTable 接口定义
  - Signal 信号类型定义
  - StrategyMetadata 元数据结构
  - StrategyParameter 参数定义
  - StrategyConfig 配置结构
  - MinimalROI 和 TrailingStop 配置
  - 完整的单元测试
  - Mock 策略实现用于测试

- **不包含**:
  - 具体策略实现（由后续 Story 实现）
  - StrategyContext 实现（Story 014）
  - 技术指标实现（Story 015）
  - 回测引擎集成（Story 020）

---

## 🎯 验收标准

- [ ] **AC1**: IStrategy 接口定义完整，包含所有必需的 VTable 方法
  - `init()`, `deinit()`, `populateIndicators()`, `generateEntrySignal()`, `generateExitSignal()`, `calculatePositionSize()`, `getParameters()`, `getMetadata()`

- [ ] **AC2**: Signal 类型定义完整，支持所有信号类型
  - `entry_long`, `entry_short`, `exit_long`, `exit_short`, `hold`
  - 包含价格、强度、时间戳、元数据等字段

- [ ] **AC3**: StrategyMetadata 结构完整，包含策略描述信息
  - 名称、版本、作者、描述、策略类型、时间周期
  - ROI 配置、止损配置、追踪止损配置

- [ ] **AC4**: StrategyParameter 支持参数定义和优化标记
  - 支持 integer, decimal, boolean, string 类型
  - 支持参数范围定义（min, max, step）
  - 支持优化标记

- [ ] **AC5**: 编译通过，无警告
  - `zig build` 成功
  - 所有类型定义编译通过

- [ ] **AC6**: Mock 策略实现并测试通过
  - MockStrategy 实现 IStrategy 接口
  - 所有接口方法可正常调用
  - VTable 多态机制工作正常

- [ ] **AC7**: 单元测试覆盖率 > 85%
  - 所有类型构造函数测试
  - Signal 创建和验证测试
  - StrategyParameter 范围验证测试
  - Mock 策略集成测试

- [ ] **AC8**: 内存安全验证通过
  - 使用 GeneralPurposeAllocator 检测
  - 无内存泄漏
  - 所有资源正确释放

---

## 🔧 技术设计

### 架构概览

```
IStrategy 接口层
    ├── interface.zig       # VTable 接口定义
    ├── types.zig          # 核心类型定义
    │   ├── StrategyMetadata
    │   ├── StrategyParameter
    │   ├── StrategyConfig
    │   ├── MinimalROI
    │   └── TrailingStopConfig
    └── signal.zig         # 信号类型定义
        ├── Signal
        ├── SignalType
        └── SignalMetadata
```

### 数据结构

#### 1. IStrategy 接口 (interface.zig)

```zig
const std = @import("std");
const Decimal = @import("../types/decimal.zig").Decimal;
const Timestamp = @import("../types/time.zig").Timestamp;
const Signal = @import("signal.zig").Signal;
const Candles = @import("candles.zig").Candles;
const Position = @import("../trading/position.zig").Position;
const Account = @import("../trading/account.zig").Account;
const StrategyMetadata = @import("types.zig").StrategyMetadata;
const StrategyParameter = @import("types.zig").StrategyParameter;
const StrategyContext = @import("context.zig").StrategyContext;

/// 策略接口 - 所有策略必须实现此接口
/// 参考 Freqtrade IStrategy 设计
pub const IStrategy = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        /// 初始化策略
        /// @param ptr - 策略实例指针
        /// @param ctx - 策略上下文
        init: *const fn (ptr: *anyopaque, ctx: StrategyContext) anyerror!void,

        /// 清理资源
        /// @param ptr - 策略实例指针
        deinit: *const fn (ptr: *anyopaque) void,

        /// 计算技术指标（类似 Freqtrade 的 populate_indicators）
        /// @param ptr - 策略实例指针
        /// @param candles - K线数据容器
        populateIndicators: *const fn (ptr: *anyopaque, candles: *Candles) anyerror!void,

        /// 生成入场信号（类似 Freqtrade 的 populate_entry_trend）
        /// @param ptr - 策略实例指针
        /// @param candles - K线数据容器
        /// @param index - 当前 K线索引
        /// @return 信号或 null
        generateEntrySignal: *const fn (ptr: *anyopaque, candles: *Candles, index: usize) anyerror!?Signal,

        /// 生成出场信号（类似 Freqtrade 的 populate_exit_trend）
        /// @param ptr - 策略实例指针
        /// @param candles - K线数据容器
        /// @param position - 当前持仓
        /// @return 信号或 null
        generateExitSignal: *const fn (ptr: *anyopaque, candles: *Candles, position: Position) anyerror!?Signal,

        /// 计算仓位大小
        /// @param ptr - 策略实例指针
        /// @param signal - 交易信号
        /// @param account - 账户信息
        /// @return 仓位大小
        calculatePositionSize: *const fn (ptr: *anyopaque, signal: Signal, account: Account) anyerror!Decimal,

        /// 获取策略参数（用于优化）
        /// @param ptr - 策略实例指针
        /// @return 参数列表
        getParameters: *const fn (ptr: *anyopaque) []const StrategyParameter,

        /// 获取策略元数据
        /// @param ptr - 策略实例指针
        /// @return 元数据
        getMetadata: *const fn (ptr: *anyopaque) StrategyMetadata,
    };

    // 代理方法 - 提供类型安全的调用接口

    pub fn init(self: IStrategy, ctx: StrategyContext) !void {
        return self.vtable.init(self.ptr, ctx);
    }

    pub fn deinit(self: IStrategy) void {
        self.vtable.deinit(self.ptr);
    }

    pub fn populateIndicators(self: IStrategy, candles: *Candles) !void {
        return self.vtable.populateIndicators(self.ptr, candles);
    }

    pub fn generateEntrySignal(self: IStrategy, candles: *Candles, index: usize) !?Signal {
        return self.vtable.generateEntrySignal(self.ptr, candles, index);
    }

    pub fn generateExitSignal(self: IStrategy, candles: *Candles, position: Position) !?Signal {
        return self.vtable.generateExitSignal(self.ptr, candles, position);
    }

    pub fn calculatePositionSize(self: IStrategy, signal: Signal, account: Account) !Decimal {
        return self.vtable.calculatePositionSize(self.ptr, signal, account);
    }

    pub fn getParameters(self: IStrategy) []const StrategyParameter {
        return self.vtable.getParameters(self.ptr);
    }

    pub fn getMetadata(self: IStrategy) StrategyMetadata {
        return self.vtable.getMetadata(self.ptr);
    }
};
```

#### 2. Signal 类型 (signal.zig)

```zig
const std = @import("std");
const Decimal = @import("../types/decimal.zig").Decimal;
const Timestamp = @import("../types/time.zig").Timestamp;
const TradingPair = @import("../types/market.zig").TradingPair;
const Side = @import("../types/market.zig").Side;

/// 交易信号类型
pub const SignalType = enum {
    entry_long,      // 做多入场
    entry_short,     // 做空入场
    exit_long,       // 多单出场
    exit_short,      // 空单出场
    hold,           // 持有

    pub fn isEntry(self: SignalType) bool {
        return self == .entry_long or self == .entry_short;
    }

    pub fn isExit(self: SignalType) bool {
        return self == .exit_long or self == .exit_short;
    }

    pub fn toString(self: SignalType) []const u8 {
        return switch (self) {
            .entry_long => "ENTRY_LONG",
            .entry_short => "ENTRY_SHORT",
            .exit_long => "EXIT_LONG",
            .exit_short => "EXIT_SHORT",
            .hold => "HOLD",
        };
    }
};

/// 指标值（用于信号元数据）
pub const IndicatorValue = struct {
    name: []const u8,
    value: Decimal,
};

/// 信号元数据
pub const SignalMetadata = struct {
    reason: []const u8,                 // 信号原因
    indicators: []const IndicatorValue, // 相关指标值

    pub fn init(allocator: std.mem.Allocator, reason: []const u8, indicators: []const IndicatorValue) !SignalMetadata {
        const reason_copy = try allocator.dupe(u8, reason);
        const indicators_copy = try allocator.dupe(IndicatorValue, indicators);
        return SignalMetadata{
            .reason = reason_copy,
            .indicators = indicators_copy,
        };
    }

    pub fn deinit(self: SignalMetadata, allocator: std.mem.Allocator) void {
        allocator.free(self.reason);
        allocator.free(self.indicators);
    }
};

/// 交易信号
pub const Signal = struct {
    /// 信号类型
    type: SignalType,

    /// 交易对
    pair: TradingPair,

    /// 方向
    side: Side,

    /// 建议价格
    price: Decimal,

    /// 信号强度 [0.0, 1.0]
    strength: f64,

    /// 信号时间
    timestamp: Timestamp,

    /// 附加信息
    metadata: ?SignalMetadata,

    pub fn init(
        signal_type: SignalType,
        pair: TradingPair,
        side: Side,
        price: Decimal,
        strength: f64,
        timestamp: Timestamp,
        metadata: ?SignalMetadata,
    ) !Signal {
        if (strength < 0.0 or strength > 1.0) {
            return error.InvalidSignalStrength;
        }

        return Signal{
            .type = signal_type,
            .pair = pair,
            .side = side,
            .price = price,
            .strength = strength,
            .timestamp = timestamp,
            .metadata = metadata,
        };
    }

    pub fn deinit(self: Signal, allocator: std.mem.Allocator) void {
        if (self.metadata) |metadata| {
            metadata.deinit(allocator);
        }
    }

    pub fn isValid(self: Signal) bool {
        return self.strength >= 0.0 and self.strength <= 1.0;
    }
};
```

#### 3. Strategy Types (types.zig)

```zig
const std = @import("std");
const Decimal = @import("../types/decimal.zig").Decimal;
const TradingPair = @import("../types/market.zig").TradingPair;
const Timeframe = @import("../types/market.zig").Timeframe;

/// 策略类型
pub const StrategyType = enum {
    trend_following,    // 趋势跟随
    mean_reversion,     // 均值回归
    breakout,          // 突破
    arbitrage,         // 套利（Hummingbot）
    market_making,     // 做市（Hummingbot）
    grid_trading,      // 网格交易
    custom,            // 自定义
};

/// ROI 目标
pub const ROITarget = struct {
    time_minutes: u32,
    profit_ratio: Decimal,

    pub fn init(time_minutes: u32, profit_ratio: Decimal) ROITarget {
        return .{
            .time_minutes = time_minutes,
            .profit_ratio = profit_ratio,
        };
    }
};

/// 最小 ROI 配置（Freqtrade 风格）
pub const MinimalROI = struct {
    targets: []const ROITarget,

    pub fn init(targets: []const ROITarget) MinimalROI {
        return .{ .targets = targets };
    }

    pub fn deinit(self: MinimalROI, allocator: std.mem.Allocator) void {
        allocator.free(self.targets);
    }
};

/// 追踪止损配置（Freqtrade 风格）
pub const TrailingStopConfig = struct {
    enabled: bool,
    positive_offset: Decimal,      // 正收益后才启动
    only_offset_is_reached: bool,

    pub fn init(enabled: bool, positive_offset: Decimal, only_offset_is_reached: bool) TrailingStopConfig {
        return .{
            .enabled = enabled,
            .positive_offset = positive_offset,
            .only_offset_is_reached = only_offset_is_reached,
        };
    }
};

/// 策略元数据（参考 Freqtrade）
pub const StrategyMetadata = struct {
    name: []const u8,
    version: []const u8,
    author: []const u8,
    description: []const u8,

    /// 策略类型
    strategy_type: StrategyType,

    /// 时间周期
    timeframe: Timeframe,

    /// 启动需要的蜡烛数
    startup_candle_count: u32,

    /// 最小 ROI 目标
    minimal_roi: MinimalROI,

    /// 止损百分比
    stoploss: Decimal,

    /// 追踪止损配置
    trailing_stop: ?TrailingStopConfig,

    pub fn deinit(self: StrategyMetadata, allocator: std.mem.Allocator) void {
        self.minimal_roi.deinit(allocator);
    }
};

/// 参数类型
pub const ParameterType = enum {
    integer,
    decimal,
    boolean,
    string,
};

/// 参数值
pub const ParameterValue = union(ParameterType) {
    integer: i64,
    decimal: Decimal,
    boolean: bool,
    string: []const u8,

    pub fn equals(self: ParameterValue, other: ParameterValue) bool {
        return switch (self) {
            .integer => |v| v == other.integer,
            .decimal => |v| v.equals(other.decimal),
            .boolean => |v| v == other.boolean,
            .string => |v| std.mem.eql(u8, v, other.string),
        };
    }
};

/// 参数范围
pub const ParameterRange = union(enum) {
    integer: struct { min: i64, max: i64, step: i64 },
    decimal: struct { min: Decimal, max: Decimal, step: Decimal },

    pub fn validate(self: ParameterRange, value: ParameterValue) bool {
        return switch (self) {
            .integer => |range| {
                const v = value.integer;
                return v >= range.min and v <= range.max;
            },
            .decimal => |range| {
                const v = value.decimal;
                return v.gte(range.min) and v.lte(range.max);
            },
        };
    }
};

/// 策略参数定义（参考 Freqtrade IntParameter/DecimalParameter）
pub const StrategyParameter = struct {
    name: []const u8,
    type: ParameterType,
    default_value: ParameterValue,
    range: ?ParameterRange,
    optimize: bool,  // 是否参与优化

    pub fn init(
        name: []const u8,
        param_type: ParameterType,
        default_value: ParameterValue,
        range: ?ParameterRange,
        optimize: bool,
    ) !StrategyParameter {
        // 验证类型匹配
        if (@intFromEnum(param_type) != @intFromEnum(default_value)) {
            return error.TypeMismatch;
        }

        // 验证默认值在范围内
        if (range) |r| {
            if (!r.validate(default_value)) {
                return error.DefaultValueOutOfRange;
            }
        }

        return StrategyParameter{
            .name = name,
            .type = param_type,
            .default_value = default_value,
            .range = range,
            .optimize = optimize,
        };
    }
};

/// 策略配置
pub const StrategyConfig = struct {
    pair: TradingPair,
    timeframe: Timeframe,
    max_open_trades: u32,
    stake_amount: Decimal,

    pub fn init(
        pair: TradingPair,
        timeframe: Timeframe,
        max_open_trades: u32,
        stake_amount: Decimal,
    ) StrategyConfig {
        return .{
            .pair = pair,
            .timeframe = timeframe,
            .max_open_trades = max_open_trades,
            .stake_amount = stake_amount,
        };
    }
};
```

### 文件结构

```
src/strategy/
├── interface.zig           # IStrategy 接口定义
├── types.zig              # 策略类型定义
├── signal.zig             # 信号类型定义
├── interface_test.zig     # 接口测试
├── types_test.zig         # 类型测试
└── signal_test.zig        # 信号测试
```

---

## 📝 任务分解

### Phase 1: 设计与准备 (0.5天)
- [ ] 任务 1.1: 创建文件结构和模块骨架
- [ ] 任务 1.2: 定义 Signal 相关类型（signal.zig）
- [ ] 任务 1.3: 定义 Strategy 类型（types.zig）
- [ ] 任务 1.4: 编写测试骨架

### Phase 2: 核心实现 (1天)
- [ ] 任务 2.1: 实现 Signal 类型和方法
  - SignalType 枚举和辅助方法
  - SignalMetadata 结构
  - Signal 结构和验证逻辑
- [ ] 任务 2.2: 实现 Strategy 类型
  - StrategyMetadata 结构
  - StrategyParameter 和验证逻辑
  - MinimalROI 和 TrailingStopConfig
  - StrategyConfig 结构
- [ ] 任务 2.3: 实现 IStrategy 接口
  - VTable 定义
  - 代理方法实现
  - Mock 策略实现用于测试

### Phase 3: 测试与文档 (0.5天)
- [ ] 任务 3.1: 编写单元测试
  - Signal 创建和验证测试
  - StrategyParameter 范围验证测试
  - ParameterValue 类型测试
  - Mock 策略集成测试
- [ ] 任务 3.2: 内存泄漏测试
  - 使用 GeneralPurposeAllocator 验证
  - 所有 deinit 正确调用
- [ ] 任务 3.3: 更新文档
  - 添加 API 文档注释
  - 创建使用示例

---

## 🧪 测试策略

### 单元测试

#### signal_test.zig

```zig
const std = @import("std");
const testing = std.testing;
const Signal = @import("signal.zig").Signal;
const SignalType = @import("signal.zig").SignalType;
const Decimal = @import("../types/decimal.zig").Decimal;

test "Signal: create valid signal" {
    const signal = try Signal.init(
        .entry_long,
        TradingPair.init("BTC", "USDT"),
        .buy,
        try Decimal.fromFloat(50000.0),
        0.8,
        Timestamp.now(),
        null,
    );

    try testing.expect(signal.isValid());
    try testing.expectEqual(SignalType.entry_long, signal.type);
    try testing.expectEqual(@as(f64, 0.8), signal.strength);
}

test "Signal: reject invalid strength" {
    const result = Signal.init(
        .entry_long,
        TradingPair.init("BTC", "USDT"),
        .buy,
        try Decimal.fromFloat(50000.0),
        1.5,  // Invalid: > 1.0
        Timestamp.now(),
        null,
    );

    try testing.expectError(error.InvalidSignalStrength, result);
}

test "SignalType: isEntry and isExit" {
    try testing.expect(SignalType.entry_long.isEntry());
    try testing.expect(!SignalType.entry_long.isExit());
    try testing.expect(SignalType.exit_long.isExit());
    try testing.expect(!SignalType.exit_long.isEntry());
}

test "SignalMetadata: create and deinit" {
    const allocator = testing.allocator;

    const indicators = [_]IndicatorValue{
        .{ .name = "sma_20", .value = try Decimal.fromFloat(50000.0) },
        .{ .name = "rsi_14", .value = try Decimal.fromFloat(65.0) },
    };

    const metadata = try SignalMetadata.init(
        allocator,
        "SMA crossover",
        &indicators,
    );
    defer metadata.deinit(allocator);

    try testing.expectEqualStrings("SMA crossover", metadata.reason);
    try testing.expectEqual(@as(usize, 2), metadata.indicators.len);
}
```

#### types_test.zig

```zig
const std = @import("std");
const testing = std.testing;
const StrategyParameter = @import("types.zig").StrategyParameter;
const ParameterValue = @import("types.zig").ParameterValue;
const ParameterRange = @import("types.zig").ParameterRange;
const ParameterType = @import("types.zig").ParameterType;
const Decimal = @import("../types/decimal.zig").Decimal;

test "StrategyParameter: create integer parameter" {
    const param = try StrategyParameter.init(
        "fast_period",
        .integer,
        ParameterValue{ .integer = 10 },
        ParameterRange{ .integer = .{ .min = 5, .max = 50, .step = 1 } },
        true,
    );

    try testing.expectEqualStrings("fast_period", param.name);
    try testing.expectEqual(ParameterType.integer, param.type);
    try testing.expectEqual(@as(i64, 10), param.default_value.integer);
    try testing.expect(param.optimize);
}

test "StrategyParameter: reject out of range default" {
    const result = StrategyParameter.init(
        "bad_param",
        .integer,
        ParameterValue{ .integer = 100 },  // Out of range
        ParameterRange{ .integer = .{ .min = 5, .max = 50, .step = 1 } },
        true,
    );

    try testing.expectError(error.DefaultValueOutOfRange, result);
}

test "StrategyParameter: reject type mismatch" {
    const result = StrategyParameter.init(
        "bad_param",
        .integer,
        ParameterValue{ .decimal = try Decimal.fromInt(10) },  // Type mismatch
        null,
        false,
    );

    try testing.expectError(error.TypeMismatch, result);
}

test "ParameterRange: validate integer value" {
    const range = ParameterRange{ .integer = .{ .min = 10, .max = 100, .step = 5 } };

    try testing.expect(range.validate(ParameterValue{ .integer = 50 }));
    try testing.expect(!range.validate(ParameterValue{ .integer = 5 }));
    try testing.expect(!range.validate(ParameterValue{ .integer = 150 }));
}

test "ParameterValue: equals comparison" {
    const v1 = ParameterValue{ .integer = 42 };
    const v2 = ParameterValue{ .integer = 42 };
    const v3 = ParameterValue{ .integer = 24 };

    try testing.expect(v1.equals(v2));
    try testing.expect(!v1.equals(v3));
}

test "MinimalROI: create and deinit" {
    const allocator = testing.allocator;

    const targets = try allocator.dupe(ROITarget, &[_]ROITarget{
        ROITarget.init(0, try Decimal.fromFloat(0.02)),
        ROITarget.init(30, try Decimal.fromFloat(0.01)),
    });

    const roi = MinimalROI.init(targets);
    defer roi.deinit(allocator);

    try testing.expectEqual(@as(usize, 2), roi.targets.len);
}
```

#### interface_test.zig

```zig
const std = @import("std");
const testing = std.testing;
const IStrategy = @import("interface.zig").IStrategy;
const Signal = @import("signal.zig").Signal;
const StrategyMetadata = @import("types.zig").StrategyMetadata;

// Mock 策略用于测试
const MockStrategy = struct {
    allocator: std.mem.Allocator,
    initialized: bool,

    pub fn create(allocator: std.mem.Allocator) !IStrategy {
        const self = try allocator.create(MockStrategy);
        self.* = .{
            .allocator = allocator,
            .initialized = false,
        };

        return IStrategy{
            .ptr = self,
            .vtable = &vtable,
        };
    }

    fn initImpl(ptr: *anyopaque, ctx: StrategyContext) !void {
        const self: *MockStrategy = @ptrCast(@alignCast(ptr));
        _ = ctx;
        self.initialized = true;
    }

    fn deinitImpl(ptr: *anyopaque) void {
        const self: *MockStrategy = @ptrCast(@alignCast(ptr));
        self.allocator.destroy(self);
    }

    fn populateIndicatorsImpl(ptr: *anyopaque, candles: *Candles) !void {
        _ = ptr;
        _ = candles;
        // Mock implementation
    }

    fn generateEntrySignalImpl(ptr: *anyopaque, candles: *Candles, index: usize) !?Signal {
        _ = ptr;
        _ = candles;
        _ = index;
        return null;  // Mock returns no signal
    }

    fn generateExitSignalImpl(ptr: *anyopaque, candles: *Candles, pos: Position) !?Signal {
        _ = ptr;
        _ = candles;
        _ = pos;
        return null;
    }

    fn calculatePositionSizeImpl(ptr: *anyopaque, signal: Signal, account: Account) !Decimal {
        _ = ptr;
        _ = signal;
        _ = account;
        return try Decimal.fromFloat(1.0);
    }

    fn getParametersImpl(ptr: *anyopaque) []const StrategyParameter {
        _ = ptr;
        return &[_]StrategyParameter{};
    }

    fn getMetadataImpl(ptr: *anyopaque) StrategyMetadata {
        _ = ptr;
        return StrategyMetadata{
            .name = "MockStrategy",
            .version = "1.0.0",
            .author = "Test",
            .description = "Mock strategy for testing",
            .strategy_type = .custom,
            .timeframe = .m15,
            .startup_candle_count = 0,
            .minimal_roi = MinimalROI.init(&[_]ROITarget{}),
            .stoploss = try Decimal.fromFloat(-0.05),
            .trailing_stop = null,
        };
    }

    const vtable = IStrategy.VTable{
        .init = initImpl,
        .deinit = deinitImpl,
        .populateIndicators = populateIndicatorsImpl,
        .generateEntrySignal = generateEntrySignalImpl,
        .generateExitSignal = generateExitSignalImpl,
        .calculatePositionSize = calculatePositionSizeImpl,
        .getParameters = getParametersImpl,
        .getMetadata = getMetadataImpl,
    };
};

test "IStrategy: create and call mock strategy" {
    const allocator = testing.allocator;

    const strategy = try MockStrategy.create(allocator);
    defer strategy.deinit();

    const metadata = strategy.getMetadata();
    try testing.expectEqualStrings("MockStrategy", metadata.name);
}

test "IStrategy: VTable polymorphism works" {
    const allocator = testing.allocator;

    const strategy = try MockStrategy.create(allocator);
    defer strategy.deinit();

    // Test that we can call through the interface
    const params = strategy.getParameters();
    try testing.expectEqual(@as(usize, 0), params.len);

    const metadata = strategy.getMetadata();
    try testing.expectEqual(StrategyType.custom, metadata.strategy_type);
}

test "IStrategy: no memory leak" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            @panic("Memory leak detected!");
        }
    }
    const allocator = gpa.allocator();

    const strategy = try MockStrategy.create(allocator);
    defer strategy.deinit();

    _ = strategy.getMetadata();
    _ = strategy.getParameters();
}
```

### 集成测试场景

```bash
# 编译测试
$ zig build test --summary all

# 运行特定测试
$ zig test src/strategy/interface_test.zig
$ zig test src/strategy/types_test.zig
$ zig test src/strategy/signal_test.zig

# 内存泄漏检测
$ zig test src/strategy/interface_test.zig -ftest-filter "no memory leak"
```

---

## 📚 相关文档

### 设计文档
- [ ] `docs/features/strategy/README.md` - 策略框架概览
- [ ] `docs/features/strategy/interface.md` - IStrategy 接口文档
- [ ] `docs/features/strategy/types.md` - 类型定义文档

### 参考资料
- [设计文档]: `/home/davirain/dev/zigQuant/docs/v0.3.0_STRATEGY_FRAMEWORK_DESIGN.md`
- [Freqtrade IStrategy]: https://www.freqtrade.io/en/stable/strategy-customization/
- [Zig VTable Pattern]: https://zig.news/david_vanderson/interfaces-in-zig-o1c

---

## 🔗 依赖关系

### 前置条件
- [ ] `src/types/decimal.zig` - Decimal 类型已实现 (v0.2.0)
- [ ] `src/types/time.zig` - Timestamp 类型已实现 (v0.2.0)
- [ ] `src/types/market.zig` - TradingPair, Side, Timeframe 已实现 (v0.2.0)

### 被依赖
- Story 014: StrategyContext 实现需要 IStrategy 接口
- Story 015: 技术指标实现需要 Signal 类型
- Story 017-019: 内置策略需要实现 IStrategy 接口
- Story 020: 回测引擎需要 IStrategy 接口

---

## ⚠️ 风险与挑战

### 已识别风险

1. **风险 1**: VTable 模式的性能开销
   - **影响**: 中
   - **缓解措施**:
     - 使用 inline 优化代理方法
     - 性能测试验证开销可接受（目标 < 1ms）
     - 如性能不达标，考虑使用 comptime 策略选择

2. **风险 2**: 接口设计的扩展性
   - **影响**: 高
   - **缓解措施**:
     - 参考成熟框架（Freqtrade）的接口设计
     - 预留扩展点（metadata 使用可选字段）
     - 在 Week 1 完成后进行设计评审

3. **风险 3**: 内存管理复杂性
   - **影响**: 中
   - **缓解措施**:
     - 明确所有权规则（谁分配谁释放）
     - 提供清晰的 deinit 模式
     - 使用 GeneralPurposeAllocator 严格检测

### 技术挑战

1. **挑战 1**: Zig 的 VTable 实现
   - **解决方案**: 参考 Zig 标准库的 `std.mem.Allocator` 设计模式

2. **挑战 2**: 类型安全的参数系统
   - **解决方案**: 使用 tagged union 确保类型安全，在编译时检查类型匹配

---

## 📊 进度追踪

### 时间线
- 开始日期: 待定
- 预计完成: 开始后 2 天
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
- [ ] Mock 策略测试通过
- [ ] 代码已审查
- [ ] 文档已更新
- [ ] 无编译警告
- [ ] 内存泄漏测试通过
- [ ] API 文档注释完整
- [ ] 相关 OVERVIEW 已更新

---

## 💡 未来改进

完成此 Story 后可以考虑的优化方向：

- 优化 1: 添加策略验证器，在初始化时检查策略配置合法性
- 优化 2: 支持策略热重载（动态加载策略）
- 扩展 1: 添加更多策略类型（如组合策略、ML 策略）
- 扩展 2: 支持策略版本管理和迁移

---

*Last updated: 2025-12-25*
*Assignee: Claude*
