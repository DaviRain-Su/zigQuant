//! Market Making Module
//!
//! This module provides components for market making strategies:
//! - Clock-driven execution mode for periodic quote updates
//! - IClockStrategy interface for clock-driven strategies
//! - Pure Market Making strategy
//! - Inventory Management with skew adjustments
//! - Cross-Exchange Arbitrage
//!
//! ## Story 033: Clock-Driven Mode
//!
//! The Clock scheduler triggers strategies at fixed time intervals,
//! suitable for market making and other strategies that need periodic updates.
//!
//! ## Story 034: Pure Market Making
//!
//! Basic market making strategy that places orders on both sides of the mid price.
//!
//! ## Story 035: Inventory Management
//!
//! Inventory-based quote adjustment to manage position risk through skew.
//!
//! ## Story 037: Cross-Exchange Arbitrage
//!
//! Monitors price differences between exchanges and executes simultaneous
//! buy/sell operations for risk-free profit.
//!
//! ## Usage
//!
//! ```zig
//! const mm = @import("market_making");
//!
//! // Create clock with 100ms interval
//! var clock = try mm.Clock.init(allocator, 100);
//! defer clock.deinit();
//!
//! // Create Pure Market Making strategy
//! var strategy = try mm.PureMarketMaking.init(allocator, config, &cache);
//! defer strategy.deinit();
//!
//! // Register strategy
//! try clock.addStrategy(strategy.asClockStrategy());
//!
//! // Run clock (blocking)
//! try clock.start();
//! ```

// Sub-modules
pub const clock = @import("clock.zig");
pub const interfaces = @import("interfaces.zig");
pub const types = @import("types.zig");
pub const pure_mm = @import("pure_mm.zig");
pub const inventory = @import("inventory.zig");
pub const arbitrage = @import("arbitrage.zig");

// Re-export Clock types (Story 033)
pub const Clock = clock.Clock;
pub const ClockStats = clock.ClockStats;
pub const ClockError = clock.ClockError;
pub const SimpleTestStrategy = clock.SimpleTestStrategy;
pub const IClockStrategy = interfaces.IClockStrategy;

// Re-export shared types
pub const OrderInfo = types.OrderInfo;
pub const OrderFill = types.OrderFill;
pub const MMStats = types.MMStats;
pub const QuoteUpdate = types.QuoteUpdate;

// Re-export Pure Market Making types (Story 034)
pub const PureMarketMaking = pure_mm.PureMarketMaking;
pub const PureMMConfig = pure_mm.PureMMConfig;
pub const ConfigError = pure_mm.ConfigError;

// Re-export Inventory Management types (Story 035)
pub const InventoryManager = inventory.InventoryManager;
pub const InventoryConfig = inventory.InventoryConfig;
pub const SkewMode = inventory.SkewMode;
pub const RebalanceAction = inventory.RebalanceAction;
pub const InventoryStats = inventory.InventoryStats;

// Re-export Arbitrage types (Story 037)
pub const CrossExchangeArbitrage = arbitrage.CrossExchangeArbitrage;
pub const ArbitrageConfig = arbitrage.ArbitrageConfig;
pub const ArbitrageOpportunity = arbitrage.ArbitrageOpportunity;
pub const ArbitrageResult = arbitrage.ArbitrageResult;
pub const ArbStats = arbitrage.ArbStats;
pub const Quote = arbitrage.Quote;
pub const Direction = arbitrage.Direction;

// ============================================================================
// Tests
// ============================================================================

test {
    const std = @import("std");
    std.testing.refAllDecls(@This());
}
