//! IStrategy Interface
//!
//! This module defines the strategy interface using Zig's VTable pattern.
//! All trading strategies must implement this interface to be used by the
//! backtesting engine and live trading system.
//!
//! Design follows Freqtrade's strategy pattern:
//! - Separate indicator calculation (populateIndicators)
//! - Dedicated entry/exit signal generation
//! - Position sizing logic
//! - Parameter and metadata access

const std = @import("std");
const Signal = @import("signal.zig").Signal;
const StrategyMetadata = @import("types.zig").StrategyMetadata;
const StrategyParameter = @import("types.zig").StrategyParameter;
const Candles = @import("../root.zig").Candles;
const Decimal = @import("../root.zig").Decimal;
const Position = @import("../backtest/position.zig").Position;
const Account = @import("../backtest/account.zig").Account;

// ============================================================================
// Strategy Context
// ============================================================================

/// Simplified strategy context for backtest environment
/// (Full context with exchange, risk manager, etc. for live trading)
pub const StrategyContext = struct {
    allocator: std.mem.Allocator,
    logger: @import("../root.zig").Logger,
};

// ============================================================================
// IStrategy Interface
// ============================================================================

/// Strategy interface using VTable pattern
/// Follows Freqtrade design: separate indicator calculation and signal generation
pub const IStrategy = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    /// Virtual function table
    pub const VTable = struct {
        /// Initialize strategy with context
        /// Called once before backtesting or live trading starts
        init: *const fn (ptr: *anyopaque, ctx: StrategyContext) anyerror!void,

        /// Deinitialize strategy and free resources
        deinit: *const fn (ptr: *anyopaque) void,

        /// Calculate and populate technical indicators
        /// Called once in backtest mode before signal generation
        /// Called on each new candle in live mode
        populateIndicators: *const fn (ptr: *anyopaque, candles: *Candles) anyerror!void,

        /// Generate entry signal for specific candle index
        /// @param candles: Candle data with populated indicators
        /// @param index: Current candle index to analyze
        /// @return Signal if entry condition met, null otherwise
        generateEntrySignal: *const fn (
            ptr: *anyopaque,
            candles: *Candles,
            index: usize,
        ) anyerror!?Signal,

        /// Generate exit signal for current position
        /// @param candles: Candle data with populated indicators
        /// @param position: Current open position
        /// @return Signal if exit condition met, null otherwise
        generateExitSignal: *const fn (
            ptr: *anyopaque,
            candles: *Candles,
            position: Position,
        ) anyerror!?Signal,

        /// Calculate position size for given signal
        /// @param signal: Entry signal
        /// @param account: Current account state
        /// @return Position size in base asset
        calculatePositionSize: *const fn (
            ptr: *anyopaque,
            signal: Signal,
            account: Account,
        ) anyerror!Decimal,

        /// Get strategy parameters (for optimization)
        /// @return Array of strategy parameters
        getParameters: *const fn (ptr: *anyopaque) []const StrategyParameter,

        /// Get strategy metadata
        /// @return Strategy metadata including name, version, risk settings
        getMetadata: *const fn (ptr: *anyopaque) StrategyMetadata,
    };

    // ========================================================================
    // Proxy Methods
    // ========================================================================

    /// Initialize strategy
    pub fn init(self: IStrategy, ctx: StrategyContext) !void {
        return self.vtable.init(self.ptr, ctx);
    }

    /// Deinitialize strategy
    pub fn deinit(self: IStrategy) void {
        self.vtable.deinit(self.ptr);
    }

    /// Populate indicators
    pub fn populateIndicators(self: IStrategy, candles: *Candles) !void {
        return self.vtable.populateIndicators(self.ptr, candles);
    }

    /// Generate entry signal
    pub fn generateEntrySignal(
        self: IStrategy,
        candles: *Candles,
        index: usize,
    ) !?Signal {
        return self.vtable.generateEntrySignal(self.ptr, candles, index);
    }

    /// Generate exit signal
    pub fn generateExitSignal(
        self: IStrategy,
        candles: *Candles,
        position: Position,
    ) !?Signal {
        return self.vtable.generateExitSignal(self.ptr, candles, position);
    }

    /// Calculate position size
    pub fn calculatePositionSize(
        self: IStrategy,
        signal: Signal,
        account: Account,
    ) !Decimal {
        return self.vtable.calculatePositionSize(self.ptr, signal, account);
    }

    /// Get parameters
    pub fn getParameters(self: IStrategy) []const StrategyParameter {
        return self.vtable.getParameters(self.ptr);
    }

    /// Get metadata
    pub fn getMetadata(self: IStrategy) StrategyMetadata {
        return self.vtable.getMetadata(self.ptr);
    }
};
