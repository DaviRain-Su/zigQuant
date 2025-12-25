# Backtest Engine Known Issues

**Version**: v0.4.0
**Status**: Planned
**Last Updated**: 2025-12-25

---

## 📋 Bug Tracking

No known bugs at this time (module not yet implemented).

This file will track bugs discovered during the backtest engine implementation.

---

## Bug Report Template

```markdown
### BUG-XXX: [Short Description]

**Severity**: Critical / High / Medium / Low
**Status**: Open / In Progress / Fixed / Won't Fix
**Discovered**: YYYY-MM-DD
**Reporter**: [Name]

#### Description

[Detailed problem description]

#### Reproduction Steps

1. Step 1
2. Step 2
3. ...

#### Expected Behavior

[What should happen]

#### Actual Behavior

[What actually happens]

#### Environment

- Zig Version: 0.15.2
- OS: Linux/macOS/Windows
- Platform: x86_64

#### Related Code

```zig
// Code snippet
```

#### Workaround

[If a temporary workaround exists]

#### Root Cause

[Root cause analysis]

#### Fix Plan

[Proposed fix]

#### Fix Commit

Commit: `[commit hash]`
PR: `[PR number]`
Fixed in: `v0.4.x`

---
```

## Common Bug Categories

### Performance Issues
- Backtest running slower than target (< 1000 candles/s)
- Memory leaks during long backtests
- Excessive memory allocation

### Calculation Errors
- Incorrect P&L calculation
- Slippage not applied correctly
- Commission calculation errors
- Metrics calculation bugs (Sharpe ratio, drawdown, etc.)

### Logic Errors
- Look-ahead bias (using future data)
- Position sizing errors
- Order execution timing issues
- Event ordering problems

### Data Issues
- Historical data validation failures
- Missing candles not handled
- Timestamp ordering problems

---

## Example Bugs (Hypothetical)

### BUG-001: [Example] Slippage applied twice on exits

**Severity**: High
**Status**: Fixed
**Discovered**: 2025-12-25
**Reporter**: Example

#### Description

Slippage is incorrectly applied twice when closing positions: once in the signal generation and again in the order executor.

#### Reproduction Steps

1. Create backtest with 0.05% slippage
2. Run strategy that generates exit signal
3. Check fill price in trade record
4. Observed: slippage is ~0.1% instead of 0.05%

#### Expected Behavior

Slippage should only be applied once during order execution.

#### Actual Behavior

Slippage applied in both signal price and executor, compounding to ~0.1%.

#### Root Cause

Strategy's `generateExitSignal()` applies slippage to signal price, then OrderExecutor applies it again:

```zig
// In strategy
const exit_price = current_price.mul(1.0 - slippage);  // Wrong!
return Signal{ .price = exit_price, ... };

// In executor
const fill_price = signal.price.mul(1.0 - slippage);  // Applied again!
```

#### Fix Plan

Remove slippage from strategy signal generation. Only apply in OrderExecutor:

```zig
// In strategy
return Signal{ .price = current_price, ... };  // Use raw price

// In executor (unchanged)
const fill_price = signal.price.mul(1.0 - slippage);
```

#### Fix Commit

Commit: `abc123def`
Fixed in: `v0.4.1`

---

### BUG-002: [Example] Max drawdown calculation off by one

**Severity**: Medium
**Status**: Fixed
**Discovered**: 2025-12-25
**Reporter**: Example

#### Description

Maximum drawdown calculation is slightly incorrect due to off-by-one error in peak tracking.

#### Reproduction Steps

1. Create equity curve: [10000, 11000, 9000, 12000]
2. Calculate max drawdown
3. Expected: (11000 - 9000) / 11000 = 18.18%
4. Actual: 16.67%

#### Root Cause

Peak update logic has off-by-one error:

```zig
for (equity_curve[1..]) |snapshot| {  // Skips first element
    if (snapshot.equity.gt(peak)) {
        peak = snapshot.equity;
    }
    // ...
}
```

Should start from index 0 to ensure first element can be peak.

#### Fix

```zig
for (equity_curve) |snapshot| {  // Include first element
    if (snapshot.equity.gt(peak)) {
        peak = snapshot.equity;
    }
    // ...
}
```

#### Fix Commit

Commit: `def456abc`
Fixed in: `v0.4.1`

---

### BUG-003: [Example] Memory leak in equity curve tracking

**Severity**: Critical
**Status**: Fixed
**Discovered**: 2025-12-25
**Reporter**: Example

#### Description

BacktestResult's `deinit()` doesn't free equity_curve array, causing memory leak.

#### Reproduction Steps

1. Run backtest with GeneralPurposeAllocator
2. Check for leaks at program end
3. Memory leak detected

#### Expected Behavior

All allocated memory should be freed.

#### Actual Behavior

Equity curve array not freed, showing leak in GPA output.

#### Root Cause

Missing free in `deinit()`:

```zig
pub fn deinit(self: *BacktestResult, allocator: std.mem.Allocator) void {
    allocator.free(self.trades);
    // Missing: allocator.free(self.equity_curve);
}
```

#### Fix

```zig
pub fn deinit(self: *BacktestResult, allocator: std.mem.Allocator) void {
    allocator.free(self.trades);
    allocator.free(self.equity_curve);  // Added
}
```

#### Fix Commit

Commit: `789ghi123`
Fixed in: `v0.4.0`

---

## Bug Prevention Guidelines

### Code Review Checklist

- [ ] All memory allocations have corresponding frees
- [ ] No look-ahead bias in signal generation
- [ ] Slippage/commission applied exactly once
- [ ] Decimal arithmetic checked for precision
- [ ] Edge cases handled (zero trades, single trade, etc.)
- [ ] Performance benchmarks pass
- [ ] Unit tests cover critical paths

### Testing Requirements

- Unit tests for all calculation functions
- Integration tests for complete flows
- Property-based tests for invariants
- Memory leak detection on all tests
- Performance regression tests

---

**Note**: The bugs listed above are hypothetical examples for documentation purposes. Actual bugs will be tracked here during implementation.

---

**Version**: v0.4.0 (Planned)
**Status**: Design Phase
**Last Updated**: 2025-12-25
