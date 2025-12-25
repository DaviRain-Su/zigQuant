//! Hyperliquid-specific data types and structures
//!
//! This module defines types specific to Hyperliquid API:
//! - Request/response formats
//! - Asset metadata
//! - Market data structures
//! - Order and position formats

const std = @import("std");
const Decimal = @import("../../core/decimal.zig").Decimal;
const Timestamp = @import("../../core/time.zig").Timestamp;

// ============================================================================
// API Configuration
// ============================================================================

/// API base URLs
pub const API_BASE_URL_MAINNET = "https://api.hyperliquid.xyz";
pub const API_BASE_URL_TESTNET = "https://api.hyperliquid-testnet.xyz";

/// API endpoints
pub const INFO_ENDPOINT = "/info";
pub const EXCHANGE_ENDPOINT = "/exchange";

// ============================================================================
// Info API Request Types
// ============================================================================

/// Info API request type
pub const InfoRequest = struct {
    type: []const u8,
    // Additional fields vary by type
};

/// Request for all mid prices
pub const AllMidsRequest = struct {
    type: []const u8 = "allMids",
};

/// Request for L2 orderbook snapshot
pub const L2BookRequest = struct {
    type: []const u8 = "l2Book",
    coin: []const u8,
};

/// Request for asset metadata
pub const MetaRequest = struct {
    type: []const u8 = "meta",
};

/// Request for user state (balances and positions)
pub const UserStateRequest = struct {
    type: []const u8 = "clearinghouseState",
    user: []const u8,
};

/// Request for user's open orders
pub const OpenOrdersRequest = struct {
    type: []const u8 = "openOrders",
    user: []const u8,
};

// ============================================================================
// Info API Response Types
// ============================================================================

/// Response containing all mid prices
/// Maps symbol to price string
pub const AllMidsResponse = std.StringHashMap([]const u8);

/// Asset metadata
pub const AssetMeta = struct {
    name: []const u8,
    szDecimals: ?u8 = null,
};

/// Universe metadata response
pub const MetaResponse = struct {
    universe: []AssetMeta,
};

/// Asset context (pricing information)
pub const AssetCtx = struct {
    funding: ?[]const u8 = null, // Funding rate
    openInterest: ?[]const u8 = null, // Open interest
    prevDayPx: ?[]const u8 = null, // Previous day price
    dayNtlVlm: ?[]const u8 = null, // Day notional volume
    premium: ?[]const u8 = null, // Premium
    oraclePx: ?[]const u8 = null, // Oracle price (spot price from multiple exchanges)
    markPx: ?[]const u8 = null, // Mark price (used for margining, liquidations)
    midPx: ?[]const u8 = null, // Mid price (from Hyperliquid orderbook)
    impactPxs: ?[2][]const u8 = null, // Impact prices [bid, ask]
};

/// Meta and asset contexts response
/// Returns a 2-element array: [{universe: [...]}, [{...}, ...]]
pub const MetaAndAssetCtxsResponse = struct {
    // First element: metadata
    universe: []AssetMeta,
};

pub const MetaAndAssetCtxsArray = [2]std.json.Value;

/// L2 orderbook level
pub const L2Level = struct {
    px: []const u8, // Price as string
    sz: []const u8, // Size as string
    n: u32, // Number of orders
};

/// L2 orderbook response
pub const L2BookResponse = struct {
    coin: []const u8,
    levels: [2][]L2Level, // [bids, asks]
    time: u64,
};

/// Asset position
pub const AssetPosition = struct {
    position: struct {
        coin: []const u8,
        entryPx: ?[]const u8,
        leverage: struct {
            type: []const u8,
            value: u32,
        },
        liquidationPx: ?[]const u8,
        marginUsed: []const u8,
        positionValue: []const u8,
        returnOnEquity: []const u8,
        szi: []const u8, // Position size
        unrealizedPnl: []const u8,
    },
    type: []const u8,
};

/// Cross margin summary
pub const MarginSummary = struct {
    accountValue: []const u8,
    totalMarginUsed: []const u8,
    totalNtlPos: []const u8,
    totalRawUsd: []const u8,
};

/// User state response
pub const UserStateResponse = struct {
    assetPositions: []AssetPosition,
    crossMarginSummary: MarginSummary,
    marginSummary: MarginSummary,
    withdrawable: []const u8,
};

