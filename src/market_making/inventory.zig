//! Inventory Management 库存管理
//!
//! 通过库存偏斜 (Inventory Skew) 技术动态调整报价，管理做市策略的仓位风险。
//!
//! ## 核心概念
//!
//! - **库存偏斜**: 根据当前持仓调整买卖报价
//! - **再平衡**: 超过阈值时主动平仓
//! - **紧急保护**: 极端情况下停止交易
//!
//! ## 偏斜原理
//!
//! ```
//! 正库存 (需要卖出) → 报价下移
//! 负库存 (需要买入) → 报价上移
//! ```

const std = @import("std");
const Decimal = @import("../core/decimal.zig").Decimal;
const Side = @import("../exchange/types.zig").Side;

// ============================================================================
// 配置
// ============================================================================

/// 库存偏斜模式
pub const SkewMode = enum {
    /// 线性偏斜: skew = ratio * factor
    linear,
    /// 指数偏斜: skew = ratio^2 * factor (库存大时偏斜更强)
    exponential,
    /// 分段偏斜: 根据阈值使用不同的系数
    tiered,
};

/// 库存管理配置
pub const InventoryConfig = struct {
    /// 目标库存 (通常为 0，表示中性持仓)
    target_inventory: Decimal = Decimal.ZERO,

    /// 最大库存绝对值
    max_inventory: Decimal,

    /// 库存偏斜系数 (0.0 - 1.0)
    /// 越大偏斜越强
    skew_factor: f64 = 0.5,

    /// 再平衡阈值 (库存/最大库存)
    /// 超过此值触发主动平仓建议
    rebalance_threshold: f64 = 0.8,

    /// 紧急平仓阈值
    emergency_threshold: f64 = 0.95,

    /// 偏斜模式
    skew_mode: SkewMode = .linear,

    /// 验证配置
    pub fn validate(self: InventoryConfig) !void {
        if (self.max_inventory.cmp(Decimal.ZERO) != .gt) {
            return error.InvalidMaxInventory;
        }
        if (self.skew_factor < 0.0 or self.skew_factor > 1.0) {
            return error.InvalidSkewFactor;
        }
        if (self.rebalance_threshold <= 0.0 or self.rebalance_threshold > 1.0) {
            return error.InvalidRebalanceThreshold;
        }
        if (self.emergency_threshold <= self.rebalance_threshold or self.emergency_threshold > 1.0) {
            return error.InvalidEmergencyThreshold;
        }
    }
};

/// 配置错误
pub const ConfigError = error{
    InvalidMaxInventory,
    InvalidSkewFactor,
    InvalidRebalanceThreshold,
    InvalidEmergencyThreshold,
};

// ============================================================================
// 再平衡动作
// ============================================================================

/// 再平衡紧急程度
pub const Urgency = enum {
    /// 正常再平衡
    normal,
    /// 紧急平仓
    emergency,
};

/// 再平衡动作
pub const RebalanceAction = struct {
    /// 方向
    direction: Side,
    /// 数量
    amount: Decimal,
    /// 紧急程度
    urgency: Urgency,
};

// ============================================================================
// 统计
// ============================================================================

/// 库存统计信息
pub const InventoryStats = struct {
    /// 当前库存
    current: Decimal,
    /// 库存比率 (-1.0 到 1.0)
    ratio: f64,
    /// 当前偏斜值
    skew: f64,
    /// 峰值库存
    peak: Decimal,
    /// 再平衡次数
    rebalance_count: u32,
    /// 是否需要再平衡
    needs_rebalance: bool,
    /// 是否需要紧急平仓
    needs_emergency: bool,
};

// ============================================================================
// 库存管理器
// ============================================================================

