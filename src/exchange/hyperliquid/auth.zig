//! Hyperliquid Authentication - EIP-712 Signing
//!
//! Implements EIP-712 typed structured data signing for Hyperliquid DEX.
//! Reference: https://eips.ethereum.org/EIPS/eip-712

const std = @import("std");
const Allocator = std.mem.Allocator;
const Keccak256 = std.crypto.hash.sha3.Keccak256;
const zigeth = @import("zigeth");

// ============================================================================
// EIP-712 Domain
// ============================================================================

/// EIP-712 Domain Separator for Hyperliquid
pub const EIP712Domain = struct {
    name: []const u8,
    version: []const u8,
    chainId: u64,
    verifyingContract: []const u8,
};

/// Hyperliquid Exchange domain (for L1 actions)
pub const HYPERLIQUID_EXCHANGE_DOMAIN = EIP712Domain{
    .name = "Exchange",
    .version = "1",
    .chainId = 1337,
    .verifyingContract = "0x0000000000000000000000000000000000000000",
};

// ============================================================================
// Signing Functions
// ============================================================================

/// Signer for Hyperliquid API requests
pub const Signer = struct {
    allocator: Allocator,
    wallet: zigeth.signer.Wallet, // Ethereum wallet (secp256k1)
    address: []const u8, // Cached Ethereum address (0x...)

    /// Initialize signer with private key
    pub fn init(
        allocator: Allocator,
        private_key: [32]u8,
    ) !Signer {
        // Convert private key to hex string
        const pk_hex = try std.fmt.allocPrint(allocator, "0x{s}", .{
            std.fmt.bytesToHex(&private_key, .lower),
        });
        defer allocator.free(pk_hex);

        // Create wallet from private key
        var wallet = try zigeth.signer.Wallet.fromPrivateKeyHex(allocator, pk_hex);

        // Get Ethereum address
        const addr = try wallet.getAddress();
        const address = try addr.toHex(allocator);

        return .{
            .allocator = allocator,
            .wallet = wallet,
            .address = address,
        };
    }

    /// Deinitialize signer
    pub fn deinit(self: *Signer) void {
        self.allocator.free(self.address);
    }

    /// Sign an action using EIP-712
    ///
    /// @param action_data: JSON-encoded action data
    /// @return Signature components (r, s, v)
    pub fn signAction(
        self: *Signer,
        action_data: []const u8,
    ) !Signature {
        // 1. Hash the action data (message hash)
        const message_hash = keccak256(action_data);

        // 2. Compute domain separator hash
        const domain_hash = try encodeDomainSeparator(
            self.allocator,
            HYPERLIQUID_EXCHANGE_DOMAIN,
        );

        // 3. Sign using EIP-712 (zigeth handles the final encoding and signing)
        const sig = try self.wallet.signTypedData(domain_hash, message_hash);

        // 4. Convert signature components to hex strings with 0x prefix
        const r_hex = try std.fmt.allocPrint(self.allocator, "0x{s}", .{
            std.fmt.bytesToHex(&sig.r, .lower),
        });
        const s_hex = try std.fmt.allocPrint(self.allocator, "0x{s}", .{
            std.fmt.bytesToHex(&sig.s, .lower),
        });

        return Signature{
            .r = r_hex,
            .s = s_hex,
            .v = @truncate(sig.v), // Convert u64 to u8
        };
    }
};

/// ECDSA signature components
pub const Signature = struct {
    r: []const u8, // 32 bytes as hex string
    s: []const u8, // 32 bytes as hex string
    v: u8, // Recovery ID (27 or 28)
};

// ============================================================================
// EIP-712 Type Encoding
// ============================================================================

/// Encode EIP-712 domain separator
fn encodeDomainSeparator(allocator: Allocator, domain: EIP712Domain) ![32]u8 {
    // EIP712Domain type hash
    const type_string = "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)";
    const type_hash = keccak256(type_string);

    // Encode domain fields
    const name_hash = keccak256(domain.name);
    const version_hash = keccak256(domain.version);

    // Parse verifying contract address (hex string to bytes)
    var contract_bytes: [20]u8 = undefined;
    if (domain.verifyingContract.len >= 42 and domain.verifyingContract[0] == '0' and domain.verifyingContract[1] == 'x') {
        const hex_str = domain.verifyingContract[2..];
        _ = try std.fmt.hexToBytes(&contract_bytes, hex_str);
    } else {
        @memset(&contract_bytes, 0);
    }

    // Concatenate: typeHash + nameHash + versionHash + chainId + verifyingContract
    var data = try allocator.alloc(u8, 32 + 32 + 32 + 32 + 32);
    defer allocator.free(data);

    @memcpy(data[0..32], &type_hash);
    @memcpy(data[32..64], &name_hash);
    @memcpy(data[64..96], &version_hash);

    // Chain ID as uint256 (big-endian)
    var chain_id_bytes: [32]u8 = [_]u8{0} ** 32;
    std.mem.writeInt(u64, chain_id_bytes[24..32], domain.chainId, .big);
    @memcpy(data[96..128], &chain_id_bytes);

    // Verifying contract as address (left-padded to 32 bytes)
    var contract_padded: [32]u8 = [_]u8{0} ** 32;
    @memcpy(contract_padded[12..32], &contract_bytes);
    @memcpy(data[128..160], &contract_padded);

    return keccak256(data);
}

/// Compute keccak256 hash
fn keccak256(data: []const u8) [32]u8 {
    var hash: [32]u8 = undefined;
    Keccak256.hash(data, &hash, .{});
    return hash;
}

// ============================================================================
// Tests
// ============================================================================

test "Signer: initialization" {
    const allocator = std.testing.allocator;

    const private_key = [_]u8{0x42} ** 32;
    var signer = try Signer.init(allocator, private_key);
    defer signer.deinit();

    try std.testing.expect(signer.address.len > 0);
    try std.testing.expect(std.mem.startsWith(u8, signer.address, "0x"));
}

test "Signer: sign action" {
    const allocator = std.testing.allocator;

    // Test private key
    const private_key = [_]u8{0x42} ** 32;
    var signer = try Signer.init(allocator, private_key);
    defer signer.deinit();

    // Test action data (simulated order JSON)
    const action_data = "{\"type\":\"order\",\"orders\":[{\"a\":0,\"b\":true,\"p\":\"1800.0\",\"s\":\"0.1\"}]}";

    // Sign the action
    const signature = try signer.signAction(action_data);
    defer allocator.free(signature.r);
    defer allocator.free(signature.s);

    // Verify signature format
    try std.testing.expect(std.mem.startsWith(u8, signature.r, "0x"));
    try std.testing.expect(std.mem.startsWith(u8, signature.s, "0x"));
    try std.testing.expect(signature.r.len == 66); // 0x + 64 hex chars
    try std.testing.expect(signature.s.len == 66);
    try std.testing.expect(signature.v == 27 or signature.v == 28);
}

test "Signature: structure" {
    const sig = Signature{
        .r = "0x1234",
        .s = "0x5678",
        .v = 27,
    };

    try std.testing.expectEqualStrings("0x1234", sig.r);
    try std.testing.expectEqualStrings("0x5678", sig.s);
    try std.testing.expectEqual(@as(u8, 27), sig.v);
}
