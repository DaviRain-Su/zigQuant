//! Example 16: Hyperliquid Adapter (v0.6.0)
//!
//! This example demonstrates the Hyperliquid exchange adapters:
//! - HyperliquidDataProvider: Market data subscription via WebSocket
//! - HyperliquidExecutionClient: Order execution via REST API
//!
//! Both implement standard interfaces (IDataProvider, IExecutionClient) for
//! seamless integration with the trading engine.
//!
//! Run: zig build run-example-adapter
//!
//! Note: This example requires network connectivity to Hyperliquid API.

const std = @import("std");
const zigQuant = @import("zigQuant");

const adapters = zigQuant.adapters;
const HyperliquidDataProvider = adapters.HyperliquidDataProvider;
const HyperliquidExecutionClient = adapters.HyperliquidExecutionClient;

// For demonstration purposes
const Decimal = zigQuant.Decimal;

pub fn main() !void {
    // Using std.debug.print for output

    std.debug.print("\n", .{});
    std.debug.print("================================================================\n", .{});
    std.debug.print("       Example 16: Hyperliquid Adapter (v0.6.0)\n", .{});
    std.debug.print("================================================================\n", .{});
    std.debug.print("\n", .{});

    // ========================================================================
    // Section 1: Introduction
    // ========================================================================
    std.debug.print("--- 1. Introduction ---\n\n", .{});
    std.debug.print("The Hyperliquid Adapter provides two main components:\n\n", .{});
    std.debug.print("  HyperliquidDataProvider:\n", .{});
    std.debug.print("    - Implements IDataProvider interface\n", .{});
    std.debug.print("    - WebSocket-based market data subscription\n", .{});
    std.debug.print("    - Supports quotes, orderbook, and trades\n", .{});
    std.debug.print("    - Thread-safe message queue\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  HyperliquidExecutionClient:\n", .{});
    std.debug.print("    - Implements IExecutionClient interface\n", .{});
    std.debug.print("    - REST API for order execution\n", .{});
    std.debug.print("    - Supports market and limit orders\n", .{});
    std.debug.print("    - EIP-712 signature authentication\n", .{});
    std.debug.print("\n", .{});

    // ========================================================================
    // Section 2: Data Provider Configuration
    // ========================================================================
    std.debug.print("--- 2. Data Provider Configuration ---\n\n", .{});

    std.debug.print("  const Config = struct {{\n", .{});
    std.debug.print("      host: []const u8 = \"api.hyperliquid.xyz\",\n", .{});
    std.debug.print("      port: u16 = 443,\n", .{});
    std.debug.print("      path: []const u8 = \"/ws\",\n", .{});
    std.debug.print("      use_tls: bool = true,\n", .{});
    std.debug.print("      max_message_size: usize = 1MB,\n", .{});
    std.debug.print("      reconnect_interval_ms: u64 = 5000,\n", .{});
    std.debug.print("      max_reconnect_attempts: u32 = 10,\n", .{});
    std.debug.print("  }};\n", .{});
    std.debug.print("\n", .{});

    // ========================================================================
    // Section 3: Data Provider Usage
    // ========================================================================
    std.debug.print("--- 3. Data Provider Usage ---\n\n", .{});

    std.debug.print("  // Initialize provider\n", .{});
    std.debug.print("  var provider = HyperliquidDataProvider.init(\n", .{});
    std.debug.print("      allocator, .{{}}, logger\n", .{});
    std.debug.print("  );\n", .{});
    std.debug.print("  defer provider.deinit();\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  // Get interface for DataEngine\n", .{});
    std.debug.print("  const data_provider = provider.asProvider();\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  // Connect to WebSocket\n", .{});
    std.debug.print("  try data_provider.connect();\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  // Subscribe to market data\n", .{});
    std.debug.print("  try data_provider.subscribe(.{{\n", .{});
    std.debug.print("      .sub_type = .quote,\n", .{});
    std.debug.print("      .symbol = \"ETH\",\n", .{});
    std.debug.print("  }});\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  // Poll for messages\n", .{});
    std.debug.print("  while (data_provider.poll()) |message| {{\n", .{});
    std.debug.print("      switch (message) {{\n", .{});
    std.debug.print("          .quote => |q| // Handle quote\n", .{});
    std.debug.print("          .orderbook => |ob| // Handle orderbook\n", .{});
    std.debug.print("          .trade => |t| // Handle trade\n", .{});
    std.debug.print("      }}\n", .{});
    std.debug.print("  }}\n", .{});
    std.debug.print("\n", .{});

    // ========================================================================
    // Section 4: Execution Client Configuration
    // ========================================================================
    std.debug.print("--- 4. Execution Client Configuration ---\n\n", .{});

    std.debug.print("  const ExecConfig = struct {{\n", .{});
    std.debug.print("      testnet: bool = false,\n", .{});
    std.debug.print("      wallet_address: ?[]const u8 = null,\n", .{});
    std.debug.print("      private_key: ?[32]u8 = null,\n", .{});
    std.debug.print("  }};\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  For production use, you need:\n", .{});
    std.debug.print("    - Ethereum wallet address\n", .{});
    std.debug.print("    - Private key for EIP-712 signing\n", .{});
    std.debug.print("\n", .{});

    // ========================================================================
    // Section 5: Execution Client Usage
    // ========================================================================
    std.debug.print("--- 5. Execution Client Usage ---\n\n", .{});

    std.debug.print("  // Initialize client\n", .{});
    std.debug.print("  var exec = try HyperliquidExecutionClient.init(\n", .{});
    std.debug.print("      allocator,\n", .{});
    std.debug.print("      .{{ .testnet = true, .private_key = pk }},\n", .{});
    std.debug.print("      logger,\n", .{});
    std.debug.print("      null  // optional message bus\n", .{});
    std.debug.print("  );\n", .{});
    std.debug.print("  defer exec.deinit();\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  // Get interface for ExecutionEngine\n", .{});
    std.debug.print("  const exec_client = exec.asClient();\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  // Submit order\n", .{});
    std.debug.print("  const result = try exec_client.submitOrder(.{{\n", .{});
    std.debug.print("      .symbol = \"ETH\",\n", .{});
    std.debug.print("      .side = .buy,\n", .{});
    std.debug.print("      .order_type = .market,\n", .{});
    std.debug.print("      .quantity = Decimal.fromFloat(0.1),\n", .{});
    std.debug.print("  }});\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  if (result.success) {{\n", .{});
    std.debug.print("      // Order accepted\n", .{});
    std.debug.print("  }}\n", .{});
    std.debug.print("\n", .{});

    // ========================================================================
    // Section 6: Integration with Trading Engine
    // ========================================================================
    std.debug.print("--- 6. Integration with Trading Engine ---\n\n", .{});

    std.debug.print("  // Create components\n", .{});
    std.debug.print("  var message_bus = MessageBus.init(allocator);\n", .{});
    std.debug.print("  var cache = Cache.init(allocator, &message_bus, .{{}});\n", .{});
    std.debug.print("  var data_engine = DataEngine.init(allocator, &message_bus, &cache);\n", .{});
    std.debug.print("  var exec_engine = ExecutionEngine.init(allocator, &message_bus, &cache);\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  // Add Hyperliquid provider\n", .{});
    std.debug.print("  var hl_provider = HyperliquidDataProvider.init(allocator, .{{}}, logger);\n", .{});
    std.debug.print("  try data_engine.addProvider(hl_provider.asProvider());\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  // Set Hyperliquid execution client\n", .{});
    std.debug.print("  var hl_exec = try HyperliquidExecutionClient.init(...);\n", .{});
    std.debug.print("  exec_engine.setClient(hl_exec.asClient());\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  // Now use LiveTradingEngine for unified access\n", .{});
    std.debug.print("  var live_engine = LiveTradingEngine.init(\n", .{});
    std.debug.print("      allocator, &message_bus, &cache,\n", .{});
    std.debug.print("      &data_engine, &exec_engine, logger\n", .{});
    std.debug.print("  );\n", .{});
    std.debug.print("\n", .{});

    // ========================================================================
    // Section 7: Supported Subscriptions
    // ========================================================================
    std.debug.print("--- 7. Supported Subscriptions ---\n\n", .{});

    std.debug.print("  Subscription Types:\n", .{});
    std.debug.print("    - quote: Mid prices for all symbols\n", .{});
    std.debug.print("    - orderbook: L2 orderbook (20 levels)\n", .{});
    std.debug.print("    - trade: Trade stream for symbol\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  Message Format Conversion:\n", .{});
    std.debug.print("    Hyperliquid -> Standard DataMessage:\n", .{});
    std.debug.print("    - AllMidsData -> QuoteMessage\n", .{});
    std.debug.print("    - L2BookData -> OrderbookMessage\n", .{});
    std.debug.print("    - TradesData -> TradeMessage\n", .{});
    std.debug.print("\n", .{});

    // ========================================================================
    // Section 8: Order Types
    // ========================================================================
    std.debug.print("--- 8. Supported Order Types ---\n\n", .{});

    std.debug.print("  Order Types:\n", .{});
    std.debug.print("    - market: Market order, immediate fill\n", .{});
    std.debug.print("    - limit: Limit order with price\n", .{});
    std.debug.print("    - stop_market: Stop order (TODO)\n", .{});
    std.debug.print("    - stop_limit: Stop-limit order (TODO)\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  Time-in-Force:\n", .{});
    std.debug.print("    - GTC: Good Till Cancel\n", .{});
    std.debug.print("    - IOC: Immediate Or Cancel\n", .{});
    std.debug.print("    - FOK: Fill Or Kill\n", .{});
    std.debug.print("\n", .{});

    // ========================================================================
    // Summary
    // ========================================================================
    std.debug.print("================================================================\n", .{});
    std.debug.print("  Hyperliquid Adapter Summary\n", .{});
    std.debug.print("================================================================\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  Key Features:\n", .{});
    std.debug.print("    - Standard interface implementation\n", .{});
    std.debug.print("    - WebSocket for real-time data\n", .{});
    std.debug.print("    - REST API for order execution\n", .{});
    std.debug.print("    - Thread-safe message handling\n", .{});
    std.debug.print("    - Auto-reconnection support\n", .{});
    std.debug.print("    - EIP-712 authentication\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  Architecture Benefits:\n", .{});
    std.debug.print("    - Pluggable: Swap exchanges easily\n", .{});
    std.debug.print("    - Testable: Mock interfaces for testing\n", .{});
    std.debug.print("    - Unified: Same code works for all exchanges\n", .{});
    std.debug.print("\n", .{});
}
