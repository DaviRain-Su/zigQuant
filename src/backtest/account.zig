//! Backtest Engine - Account Management
//!
//! Tracks account balance and equity during backtest simulation.

const std = @import("std");
const Decimal = @import("../core/decimal.zig").Decimal;

// ============================================================================
// Account
// ============================================================================

/// Account balance tracking
pub const Account = struct {
    /// Starting capital
    initial_capital: Decimal,

    /// Available cash balance
    balance: Decimal,

    /// Total account value (balance + unrealized P&L)
    equity: Decimal,

    /// Cumulative fees paid
    total_commission: Decimal,

    /// Initialize account with starting capital
    pub fn init(initial_capital: Decimal) Account {
        return .{
            .initial_capital = initial_capital,
            .balance = initial_capital,
            .equity = initial_capital,
            .total_commission = Decimal.ZERO,
        };
    }

    /// Update equity based on unrealized P&L
    pub fn updateEquity(self: *Account, unrealized_pnl: Decimal) !void {
        self.equity = self.balance.add(unrealized_pnl);
    }

    /// Get net profit (equity - initial capital)
    pub fn getNetProfit(self: Account) Decimal {
        return self.equity.sub(self.initial_capital);
    }

    /// Get return as percentage
    pub fn getReturnPercent(self: Account) !f64 {
        const net_profit = self.getNetProfit();
        const return_pct = try net_profit.div(self.initial_capital);
        return return_pct.toFloat();
    }

    /// Check if account has sufficient funds
    pub fn hasSufficientFunds(self: Account, required: Decimal) bool {
        return self.balance.cmp(required) != .lt;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "Account: initialization" {
    const testing = std.testing;

    const initial_capital = Decimal.fromInt(10000);
    const account = Account.init(initial_capital);

    try testing.expect(account.initial_capital.eql(initial_capital));
    try testing.expect(account.balance.eql(initial_capital));
    try testing.expect(account.equity.eql(initial_capital));
    try testing.expect(account.total_commission.isZero());
}

test "Account: update equity with positive unrealized P&L" {
    const testing = std.testing;

    const initial_capital = Decimal.fromInt(10000);
    var account = Account.init(initial_capital);

    // Add unrealized profit of 500
    const unrealized_pnl = Decimal.fromInt(500);
    try account.updateEquity(unrealized_pnl);

    // Equity should be balance + unrealized = 10000 + 500 = 10500
    const expected_equity = Decimal.fromInt(10500);
    try testing.expect(account.equity.eql(expected_equity));

    // Balance should remain unchanged
    try testing.expect(account.balance.eql(initial_capital));
}

test "Account: update equity with negative unrealized P&L" {
    const testing = std.testing;

    const initial_capital = Decimal.fromInt(10000);
    var account = Account.init(initial_capital);

    // Add unrealized loss of -300
    const unrealized_pnl = Decimal.fromInt(-300);
    try account.updateEquity(unrealized_pnl);

    // Equity should be balance + unrealized = 10000 - 300 = 9700
    const expected_equity = Decimal.fromInt(9700);
    try testing.expect(account.equity.eql(expected_equity));
}

test "Account: net profit calculation" {
    const testing = std.testing;

    const initial_capital = Decimal.fromInt(10000);
    var account = Account.init(initial_capital);

    // Update equity to 12000
    account.equity = Decimal.fromInt(12000);

    // Net profit = 12000 - 10000 = 2000
    const net_profit = account.getNetProfit();
    try testing.expect(net_profit.eql(Decimal.fromInt(2000)));
}

test "Account: return percentage" {
    const testing = std.testing;

    const initial_capital = Decimal.fromInt(10000);
    var account = Account.init(initial_capital);

    // Update equity to 11000 (10% gain)
    account.equity = Decimal.fromInt(11000);

    const return_pct = try account.getReturnPercent();
    try testing.expectApproxEqAbs(@as(f64, 0.1), return_pct, 0.01);
}

test "Account: sufficient funds check" {
    const testing = std.testing;

    const initial_capital = Decimal.fromInt(10000);
    const account = Account.init(initial_capital);

    // Has sufficient funds for 5000
    try testing.expect(account.hasSufficientFunds(Decimal.fromInt(5000)));

    // Has sufficient funds for exactly 10000
    try testing.expect(account.hasSufficientFunds(Decimal.fromInt(10000)));

    // Doesn't have sufficient funds for 15000
    try testing.expect(!account.hasSufficientFunds(Decimal.fromInt(15000)));
}

test "Account: track commission" {
    const testing = std.testing;

    const initial_capital = Decimal.fromInt(10000);
    var account = Account.init(initial_capital);

    // Pay some fees
    account.total_commission = account.total_commission.add(Decimal.fromFloat(2.5));
    account.total_commission = account.total_commission.add(Decimal.fromFloat(3.5));

    // Total commission = 2.5 + 3.5 = 6.0
    try testing.expect(account.total_commission.eql(Decimal.fromInt(6)));
}
