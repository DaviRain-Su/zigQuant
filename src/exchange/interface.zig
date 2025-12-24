//! Exchange Interface - Unified IExchange interface using VTable pattern
//!
//! This module defines the IExchange interface that all exchange connectors must implement.
//! Uses the VTable pattern (anyopaque + vtable) for runtime polymorphism.
//!
//! Design principles:
//! - Runtime polymorphism without overhead of @TypeOf(@as())
//! - Type-safe method dispatch
//! - Extensible: Easy to add new exchanges
//! - Testable: Can create mock exchanges for testing

const std = @import("std");
const types = @import("types.zig");

// Re-export types for convenience
pub const TradingPair = types.TradingPair;
pub const Side = types.Side;
pub const OrderType = types.OrderType;
pub const TimeInForce = types.TimeInForce;
pub const OrderStatus = types.OrderStatus;
pub const OrderRequest = types.OrderRequest;
pub const Order = types.Order;
pub const Ticker = types.Ticker;
pub const Orderbook = types.Orderbook;
pub const Balance = types.Balance;
pub const Position = types.Position;

// ============================================================================
// IExchange Interface
// ============================================================================

/// IExchange - Unified exchange interface
///
/// All exchange connectors must implement this interface by providing
/// a VTable with function pointers to their implementations.
///
/// Example usage:
/// ```zig
/// const exchange: IExchange = hyperliquid_connector.interface();
/// const ticker = try exchange.getTicker(.{ .base = "BTC", .quote = "USDC" });
/// ```
pub const IExchange = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    /// VTable containing function pointers for all exchange operations
    pub const VTable = struct {
        // ====================================================================
        // Basic Operations
        // ====================================================================

        /// Get exchange name (e.g., "hyperliquid", "binance")
        getName: *const fn (ptr: *anyopaque) []const u8,

        /// Connect to the exchange (initialize HTTP/WS clients)
        connect: *const fn (ptr: *anyopaque) anyerror!void,

        /// Disconnect from the exchange (cleanup resources)
        disconnect: *const fn (ptr: *anyopaque) void,

        /// Check if connected to the exchange
        isConnected: *const fn (ptr: *anyopaque) bool,

        // ====================================================================
        // Market Data (REST)
        // ====================================================================

        /// Get ticker for a trading pair
        getTicker: *const fn (ptr: *anyopaque, pair: TradingPair) anyerror!Ticker,

        /// Get orderbook for a trading pair
        /// depth: number of price levels to retrieve (e.g., 10, 20, 50)
        getOrderbook: *const fn (ptr: *anyopaque, pair: TradingPair, depth: u32) anyerror!Orderbook,

        // ====================================================================
        // Trading Operations
        // ====================================================================

        /// Create a new order
        createOrder: *const fn (ptr: *anyopaque, request: OrderRequest) anyerror!Order,

        /// Cancel an order by exchange order ID
        cancelOrder: *const fn (ptr: *anyopaque, order_id: u64) anyerror!void,

        /// Cancel all orders (optionally filtered by trading pair)
        /// Returns the number of orders cancelled
        cancelAllOrders: *const fn (ptr: *anyopaque, pair: ?TradingPair) anyerror!u32,

        /// Get order status by exchange order ID
        getOrder: *const fn (ptr: *anyopaque, order_id: u64) anyerror!Order,

        /// Get all open orders (optionally filtered by trading pair)
        getOpenOrders: *const fn (ptr: *anyopaque, pair: ?TradingPair) anyerror![]Order,

        // ====================================================================
        // Account Operations
        // ====================================================================

        /// Get account balance for all assets
        getBalance: *const fn (ptr: *anyopaque) anyerror![]Balance,

        /// Get all open positions
        getPositions: *const fn (ptr: *anyopaque) anyerror![]Position,
    };

    // ========================================================================
    // Proxy Methods (delegate to vtable)
    // ========================================================================

    /// Get exchange name
    pub fn getName(self: IExchange) []const u8 {
        return self.vtable.getName(self.ptr);
    }

    /// Connect to exchange
    pub fn connect(self: IExchange) !void {
        return self.vtable.connect(self.ptr);
    }

    /// Disconnect from exchange
    pub fn disconnect(self: IExchange) void {
        return self.vtable.disconnect(self.ptr);
    }

    /// Check if connected
    pub fn isConnected(self: IExchange) bool {
        return self.vtable.isConnected(self.ptr);
    }

    /// Get ticker
    pub fn getTicker(self: IExchange, pair: TradingPair) !Ticker {
        return self.vtable.getTicker(self.ptr, pair);
    }

    /// Get orderbook
    pub fn getOrderbook(self: IExchange, pair: TradingPair, depth: u32) !Orderbook {
        return self.vtable.getOrderbook(self.ptr, pair, depth);
    }

    /// Create order
    pub fn createOrder(self: IExchange, request: OrderRequest) !Order {
        return self.vtable.createOrder(self.ptr, request);
    }

    /// Cancel order
    pub fn cancelOrder(self: IExchange, order_id: u64) !void {
        return self.vtable.cancelOrder(self.ptr, order_id);
    }

    /// Cancel all orders
    pub fn cancelAllOrders(self: IExchange, pair: ?TradingPair) !u32 {
        return self.vtable.cancelAllOrders(self.ptr, pair);
    }

    /// Get order
    pub fn getOrder(self: IExchange, order_id: u64) !Order {
        return self.vtable.getOrder(self.ptr, order_id);
    }

    /// Get open orders
    pub fn getOpenOrders(self: IExchange, pair: ?TradingPair) ![]Order {
        return self.vtable.getOpenOrders(self.ptr, pair);
    }

    /// Get balance
    pub fn getBalance(self: IExchange) ![]Balance {
        return self.vtable.getBalance(self.ptr);
    }

    /// Get positions
    pub fn getPositions(self: IExchange) ![]Position {
        return self.vtable.getPositions(self.ptr);
    }
};

// ============================================================================
// Tests
// ============================================================================

test "IExchange: interface compiles" {
    // Just verify the interface compiles correctly
    _ = IExchange;
    _ = IExchange.VTable;
}