/// 库存管理器
pub const InventoryManager = struct {
    /// 配置
    config: InventoryConfig,
    /// 当前库存
    current_inventory: Decimal,
    /// 峰值库存 (绝对值)
    peak_inventory: Decimal,
    /// 再平衡次数
    rebalance_count: u32,

    const Self = @This();

    // ========================================================================
    // 初始化
    // ========================================================================

    /// 初始化库存管理器
    pub fn init(config: InventoryConfig) Self {
        return .{
            .config = config,
            .current_inventory = Decimal.ZERO,
            .peak_inventory = Decimal.ZERO,
            .rebalance_count = 0,
        };
    }

    /// 重置状态
    pub fn reset(self: *Self) void {
        self.current_inventory = Decimal.ZERO;
        self.peak_inventory = Decimal.ZERO;
        self.rebalance_count = 0;
    }

    // ========================================================================
    // 核心计算
    // ========================================================================

    /// 计算库存比率 (-1.0 到 1.0)
    pub fn inventoryRatio(self: *const Self) f64 {
        const max = self.config.max_inventory.toFloat();
        if (max == 0) return 0;
        return self.current_inventory.toFloat() / max;
    }

    /// 计算库存偏斜量
    /// 返回值范围: -skew_factor 到 +skew_factor
    pub fn calculateSkew(self: *const Self) f64 {
        const ratio = self.inventoryRatio();

        return switch (self.config.skew_mode) {
            .linear => ratio * self.config.skew_factor,
            .exponential => blk: {
                const sign: f64 = if (ratio >= 0) 1.0 else -1.0;
                const abs_ratio = @abs(ratio);
                // 使用平方来增加大库存时的偏斜
                break :blk sign * abs_ratio * abs_ratio * self.config.skew_factor;
            },
            .tiered => blk: {
                const abs_ratio = @abs(ratio);
                // 分段系数: >70% 使用2x, >40% 使用1.5x, 否则1x
                const tier_factor: f64 = if (abs_ratio > 0.7)
                    2.0
                else if (abs_ratio > 0.4)
                    1.5
                else
                    1.0;
                break :blk ratio * self.config.skew_factor * tier_factor;
            },
        };
    }

    /// 调整报价
    /// 正库存 → 报价下移 (鼓励卖出)
    /// 负库存 → 报价上移 (鼓励买入)
    pub fn adjustQuotes(
        self: *const Self,
        base_bid: Decimal,
        base_ask: Decimal,
        mid: Decimal,
    ) struct { bid: Decimal, ask: Decimal } {
        const skew = self.calculateSkew();

        if (@abs(skew) < 0.0001) {
            // 偏斜太小，不调整
            return .{ .bid = base_bid, .ask = base_ask };
        }

        // 计算偏斜金额
        const skew_decimal = Decimal.fromFloat(@abs(skew));
        const skew_amount = mid.mul(skew_decimal);

        if (skew > 0) {
            // 正库存 → 鼓励卖出
            // 买价下移更多，卖价下移较少 (使卖单更容易成交)
            const bid_adjustment = skew_amount;
            const ask_adjustment = skew_amount.mul(Decimal.fromFloat(0.5));
            return .{
                .bid = base_bid.sub(bid_adjustment),
                .ask = base_ask.sub(ask_adjustment),
            };
        } else {
            // 负库存 → 鼓励买入
            // 买价上移较少，卖价上移更多 (使买单更容易成交)
            const bid_adjustment = skew_amount.mul(Decimal.fromFloat(0.5));
            const ask_adjustment = skew_amount;
            return .{
                .bid = base_bid.add(bid_adjustment),
                .ask = base_ask.add(ask_adjustment),
            };
        }
    }

    // ========================================================================
    // 再平衡检查
    // ========================================================================

    /// 检查是否需要再平衡
    pub fn needsRebalance(self: *const Self) bool {
        const abs_ratio = @abs(self.inventoryRatio());
        return abs_ratio > self.config.rebalance_threshold;
    }

    /// 检查是否需要紧急平仓
    pub fn needsEmergencyClose(self: *const Self) bool {
        const abs_ratio = @abs(self.inventoryRatio());
        return abs_ratio > self.config.emergency_threshold;
    }

    /// 获取再平衡建议
    pub fn getRebalanceAction(self: *const Self) ?RebalanceAction {
        if (!self.needsRebalance()) return null;

        const ratio = self.inventoryRatio();
        const excess = self.current_inventory.sub(self.config.target_inventory);

        // 计算绝对值
        const abs_excess = if (excess.value < 0)
            Decimal{ .value = -excess.value, .scale = excess.scale }
        else
            excess;

        return .{
            .direction = if (ratio > 0) .sell else .buy,
            .amount = abs_excess,
            .urgency = if (self.needsEmergencyClose()) .emergency else .normal,
        };
    }

    // ========================================================================
    // 库存更新
    // ========================================================================

    /// 更新库存 (成交回调)
    pub fn updateInventory(self: *Self, side: Side, quantity: Decimal) void {
        if (side == .buy) {
            self.current_inventory = self.current_inventory.add(quantity);
        } else {
            self.current_inventory = self.current_inventory.sub(quantity);
        }

        // 更新峰值
        const abs_inventory = if (self.current_inventory.value < 0)
            Decimal{ .value = -self.current_inventory.value, .scale = self.current_inventory.scale }
        else
            self.current_inventory;

        if (abs_inventory.cmp(self.peak_inventory) == .gt) {
            self.peak_inventory = abs_inventory;
        }
    }

    /// 直接设置库存 (用于同步外部状态)
    pub fn setInventory(self: *Self, inventory: Decimal) void {
        self.current_inventory = inventory;

        const abs_inventory = if (inventory.value < 0)
            Decimal{ .value = -inventory.value, .scale = inventory.scale }
        else
            inventory;

        if (abs_inventory.cmp(self.peak_inventory) == .gt) {
            self.peak_inventory = abs_inventory;
        }
    }

    /// 记录再平衡
    pub fn recordRebalance(self: *Self) void {
        self.rebalance_count += 1;
    }

    // ========================================================================
    // 统计
    // ========================================================================

    /// 获取统计信息
    pub fn getStats(self: *const Self) InventoryStats {
        return .{
            .current = self.current_inventory,
            .ratio = self.inventoryRatio(),
            .skew = self.calculateSkew(),
            .peak = self.peak_inventory,
            .rebalance_count = self.rebalance_count,
            .needs_rebalance = self.needsRebalance(),
            .needs_emergency = self.needsEmergencyClose(),
        };
    }
};

