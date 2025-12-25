//! Hyperliquid Authentication - EIP-712 Signing
//!
//! Implements EIP-712 typed structured data signing for Hyperliquid DEX.
//! Reference: https://eips.ethereum.org/EIPS/eip-712
//!
//! Phantom Agent Signing:
//! 1. Pack action with msgpack
//! 2. Append nonce (8 bytes big endian)
//! 3. Append vault address flag (0x00 for None)
//! 4. Keccak256 hash → connectionId
//! 5. Sign Agent type: {source: "b" (testnet), connectionId: hash}

const std = @import("std");
const Allocator = std.mem.Allocator;
const Keccak256 = std.crypto.hash.sha3.Keccak256; // EIP-712 uses Keccak-256 (Ethereum) for ALL hashes, not SHA3-256!
const zigeth = @import("zigeth");
const msgpack = @import("msgpack.zig");

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
// Phantom Agent Types
// ============================================================================

/// Phantom Agent for L1 action signing
/// EIP-712 Type: Agent(string source,bytes32 connectionId)
pub const PhantomAgent = struct {
    source: []const u8, // "a" for mainnet, "b" for testnet
    connectionId: [32]u8, // keccak256(msgpack(action) + nonce + vault)
};

// ============================================================================
// Action Hash Calculation
// ============================================================================

/// Compute action hash (connectionId) for phantom agent
///
/// Steps (matching Python SDK):
/// 1. Pack action with msgpack (action_data)
/// 2. Append nonce (8 bytes BIG endian)
/// 3. Append vault flag (0x00 for None, 0x01 + 20 bytes for Some(address))
/// 4. Keccak256 hash → connectionId
///
/// IMPORTANT: The nonce must match the nonce in the request body!
fn computeActionHash(
    allocator: Allocator,
    action_data: []const u8,
    nonce: u64,
) ![32]u8 {
    // Build hash input: action_data + nonce + vault_flag (matching Python SDK)
    var hash_input = try allocator.alloc(u8, action_data.len + 8 + 1);
    defer allocator.free(hash_input);

    // Copy action data (msgpack-encoded)
    @memcpy(hash_input[0..action_data.len], action_data);

    // Append nonce (8 bytes, BIG endian - matching Python's to_bytes(8, "big"))
    var nonce_bytes: [8]u8 = undefined;
    std.mem.writeInt(u64, &nonce_bytes, nonce, .big);
    @memcpy(hash_input[action_data.len..action_data.len + 8], &nonce_bytes);

    // Append vault flag (0x00 for None - matching Python SDK)
    hash_input[action_data.len + 8] = 0x00;

    // Compute SHA3-256 hash for connectionId
    return keccak256(hash_input);
}

/// Construct phantom agent for signing
fn constructPhantomAgent(
    allocator: Allocator,
    action_data: []const u8,
    nonce: u64,
    is_testnet: bool,
) !PhantomAgent {
    const connectionId = try computeActionHash(allocator, action_data, nonce);

    return PhantomAgent{
        .source = if (is_testnet) "b" else "a",
        .connectionId = connectionId,
    };
}

// ============================================================================
// EIP-712 Agent Type Encoding
// ============================================================================

/// Encode Agent type for EIP-712 signing
/// Type: Agent(string source,bytes32 connectionId)
fn encodeAgentType(allocator: Allocator, agent: PhantomAgent) ![32]u8 {
    // Agent type hash (SHA3-256)
    const type_string = "Agent(string source,bytes32 connectionId)";
    const type_hash = keccak256(type_string);
    // std.debug.print("[VERIFY] Agent type string: {s}\n", .{type_string});
    // std.debug.print("[VERIFY] Agent type hash: {s}\n", .{std.fmt.bytesToHex(&type_hash, .lower)});

    // Encode agent fields (SHA3-256)
    const source_hash = keccak256(agent.source);
    // std.debug.print("[VERIFY] Source value: {s}\n", .{agent.source});
    // std.debug.print("[VERIFY] Source hash: {s}\n", .{std.fmt.bytesToHex(&source_hash, .lower)});
    // std.debug.print("[VERIFY] ConnectionId: {s}\n", .{std.fmt.bytesToHex(&agent.connectionId, .lower)});

    // Concatenate: typeHash + sourceHash + connectionId
    var data = try allocator.alloc(u8, 32 + 32 + 32);
    defer allocator.free(data);

    @memcpy(data[0..32], &type_hash);
    @memcpy(data[32..64], &source_hash);
    @memcpy(data[64..96], &agent.connectionId);

    // std.debug.print("[VERIFY] Agent encode concat: ", .{});
    for (data) |byte| {
        std.debug.print("{x:0>2}", .{byte});
    }
    std.debug.print("\n", .{});

    // Final struct hash (SHA3-256)
    const result = keccak256(data);
    return result;
}

// ============================================================================
// Signing Functions
// ============================================================================

