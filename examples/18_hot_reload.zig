//! Example 18: Hot Reload Manager (v0.6.0)
//!
//! This example demonstrates the Hot Reload Manager for runtime strategy
//! parameter updates without restarting the trading engine.
//!
//! Features:
//! - File-based configuration monitoring
//! - Parameter validation with min/max bounds
//! - Safe reload timing (between ticks)
//! - Configuration backup
//! - Event notification
//!
//! Run: zig build run-example-hot-reload

const std = @import("std");
const zigQuant = @import("zigQuant");

const Decimal = zigQuant.Decimal;

pub fn main() !void {
    // Using std.debug.print for output
    // This example demonstrates Hot Reload concepts

    std.debug.print("\n", .{});
    std.debug.print("================================================================\n", .{});
    std.debug.print("       Example 18: Hot Reload Manager (v0.6.0)\n", .{});
    std.debug.print("================================================================\n", .{});
    std.debug.print("\n", .{});

    // ========================================================================
    // Section 1: Introduction
    // ========================================================================
    std.debug.print("--- 1. Introduction ---\n\n", .{});
    std.debug.print("Hot Reload Manager enables:\n", .{});
    std.debug.print("  - Runtime parameter updates\n", .{});
    std.debug.print("  - File change monitoring\n", .{});
    std.debug.print("  - Validation before applying changes\n", .{});
    std.debug.print("  - Safe reload timing\n", .{});
    std.debug.print("  - Automatic configuration backup\n", .{});
    std.debug.print("\n", .{});

    // ========================================================================
    // Section 2: Configuration Parameters
    // ========================================================================
    std.debug.print("--- 2. Configuration Parameters ---\n\n", .{});

    std.debug.print("  ConfigParam structure:\n", .{});
    std.debug.print("    - name: Parameter identifier\n", .{});
    std.debug.print("    - value: Current value\n", .{});
    std.debug.print("    - min/max: Valid range bounds\n", .{});
    std.debug.print("    - description: Human-readable description\n", .{});
    std.debug.print("\n", .{});

    // Sample parameters (conceptual)
    std.debug.print("  Sample parameters:\n", .{});
    std.debug.print("    - fast_period: 10 (range: 2 - 100)\n", .{});
    std.debug.print("      Valid: yes\n", .{});
    std.debug.print("    - slow_period: 30 (range: 5 - 200)\n", .{});
    std.debug.print("      Valid: yes\n", .{});
    std.debug.print("    - position_size: 0.10 (range: 0.01 - 1.00)\n", .{});
    std.debug.print("      Valid: yes\n", .{});
    std.debug.print("\n", .{});

    // ========================================================================
    // Section 3: Risk Configuration
    // ========================================================================
    std.debug.print("--- 3. Risk Configuration ---\n\n", .{});

    std.debug.print("  RiskConfig structure:\n", .{});
    std.debug.print("    - max_position_size: Maximum position size\n", .{});
    std.debug.print("    - max_order_size: Max single order size\n", .{});
    std.debug.print("    - max_daily_loss: Maximum daily loss limit\n", .{});
    std.debug.print("    - max_open_orders: Max concurrent orders\n", .{});
    std.debug.print("\n", .{});

    // RiskConfig example values (conceptual)
    std.debug.print("  Current risk config:\n", .{});
    std.debug.print("    - Max Position: 10000\n", .{});
    std.debug.print("    - Max Order: 1000\n", .{});
    std.debug.print("    - Max Daily Loss: 5000\n", .{});
    std.debug.print("    - Max Open Orders: 100\n", .{});
    std.debug.print("    Validation: passed\n", .{});
    std.debug.print("\n", .{});

    // ========================================================================
    // Section 4: Hot Reload Config
    // ========================================================================
    std.debug.print("--- 4. Hot Reload Config File ---\n\n", .{});

    std.debug.print("  Example JSON config file:\n\n", .{});
    std.debug.print("  {{\n", .{});
    std.debug.print("    \"strategy\": \"dual_ma\",\n", .{});
    std.debug.print("    \"version\": 1,\n", .{});
    std.debug.print("    \"params\": {{\n", .{});
    std.debug.print("      \"fast_period\": {{\n", .{});
    std.debug.print("        \"value\": 10,\n", .{});
    std.debug.print("        \"min\": 2,\n", .{});
    std.debug.print("        \"max\": 100\n", .{});
    std.debug.print("      }},\n", .{});
    std.debug.print("      \"slow_period\": {{\n", .{});
    std.debug.print("        \"value\": 30,\n", .{});
    std.debug.print("        \"min\": 5,\n", .{});
    std.debug.print("        \"max\": 200\n", .{});
    std.debug.print("      }}\n", .{});
    std.debug.print("    }},\n", .{});
    std.debug.print("    \"risk\": {{\n", .{});
    std.debug.print("      \"max_position_size\": 10000,\n", .{});
    std.debug.print("      \"max_order_size\": 1000,\n", .{});
    std.debug.print("      \"max_daily_loss\": 5000\n", .{});
    std.debug.print("    }}\n", .{});
    std.debug.print("  }}\n", .{});
    std.debug.print("\n", .{});

    // ========================================================================
    // Section 5: Manager Usage
    // ========================================================================
    std.debug.print("--- 5. Manager Usage ---\n\n", .{});

    std.debug.print("  // Initialize manager\n", .{});
    std.debug.print("  var manager = try HotReloadManager.init(\n", .{});
    std.debug.print("      allocator,\n", .{});
    std.debug.print("      \"strategy_config.json\",\n", .{});
    std.debug.print("      &strategy,      // IReloadable strategy\n", .{});
    std.debug.print("      &message_bus,\n", .{});
    std.debug.print("      .{{\n", .{});
    std.debug.print("          .check_interval_ms = 1000,\n", .{});
    std.debug.print("          .backup_enabled = true,\n", .{});
    std.debug.print("      }}\n", .{});
    std.debug.print("  );\n", .{});
    std.debug.print("  defer manager.deinit();\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  // Start file monitoring\n", .{});
    std.debug.print("  try manager.start();\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  // ... trading loop ...\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  // Stop monitoring\n", .{});
    std.debug.print("  manager.stop();\n", .{});
    std.debug.print("\n", .{});

    // ========================================================================
    // Section 6: Event Notification
    // ========================================================================
    std.debug.print("--- 6. Event Notification ---\n\n", .{});

    std.debug.print("  Hot reload events via MessageBus:\n\n", .{});
    std.debug.print("  // Subscribe to reload events\n", .{});
    std.debug.print("  try message_bus.subscribe(\"config.reload\", handler);\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  Events published:\n", .{});
    std.debug.print("    - config.reload.started: Before applying changes\n", .{});
    std.debug.print("    - config.reload.success: After successful reload\n", .{});
    std.debug.print("    - config.reload.failed: On validation/apply error\n", .{});
    std.debug.print("    - config.backup.created: Backup file saved\n", .{});
    std.debug.print("\n", .{});

    // ========================================================================
    // Section 7: IReloadable Interface
    // ========================================================================
    std.debug.print("--- 7. IReloadable Interface ---\n\n", .{});

    std.debug.print("  Strategies must implement IReloadable:\n\n", .{});
    std.debug.print("  pub const IReloadable = struct {{\n", .{});
    std.debug.print("      ptr: *anyopaque,\n", .{});
    std.debug.print("      vtable: *const VTable,\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("      pub const VTable = struct {{\n", .{});
    std.debug.print("          canReload: fn() bool,\n", .{});
    std.debug.print("          applyConfig: fn(*HotReloadConfig) !void,\n", .{});
    std.debug.print("          getConfig: fn() HotReloadConfig,\n", .{});
    std.debug.print("      }};\n", .{});
    std.debug.print("  }};\n", .{});
    std.debug.print("\n", .{});

    // ========================================================================
    // Section 8: Best Practices
    // ========================================================================
    std.debug.print("--- 8. Best Practices ---\n\n", .{});

    std.debug.print("  1. Validation:\n", .{});
    std.debug.print("     - Always define min/max bounds\n", .{});
    std.debug.print("     - Validate before applying\n", .{});
    std.debug.print("     - Check parameter relationships\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  2. Safety:\n", .{});
    std.debug.print("     - Apply changes between ticks\n", .{});
    std.debug.print("     - Enable automatic backups\n", .{});
    std.debug.print("     - Log all configuration changes\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  3. Testing:\n", .{});
    std.debug.print("     - Test with paper trading first\n", .{});
    std.debug.print("     - Verify reload in safe conditions\n", .{});
    std.debug.print("     - Monitor behavior after reload\n", .{});
    std.debug.print("\n", .{});

    // ========================================================================
    // Summary
    // ========================================================================
    std.debug.print("================================================================\n", .{});
    std.debug.print("  Hot Reload Manager Summary\n", .{});
    std.debug.print("================================================================\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  Key Features:\n", .{});
    std.debug.print("    - Runtime parameter updates\n", .{});
    std.debug.print("    - File change monitoring\n", .{});
    std.debug.print("    - Parameter validation\n", .{});
    std.debug.print("    - Configuration backup\n", .{});
    std.debug.print("    - Event notification\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  Use Cases:\n", .{});
    std.debug.print("    - Adjust risk parameters on-the-fly\n", .{});
    std.debug.print("    - Fine-tune strategy without restart\n", .{});
    std.debug.print("    - Respond to market conditions\n", .{});
    std.debug.print("    - A/B testing parameters\n", .{});
    std.debug.print("\n", .{});

}