/// Open order information
pub const OpenOrder = struct {
    coin: []const u8, // Asset symbol (e.g., "ETH")
    side: []const u8, // "A" for ask (sell), "B" for bid (buy)
    limitPx: []const u8, // Limit price
    sz: []const u8, // Current size (remaining)
    oid: u64, // Order ID
    timestamp: u64, // Order timestamp (ms)
    origSz: []const u8, // Original size
    reduceOnly: bool = false, // Reduce-only flag
    orderType: []const u8 = "Limit", // Order type
    isPositionTpsl: bool = false, // Is position TP/SL
    isTrigger: bool = false, // Is trigger order
    triggerCondition: ?[]const u8 = null, // Trigger condition
    triggerPx: ?[]const u8 = null, // Trigger price
    cloid: ?[]const u8 = null, // Client order ID
};

/// Open orders response (array of orders)
pub const OpenOrdersResponse = []OpenOrder;

// ============================================================================
// Exchange API Request Types
// ============================================================================

/// Order type
pub const HyperliquidOrderType = struct {
    limit: ?LimitOrderParams = null,
    market: ?MarketOrderParams = null,
};

/// Limit order parameters
pub const LimitOrderParams = struct {
    tif: []const u8, // "Gtc", "Ioc", "Alo"
};

/// Market order parameters (placeholder for slippage tolerance)
pub const MarketOrderParams = struct {
    slippage: []const u8 = "0.05", // 5% default
};

/// Order request (for single order placement)
pub const OrderRequest = struct {
    asset_index: u64, // Asset index from meta (e.g., 3 for BTC, 0 for SOL)
    coin: []const u8, // Coin symbol (for logging)
    is_buy: bool,
    sz: []const u8, // Size as string
    limit_px: []const u8, // Limit price as string
    order_type: HyperliquidOrderType,
    reduce_only: bool,
};

/// Action wrapper for exchange requests
pub const ExchangeAction = struct {
    type: []const u8,
    orders: ?[]OrderRequest = null,
    cancels: ?[]CancelRequest = null,
};

/// Cancel request
pub const CancelRequest = struct {
    coin: []const u8,
    oid: u64,
};

// ============================================================================
// Exchange API Response Types
// ============================================================================

/// Order response status
pub const OrderStatus = struct {
    resting: ?RestingOrder = null,
    filled: ?FilledOrder = null,
    @"error": ?[]const u8 = null, // Error message if order was rejected
};

/// Resting (open) order
pub const RestingOrder = struct {
    oid: u64,
};

/// Filled order
pub const FilledOrder = struct {
    totalSz: []const u8,
    avgPx: []const u8,
    oid: u64,
};

/// Exchange response
pub const ExchangeResponse = struct {
    status: []const u8, // "ok" or "err"
    response: ?struct {
        type: []const u8,
        data: ?struct {
            statuses: []OrderStatus,
        } = null,
    } = null,
};

// ============================================================================
// Error Responses
// ============================================================================

/// API error response
pub const ErrorResponse = struct {
    @"error": []const u8,
};

// ============================================================================
// Helper Functions
// ============================================================================

/// Parse price string to Decimal
pub fn parsePrice(price_str: []const u8) !Decimal {
    return Decimal.fromString(price_str);
}

/// Format Decimal to price string
pub fn formatPrice(allocator: std.mem.Allocator, price: Decimal) ![]const u8 {
    return price.toString(allocator);
}

/// Parse size string to Decimal
pub fn parseSize(size_str: []const u8) !Decimal {
    return Decimal.fromString(size_str);
}

/// Format Decimal to size string
pub fn formatSize(allocator: std.mem.Allocator, size: Decimal) ![]const u8 {
    return size.toString(allocator);
}

// ============================================================================
// Tests
// ============================================================================

test "parse price" {
    const price = try parsePrice("1234.56");
    const expected = try Decimal.fromString("1234.56");
    try std.testing.expect(price.eql(expected));
}

test "parse size" {
    const size = try parseSize("0.123");
    const expected = try Decimal.fromString("0.123");
    try std.testing.expect(size.eql(expected));
}

test "format price" {
    const price = try Decimal.fromString("1234.56");
    const price_str = try formatPrice(std.testing.allocator, price);
    defer std.testing.allocator.free(price_str);
    try std.testing.expectEqualStrings("1234.56", price_str);
}

// ============================================================================
// Exchange API Response Types
// ============================================================================

/// Order response from Exchange API (success case only)
///
/// Format: {"status":"ok","response":{"type":"order","data":{"statuses":[...]}}}
/// Error responses are handled separately in exchange_api.zig
pub const OrderResponse = struct {
    status: []const u8, // Should be "ok"
    response: struct {
        type: []const u8,
        data: ?struct {
            statuses: []OrderStatus, // Use OrderStatus type which includes error field
        },
    },
};

/// Cancel response from Exchange API
pub const CancelResponse = struct {
    status: []const u8, // "ok" or error message
    response: ?struct {
        type: []const u8,
        data: ?struct {
            statuses: [][]const u8,
        },
    },
};