/// Signer for Hyperliquid API requests
pub const Signer = struct {
    allocator: Allocator,
    wallet: zigeth.signer.Wallet, // Ethereum wallet (secp256k1)
    address: []const u8, // Cached Ethereum address (0x...)
    is_testnet: bool, // Whether this is for testnet (affects phantom agent source)

    /// Initialize signer with private key
    pub fn init(
        allocator: Allocator,
        private_key: [32]u8,
        is_testnet: bool,
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
            .is_testnet = is_testnet,
        };
    }

    /// Deinitialize signer
    pub fn deinit(self: *Signer) void {
        self.allocator.free(self.address);
    }

    /// Sign an action using EIP-712 with Phantom Agent
    ///
    /// This implements Hyperliquid's L1 action signing flow:
    /// 1. action_data should be msgpack-encoded action
    /// 2. Construct phantom agent with connectionId = keccak256(action + nonce + vault)
    /// 3. Sign the Agent type, NOT the action itself
    ///
    /// @param action_data: Msgpack-encoded action data
    /// @param nonce: Timestamp nonce (must match the request body nonce!)
    /// @return Signature components (r, s, v)
    pub fn signAction(
        self: *Signer,
        action_data: []const u8,
        nonce: u64,
    ) !Signature {
        // std.debug.print("[DEBUG] Signing msgpack action ({d} bytes)\n", .{action_data.len});
        // std.debug.print("[DEBUG] Signer address: {s}\n", .{self.address});
        // std.debug.print("[DEBUG] Is testnet: {}\n", .{self.is_testnet});
        // std.debug.print("[DEBUG] Nonce: {d}\n", .{nonce});

        // 1. Construct phantom agent
        const agent = try constructPhantomAgent(
            self.allocator,
            action_data,
            nonce,
            self.is_testnet,
        );
        // std.debug.print("[DEBUG] Phantom agent source: {s}\n", .{agent.source});
        // std.debug.print("[DEBUG] Connection ID: {s}\n", .{std.fmt.bytesToHex(&agent.connectionId, .lower)});

        // 2. Encode Agent type for EIP-712
        const agent_hash = try encodeAgentType(self.allocator, agent);
        // std.debug.print("[DEBUG] Agent hash: {s}\n", .{std.fmt.bytesToHex(&agent_hash, .lower)});

        // 3. Compute domain separator hash
        const domain_hash = try encodeDomainSeparator(
            self.allocator,
            HYPERLIQUID_EXCHANGE_DOMAIN,
        );
        // std.debug.print("[DEBUG] Domain hash: {s}\n", .{std.fmt.bytesToHex(&domain_hash, .lower)});

        // 4. Construct EIP-712 digest: Keccak256("\x19\x01" + domain_hash + agent_hash)
        // IMPORTANT: Use Ethereum Keccak256 for final digest, not SHA3-256!
        var digest_data: [66]u8 = undefined;
        digest_data[0] = 0x19;
        digest_data[1] = 0x01;
        @memcpy(digest_data[2..34], &domain_hash);
        @memcpy(digest_data[34..66], &agent_hash);

        // std.debug.print("[VERIFY] Digest input (66 bytes): ", .{});
        for (digest_data) |byte| {
            std.debug.print("{x:0>2}", .{byte});
        }
        std.debug.print("\n", .{});

        const digest = keccak256(&digest_data); // Ethereum Keccak256!
        // std.debug.print("[DEBUG] EIP-712 digest (Keccak256): {s}\n", .{std.fmt.bytesToHex(&digest, .lower)});

        // 5. Sign the digest using signHash (not signMessage to avoid double-hashing)
        const Hash = zigeth.primitives.Hash;
        const hash = Hash.fromBytes(digest);
        const sig = try self.wallet.signer.signHash(hash);
        // std.debug.print("[DEBUG] Signature v: {d}\n", .{sig.v});

        // 6. Verify signature by recovering address (for debugging)
        const ecdsa = @import("../../zigeth_deps.zig").ecdsa;
        const recovered_addr = try ecdsa.recoverAddress(hash, sig);
        const recovered_hex = try recovered_addr.toHex(self.allocator);
        defer self.allocator.free(recovered_hex);
        // std.debug.print("[VERIFY] Recovered address: {s}\n", .{recovered_hex});
        // std.debug.print("[VERIFY] Expected address:  {s}\n", .{self.address});
        if (std.mem.eql(u8, recovered_hex, self.address)) {
            // std.debug.print("[VERIFY] ✅ Local signature verification passed!\n", .{});
        } else {
            std.debug.print("[WARN] Local address mismatch - may indicate signing issue\n", .{});
        }

        // 7. Convert signature components to hex strings with 0x prefix
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
    // EIP712Domain type hash (SHA3-256)
    const type_string = "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)";
    const type_hash = keccak256(type_string);

    // Encode domain fields (SHA3-256)
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

    // Domain separator hash (SHA3-256)
    return keccak256(data);
}

/// Compute Keccak-256 hash (Ethereum standard, used for ALL EIP-712 hashes)
/// NOTE: EIP-712 uses Keccak-256, not NIST SHA3-256! They produce different hashes!
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
    var signer = try Signer.init(allocator, private_key, true); // testnet
    defer signer.deinit();

    try std.testing.expect(signer.address.len > 0);
    try std.testing.expect(std.mem.startsWith(u8, signer.address, "0x"));
    try std.testing.expect(signer.is_testnet == true);
}

test "Signer: sign action" {
    const allocator = std.testing.allocator;

    // Test private key
    const private_key = [_]u8{0x42} ** 32;
    var signer = try Signer.init(allocator, private_key, true); // testnet
    defer signer.deinit();

    // Test action data (TODO: should be msgpack-encoded, using placeholder for now)
    const action_data = "{\"type\":\"order\",\"orders\":[{\"a\":0,\"b\":true,\"p\":\"1800.0\",\"s\":\"0.1\"}]}";

    // Sign the action with a test nonce
    const nonce = 1234567890;
    const signature = try signer.signAction(action_data, nonce);
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