// ============================================================================
// Tests
// ============================================================================

test "InventoryConfig: validation" {
    const valid_config = InventoryConfig{
        .max_inventory = Decimal.fromFloat(1.0),
        .skew_factor = 0.5,
        .rebalance_threshold = 0.8,
        .emergency_threshold = 0.95,
    };
    try valid_config.validate();
}

test "InventoryConfig: invalid max inventory" {
    const config = InventoryConfig{
        .max_inventory = Decimal.ZERO,
    };
    try std.testing.expectError(error.InvalidMaxInventory, config.validate());
}

test "InventoryConfig: invalid skew factor" {
    const config = InventoryConfig{
        .max_inventory = Decimal.fromFloat(1.0),
        .skew_factor = 1.5, // > 1.0
    };
    try std.testing.expectError(error.InvalidSkewFactor, config.validate());
}

test "InventoryManager: initialization" {
    const manager = InventoryManager.init(.{
        .max_inventory = Decimal.fromFloat(1.0),
    });

    try std.testing.expectEqual(Decimal.ZERO, manager.current_inventory);
    try std.testing.expectEqual(@as(f64, 0.0), manager.inventoryRatio());
}

test "InventoryManager: linear skew calculation" {
    var manager = InventoryManager.init(.{
        .max_inventory = Decimal.fromFloat(1.0),
        .skew_factor = 0.5,
        .skew_mode = .linear,
    });

    // 无库存
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), manager.calculateSkew(), 0.001);

    // 50% 正库存 → skew = 0.5 * 0.5 = 0.25
    manager.current_inventory = Decimal.fromFloat(0.5);
    try std.testing.expectApproxEqAbs(@as(f64, 0.25), manager.calculateSkew(), 0.001);

    // 满仓 → skew = 1.0 * 0.5 = 0.5
    manager.current_inventory = Decimal.fromFloat(1.0);
    try std.testing.expectApproxEqAbs(@as(f64, 0.5), manager.calculateSkew(), 0.001);

    // 负库存 → 负偏斜
    manager.current_inventory = Decimal.fromFloat(-0.5);
    try std.testing.expectApproxEqAbs(@as(f64, -0.25), manager.calculateSkew(), 0.001);
}

