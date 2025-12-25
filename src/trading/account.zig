//! Account - 账户信息
//!
//! 基于 Hyperliquid API 规范的账户数据结构：
//! - 保证金摘要 (marginSummary, crossMarginSummary)
//! - 可提现金额 (withdrawable)
//! - 已实现盈亏追踪
//!
//! 参考: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/info-endpoint#retrieve-users-state

const std = @import("std");
const Decimal = @import("../core/decimal.zig").Decimal;

// ============================================================================
// Account
// ============================================================================

pub const Account = struct {
    // 基于真实 API: marginSummary 字段
    margin_summary: MarginSummary,

    // 基于真实 API: crossMarginSummary 字段
    cross_margin_summary: MarginSummary,

    // 基于真实 API: withdrawable 字段
    withdrawable: Decimal, // 可提现金额

    // 基于真实 API: crossMaintenanceMarginUsed
    cross_maintenance_margin_used: Decimal,

    // 本地追踪的盈亏（非 API 返回）
    total_realized_pnl: Decimal, // 总已实现盈亏（从成交累计）

    /// 保证金摘要 (基于真实 API)
    pub const MarginSummary = struct {
        account_value: Decimal, // 账户总价值 (accountValue)
        total_margin_used: Decimal, // 总已用保证金 (totalMarginUsed)
        total_ntl_pos: Decimal, // 总名义仓位价值 (totalNtlPos)
        total_raw_usd: Decimal, // 总原始 USD (totalRawUsd)
    };

    /// 初始化账户（空账户）
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

    /// 获取账户总价值
    pub fn getAccountValue(self: *const Account) Decimal {
        return self.cross_margin_summary.account_value;
    }

    /// 获取可用保证金
    pub fn getAvailableMargin(self: *const Account) Decimal {
        return self.cross_margin_summary.account_value
            .sub(self.cross_margin_summary.total_margin_used);
    }

    /// 获取保证金使用率
    pub fn getMarginUsageRate(self: *const Account) ?Decimal {
        if (self.cross_margin_summary.account_value.isZero()) return null;

        return self.cross_margin_summary.total_margin_used
            .div(self.cross_margin_summary.account_value) catch null;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "Account: init" {
    const account = Account.init();

    try std.testing.expect(account.margin_summary.account_value.isZero());
    try std.testing.expect(account.withdrawable.isZero());
}

test "Account: updateFromApiResponse" {
    var account = Account.init();

    const margin_summary = Account.MarginSummary{
        .account_value = Decimal.fromInt(10000),
        .total_margin_used = Decimal.fromInt(2000),
        .total_ntl_pos = Decimal.fromInt(20000),
        .total_raw_usd = Decimal.fromInt(10000),
    };

    account.updateFromApiResponse(
        margin_summary,
        margin_summary,
        Decimal.fromInt(8000),
        Decimal.fromInt(1500),
    );

    try std.testing.expect(account.getAccountValue().eql(Decimal.fromInt(10000)));
    try std.testing.expect(account.withdrawable.eql(Decimal.fromInt(8000)));
}

test "Account: getAvailableMargin" {
    var account = Account.init();
    account.cross_margin_summary.account_value = Decimal.fromInt(10000);
    account.cross_margin_summary.total_margin_used = Decimal.fromInt(3000);

    const available = account.getAvailableMargin();
    try std.testing.expect(available.eql(Decimal.fromInt(7000)));
}

test "Account: getMarginUsageRate" {
    var account = Account.init();
    account.cross_margin_summary.account_value = Decimal.fromInt(10000);
    account.cross_margin_summary.total_margin_used = Decimal.fromInt(2000);

    const rate = account.getMarginUsageRate().?;
    // 2000 / 10000 = 0.2
    try std.testing.expect(rate.eql(try Decimal.fromString("0.2")));
}
