//! Verify Private Key and Wallet Address Match
//!
//! This tool helps verify that a private key correctly derives to the expected wallet address.
//! Run with: zig run tests/integration/verify_keys.zig

const std = @import("std");
const zigeth = @import("zigeth");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Read config file
    const config_file = try std.fs.cwd().openFile("tests/integration/test_config.json", .{});
    defer config_file.close();

    const config_content = try config_file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(config_content);

    const parsed = try std.json.parseFromSlice(
        struct {
            exchanges: []struct {
                api_key: []const u8,
                api_secret: []const u8,
            },
        },
        allocator,
        config_content,
        .{ .allocate = .alloc_always, .ignore_unknown_fields = true },
    );
    defer parsed.deinit();

    if (parsed.value.exchanges.len == 0) {
        std.debug.print("No exchange configured\n", .{});
        return;
    }

    const exchange = parsed.value.exchanges[0];
    std.debug.print("\n" ++ "=" ** 80 ++ "\n", .{});
    std.debug.print("Private Key and Address Verification\n", .{});
    std.debug.print("=" ** 80 ++ "\n\n", .{});

    // Parse private key
    var private_key_bytes: [32]u8 = undefined;
    _ = try std.fmt.hexToBytes(&private_key_bytes, exchange.api_secret);

    // Create private key hex string
    const pk_hex = try std.fmt.allocPrint(allocator, "0x{s}", .{
        std.fmt.bytesToHex(&private_key_bytes, .lower),
    });
    defer allocator.free(pk_hex);

    std.debug.print("Configuration:\n", .{});
    std.debug.print("  Configured Address (api_key): {s}\n", .{exchange.api_key});
    std.debug.print("  Private Key (api_secret):     {s}\n\n", .{exchange.api_secret});

    // Derive address from private key
    var wallet = try zigeth.signer.Wallet.fromPrivateKeyHex(allocator, pk_hex);

    const addr = try wallet.getAddress();
    const derived_address = try addr.toHex(allocator);
    defer allocator.free(derived_address);

    std.debug.print("Derived from Private Key:\n", .{});
    std.debug.print("  Derived Address:              {s}\n\n", .{derived_address});

    // Compare
    const match = std.ascii.eqlIgnoreCase(exchange.api_key, derived_address);

    std.debug.print("=" ** 80 ++ "\n", .{});
    if (match) {
        std.debug.print("✅ MATCH: Private key and address are correctly paired\n", .{});
        std.debug.print("=" ** 80 ++ "\n\n", .{});
        std.debug.print("You can use this configuration for Hyperliquid testnet.\n", .{});
        std.debug.print("Make sure the wallet {s} exists on testnet and has USDC balance.\n", .{derived_address});
    } else {
        std.debug.print("❌ MISMATCH: Private key does NOT match the configured address!\n", .{});
        std.debug.print("=" ** 80 ++ "\n\n", .{});
        std.debug.print("ERROR: The private key generates address:\n", .{});
        std.debug.print("  {s}\n\n", .{derived_address});
        std.debug.print("But the configured address is:\n", .{});
        std.debug.print("  {s}\n\n", .{exchange.api_key});
        std.debug.print("To fix this issue:\n", .{});
        std.debug.print("1. Update api_key in test_config.json to: {s}\n", .{derived_address});
        std.debug.print("   OR\n", .{});
        std.debug.print("2. Use the correct private key that matches {s}\n", .{exchange.api_key});
        std.debug.print("\nThen make sure the wallet exists on Hyperliquid testnet:\n", .{});
        std.debug.print("  - Visit: https://app.hyperliquid-testnet.xyz/\n", .{});
        std.debug.print("  - Connect with wallet address: {s}\n", .{derived_address});
        std.debug.print("  - Get testnet USDC from faucet\n", .{});

        return error.AddressMismatch;
    }

    std.debug.print("\n", .{});
}