test "InventoryManager: exponential skew calculation" {
    var manager = InventoryManager.init(.{
        .max_inventory = Decimal.fromFloat(1.0),
        .skew_factor = 0.5,
        .skew_mode = .exponential,
    });

    // 50% 库存 → skew = 0.5^2 * 0.5 = 0.125
    manager.current_inventory = Decimal.fromFloat(0.5);
    try std.testing.expectApproxEqAbs(@as(f64, 0.125), manager.calculateSkew(), 0.001);

    // 满仓 → skew = 1.0^2 * 0.5 = 0.5
    manager.current_inventory = Decimal.fromFloat(1.0);
    try std.testing.expectApproxEqAbs(@as(f64, 0.5), manager.calculateSkew(), 0.001);
}

test "InventoryManager: tiered skew calculation" {
    var manager = InventoryManager.init(.{
        .max_inventory = Decimal.fromFloat(1.0),
        .skew_factor = 0.5,
        .skew_mode = .tiered,
    });

    // 30% 库存 (tier 1x) → skew = 0.3 * 0.5 * 1.0 = 0.15
    manager.current_inventory = Decimal.fromFloat(0.3);
    try std.testing.expectApproxEqAbs(@as(f64, 0.15), manager.calculateSkew(), 0.001);

    // 50% 库存 (tier 1.5x) → skew = 0.5 * 0.5 * 1.5 = 0.375
    manager.current_inventory = Decimal.fromFloat(0.5);
    try std.testing.expectApproxEqAbs(@as(f64, 0.375), manager.calculateSkew(), 0.001);

    // 80% 库存 (tier 2x) → skew = 0.8 * 0.5 * 2.0 = 0.8
    manager.current_inventory = Decimal.fromFloat(0.8);
    try std.testing.expectApproxEqAbs(@as(f64, 0.8), manager.calculateSkew(), 0.001);
}

test "InventoryManager: quote adjustment positive inventory" {
    var manager = InventoryManager.init(.{
        .max_inventory = Decimal.fromFloat(1.0),
        .skew_factor = 0.5,
        .skew_mode = .linear,
    });

    const mid = Decimal.fromInt(2000);
    const bid = Decimal.fromInt(1999);
    const ask = Decimal.fromInt(2001);

    // 50% 正库存 → 报价下移
    manager.current_inventory = Decimal.fromFloat(0.5);
    const adjusted = manager.adjustQuotes(bid, ask, mid);

    // 买价应该下移更多
    try std.testing.expect(adjusted.bid.toFloat() < bid.toFloat());
    // 卖价应该下移较少
    try std.testing.expect(adjusted.ask.toFloat() < ask.toFloat());
    // 买价下移幅度 > 卖价下移幅度
    const bid_diff = bid.toFloat() - adjusted.bid.toFloat();
    const ask_diff = ask.toFloat() - adjusted.ask.toFloat();
    try std.testing.expect(bid_diff > ask_diff);
}

test "InventoryManager: quote adjustment negative inventory" {
    var manager = InventoryManager.init(.{
        .max_inventory = Decimal.fromFloat(1.0),
        .skew_factor = 0.5,
        .skew_mode = .linear,
    });

    const mid = Decimal.fromInt(2000);
    const bid = Decimal.fromInt(1999);
    const ask = Decimal.fromInt(2001);

    // 50% 负库存 → 报价上移
    manager.current_inventory = Decimal.fromFloat(-0.5);
    const adjusted = manager.adjustQuotes(bid, ask, mid);

    // 买价应该上移较少
    try std.testing.expect(adjusted.bid.toFloat() > bid.toFloat());
    // 卖价应该上移更多
    try std.testing.expect(adjusted.ask.toFloat() > ask.toFloat());
}

test "InventoryManager: rebalance check" {
    var manager = InventoryManager.init(.{
        .max_inventory = Decimal.fromFloat(1.0),
        .rebalance_threshold = 0.8,
        .emergency_threshold = 0.95,
    });

    // 低于阈值
    manager.current_inventory = Decimal.fromFloat(0.7);
    try std.testing.expect(!manager.needsRebalance());
    try std.testing.expect(!manager.needsEmergencyClose());

    // 高于再平衡阈值
    manager.current_inventory = Decimal.fromFloat(0.85);
    try std.testing.expect(manager.needsRebalance());
    try std.testing.expect(!manager.needsEmergencyClose());

    // 高于紧急阈值
    manager.current_inventory = Decimal.fromFloat(0.98);
    try std.testing.expect(manager.needsRebalance());
    try std.testing.expect(manager.needsEmergencyClose());
}

test "InventoryManager: rebalance action" {
    var manager = InventoryManager.init(.{
        .max_inventory = Decimal.fromFloat(1.0),
        .rebalance_threshold = 0.8,
        .emergency_threshold = 0.95,
    });

    // 不需要再平衡
    manager.current_inventory = Decimal.fromFloat(0.5);
    try std.testing.expect(manager.getRebalanceAction() == null);

    // 需要正常再平衡 (卖出)
    manager.current_inventory = Decimal.fromFloat(0.85);
    const action1 = manager.getRebalanceAction().?;
    try std.testing.expect(action1.direction == .sell);
    try std.testing.expect(action1.urgency == .normal);

    // 需要紧急平仓
    manager.current_inventory = Decimal.fromFloat(0.98);
    const action2 = manager.getRebalanceAction().?;
    try std.testing.expect(action2.urgency == .emergency);

    // 负库存需要买入
    manager.current_inventory = Decimal.fromFloat(-0.85);
    const action3 = manager.getRebalanceAction().?;
    try std.testing.expect(action3.direction == .buy);
}

test "InventoryManager: update inventory" {
    var manager = InventoryManager.init(.{
        .max_inventory = Decimal.fromFloat(1.0),
    });

    // 买入增加库存
    manager.updateInventory(.buy, Decimal.fromFloat(0.3));
    try std.testing.expectApproxEqAbs(@as(f64, 0.3), manager.current_inventory.toFloat(), 0.001);

    // 再次买入
    manager.updateInventory(.buy, Decimal.fromFloat(0.2));
    try std.testing.expectApproxEqAbs(@as(f64, 0.5), manager.current_inventory.toFloat(), 0.001);

    // 卖出减少库存
    manager.updateInventory(.sell, Decimal.fromFloat(0.4));
    try std.testing.expectApproxEqAbs(@as(f64, 0.1), manager.current_inventory.toFloat(), 0.001);

    // 峰值应该是 0.5
    try std.testing.expectApproxEqAbs(@as(f64, 0.5), manager.peak_inventory.toFloat(), 0.001);
}

test "InventoryManager: stats" {
    var manager = InventoryManager.init(.{
        .max_inventory = Decimal.fromFloat(1.0),
        .skew_factor = 0.5,
        .rebalance_threshold = 0.8,
    });

    manager.current_inventory = Decimal.fromFloat(0.5);
    manager.recordRebalance();

    const stats = manager.getStats();

    try std.testing.expectApproxEqAbs(@as(f64, 0.5), stats.current.toFloat(), 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 0.5), stats.ratio, 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 0.25), stats.skew, 0.001);
    try std.testing.expectEqual(@as(u32, 1), stats.rebalance_count);
    try std.testing.expect(!stats.needs_rebalance);
}

test "InventoryManager: reset" {
    var manager = InventoryManager.init(.{
        .max_inventory = Decimal.fromFloat(1.0),
    });

    manager.current_inventory = Decimal.fromFloat(0.5);
    manager.peak_inventory = Decimal.fromFloat(0.8);
    manager.rebalance_count = 5;

    manager.reset();

    try std.testing.expectEqual(Decimal.ZERO, manager.current_inventory);
    try std.testing.expectEqual(Decimal.ZERO, manager.peak_inventory);
    try std.testing.expectEqual(@as(u32, 0), manager.rebalance_count);
}
