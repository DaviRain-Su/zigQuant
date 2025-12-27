//! Dual Latency Simulation for Realistic Backtest
//!
//! This module provides latency simulation for market data (feed latency)
//! and order execution (order latency). Real trading has different latencies
//! for these two paths, which must be modeled separately for accurate results.
//!
//! ## Latency Types
//!
//! - Feed Latency: Exchange -> Strategy (market data, orderbook updates)
//! - Order Latency: Strategy -> Exchange -> Strategy (order submit + response)
//!   - Entry Latency: Strategy -> Exchange (order submission)
//!   - Response Latency: Exchange -> Strategy (confirmation)
//!
//! ## Latency Models
//!
//! - Constant: Fixed latency value
//! - Normal: Gaussian distribution with mean and std
//! - Interpolated: Linear interpolation from historical data points
//!
//! ## Story 039: Dual Latency Simulation

const std = @import("std");
const Allocator = std.mem.Allocator;

// ============================================================================
// Latency Model Type
// ============================================================================

/// Latency model type
pub const LatencyModelType = enum {
    /// Fixed constant latency
    Constant,
    /// Normal (Gaussian) distribution
    Normal,
    /// Interpolated from historical data
    Interpolated,
};

// ============================================================================
// Latency Data Point
// ============================================================================

/// Historical latency data point for interpolation
pub const LatencyDataPoint = struct {
    /// Timestamp in nanoseconds
    timestamp: i64,
    /// Latency in nanoseconds
    latency_ns: i64,
};

// ============================================================================
// Latency Model
// ============================================================================

/// Base latency model supporting multiple distribution types
pub const LatencyModel = struct {
    /// Model type
    model_type: LatencyModelType,

    /// Constant latency (nanoseconds)
    constant_latency_ns: i64,

    /// Normal distribution mean (nanoseconds)
    mean_ns: i64,

    /// Normal distribution std (nanoseconds)
    std_ns: i64,

    /// Historical data for interpolation
    historical_data: ?[]const LatencyDataPoint,

    /// Random number generator state
    rng_state: u64,

    const Self = @This();

    /// Nanoseconds per millisecond
    pub const NS_PER_MS: i64 = 1_000_000;

    /// Nanoseconds per microsecond
    pub const NS_PER_US: i64 = 1_000;

    /// Create constant latency model
    pub fn constant(latency_ns: i64) Self {
        return .{
            .model_type = .Constant,
            .constant_latency_ns = latency_ns,
            .mean_ns = 0,
            .std_ns = 0,
            .historical_data = null,
            .rng_state = 0,
        };
    }

    /// Create constant latency model from milliseconds
    pub fn constantMs(latency_ms: i64) Self {
        return constant(latency_ms * NS_PER_MS);
    }

    /// Create normal distribution latency model
    pub fn normal(mean_ns: i64, std_ns: i64) Self {
        return .{
            .model_type = .Normal,
            .constant_latency_ns = 0,
            .mean_ns = mean_ns,
            .std_ns = std_ns,
            .historical_data = null,
            .rng_state = @intCast(@as(u128, @bitCast(std.time.nanoTimestamp())) & 0xFFFFFFFFFFFFFFFF),
        };
    }

    /// Create normal distribution latency model from milliseconds
    pub fn normalMs(mean_ms: i64, std_ms: i64) Self {
        return normal(mean_ms * NS_PER_MS, std_ms * NS_PER_MS);
    }

    /// Create interpolated latency model from historical data
    pub fn interpolated(data: []const LatencyDataPoint) Self {
        return .{
            .model_type = .Interpolated,
            .constant_latency_ns = 0,
            .mean_ns = 0,
            .std_ns = 0,
            .historical_data = data,
            .rng_state = 0,
        };
    }

    /// Simulate latency and return delayed timestamp
    pub fn simulate(self: *Self, event_time: i64) i64 {
        const latency = self.getLatency(event_time);
        return event_time + latency;
    }

    /// Get latency value (without adding to event time)
    pub fn getLatency(self: *Self, event_time: i64) i64 {
        return switch (self.model_type) {
            .Constant => self.constant_latency_ns,
            .Normal => self.sampleNormal(),
            .Interpolated => self.interpolate(event_time),
        };
    }

    /// Sample from normal distribution using Box-Muller transform
    fn sampleNormal(self: *Self) i64 {
        // Simple xorshift64 for random numbers
        var x = self.rng_state;
        x ^= x << 13;
        x ^= x >> 7;
        x ^= x << 17;
        self.rng_state = x;

        // Convert to uniform [0, 1)
        const rand1 = @as(f64, @floatFromInt(x & 0x7FFFFFFFFFFFFFFF)) / @as(f64, @floatFromInt(@as(u64, 0x8000000000000000)));

        // Get second random number
        x ^= x << 13;
        x ^= x >> 7;
        x ^= x << 17;
        self.rng_state = x;
        const rand2 = @as(f64, @floatFromInt(x & 0x7FFFFFFFFFFFFFFF)) / @as(f64, @floatFromInt(@as(u64, 0x8000000000000000)));

        // Box-Muller transform
        const epsilon = 1e-10;
        const rand1_safe = @max(epsilon, rand1);
        const z = @sqrt(-2.0 * @log(rand1_safe)) * @cos(2.0 * std.math.pi * rand2);

        // Scale to desired mean and std
        const mean_f = @as(f64, @floatFromInt(self.mean_ns));
        const std_f = @as(f64, @floatFromInt(self.std_ns));
        const sample = mean_f + z * std_f;

        // Ensure non-negative latency
        return @max(0, @as(i64, @intFromFloat(sample)));
    }

    /// Interpolate latency from historical data
    fn interpolate(self: *Self, event_time: i64) i64 {
        const data = self.historical_data orelse return self.mean_ns;
        if (data.len == 0) return 0;

        // Find surrounding data points
        var prev: ?LatencyDataPoint = null;
        var next: ?LatencyDataPoint = null;

        for (data) |point| {
            if (point.timestamp <= event_time) {
                prev = point;
            } else {
                next = point;
                break;
            }
        }

        // Edge cases
        if (prev == null) return data[0].latency_ns;
        if (next == null) return prev.?.latency_ns;

        // Linear interpolation
        const t_diff = next.?.timestamp - prev.?.timestamp;
        if (t_diff == 0) return prev.?.latency_ns;

        const t = @as(f64, @floatFromInt(event_time - prev.?.timestamp)) /
            @as(f64, @floatFromInt(t_diff));

        const prev_lat = @as(f64, @floatFromInt(prev.?.latency_ns));
        const next_lat = @as(f64, @floatFromInt(next.?.latency_ns));
        const latency = prev_lat * (1.0 - t) + next_lat * t;

        return @max(0, @as(i64, @intFromFloat(latency)));
    }

    /// Set random seed for reproducible results
    pub fn setSeed(self: *Self, seed: u64) void {
        self.rng_state = seed;
    }
};

// ============================================================================
// Order Timeline
// ============================================================================

/// Complete order execution timeline
pub const OrderTimeline = struct {
    /// Time strategy submits order (local time)
    strategy_submit: i64,
    /// Time order arrives at exchange
    exchange_arrive: i64,
    /// Time exchange finishes processing
    exchange_process: i64,
    /// Time strategy receives acknowledgment
    strategy_ack: i64,
    /// Total round-trip latency
    total_roundtrip: i64,

    const Self = @This();

    /// Calculate entry latency (submit -> arrive)
    pub fn entryLatency(self: Self) i64 {
        return self.exchange_arrive - self.strategy_submit;
    }

    /// Calculate response latency (process -> ack)
    pub fn responseLatency(self: Self) i64 {
        return self.strategy_ack - self.exchange_process;
    }

    /// Calculate exchange processing time
    pub fn processingTime(self: Self) i64 {
        return self.exchange_process - self.exchange_arrive;
    }

    /// Get entry latency in milliseconds
    pub fn entryLatencyMs(self: Self) f64 {
        return @as(f64, @floatFromInt(self.entryLatency())) / 1_000_000.0;
    }

    /// Get response latency in milliseconds
    pub fn responseLatencyMs(self: Self) f64 {
        return @as(f64, @floatFromInt(self.responseLatency())) / 1_000_000.0;
    }

    /// Get total roundtrip in milliseconds
    pub fn roundtripMs(self: Self) f64 {
        return @as(f64, @floatFromInt(self.total_roundtrip)) / 1_000_000.0;
    }
};

// ============================================================================
// Order Latency Model
// ============================================================================

/// Order execution latency model
/// Models both entry (submit) and response (ack) latencies separately
pub const OrderLatencyModel = struct {
    /// Entry latency: strategy -> exchange
    entry_latency: LatencyModel,
    /// Response latency: exchange -> strategy
    response_latency: LatencyModel,
    /// Exchange processing time (nanoseconds, usually small)
    exchange_process_ns: i64,

    const Self = @This();

    /// Create default model (10ms round-trip)
    pub fn default() Self {
        return .{
            .entry_latency = LatencyModel.constantMs(5), // 5ms
            .response_latency = LatencyModel.constantMs(5), // 5ms
            .exchange_process_ns = 100_000, // 100μs
        };
    }

    /// Create constant latency model
    pub fn constant(entry_ms: i64, response_ms: i64) Self {
        return .{
            .entry_latency = LatencyModel.constantMs(entry_ms),
            .response_latency = LatencyModel.constantMs(response_ms),
            .exchange_process_ns = 100_000,
        };
    }

    /// Create normal distribution model
    pub fn normalDistribution(
        entry_mean_ms: i64,
        entry_std_ms: i64,
        response_mean_ms: i64,
        response_std_ms: i64,
    ) Self {
        return .{
            .entry_latency = LatencyModel.normalMs(entry_mean_ms, entry_std_ms),
            .response_latency = LatencyModel.normalMs(response_mean_ms, response_std_ms),
            .exchange_process_ns = 100_000,
        };
    }

    /// Set exchange processing time
    pub fn setExchangeProcessTime(self: *Self, process_ns: i64) void {
        self.exchange_process_ns = process_ns;
    }

    /// Simulate complete order flow
    pub fn simulateOrderFlow(self: *Self, submit_time: i64) OrderTimeline {
        const arrive_time = self.entry_latency.simulate(submit_time);
        const process_time = arrive_time + self.exchange_process_ns;
        const ack_time = self.response_latency.simulate(process_time);

        return .{
            .strategy_submit = submit_time,
            .exchange_arrive = arrive_time,
            .exchange_process = process_time,
            .strategy_ack = ack_time,
            .total_roundtrip = ack_time - submit_time,
        };
    }

    /// Set random seeds for reproducible results
    pub fn setSeeds(self: *Self, entry_seed: u64, response_seed: u64) void {
        self.entry_latency.setSeed(entry_seed);
        self.response_latency.setSeed(response_seed);
    }
};

// ============================================================================
// Feed Latency Model
// ============================================================================

/// Feed (market data) latency model
pub const FeedLatencyModel = struct {
    /// Base latency model
    latency: LatencyModel,

    const Self = @This();

    /// Create default model (10ms constant)
    pub fn default() Self {
        return .{
            .latency = LatencyModel.constantMs(10),
        };
    }

    /// Create constant latency model
    pub fn constant(latency_ms: i64) Self {
        return .{
            .latency = LatencyModel.constantMs(latency_ms),
        };
    }

    /// Create normal distribution model
    pub fn normalDistribution(mean_ms: i64, std_ms: i64) Self {
        return .{
            .latency = LatencyModel.normalMs(mean_ms, std_ms),
        };
    }

    /// Simulate feed event latency
    pub fn simulate(self: *Self, exchange_time: i64) i64 {
        return self.latency.simulate(exchange_time);
    }

    /// Get latency value
    pub fn getLatency(self: *Self, exchange_time: i64) i64 {
        return self.latency.getLatency(exchange_time);
    }

    /// Set random seed
    pub fn setSeed(self: *Self, seed: u64) void {
        self.latency.setSeed(seed);
    }
};

// ============================================================================
// Latency Simulator
// ============================================================================

/// Complete dual latency simulator
/// Combines feed latency and order latency models
pub const LatencySimulator = struct {
    /// Feed (market data) latency model
    feed_latency: FeedLatencyModel,
    /// Order execution latency model
    order_latency: OrderLatencyModel,

    const Self = @This();

    /// Create default simulator
    pub fn default() Self {
        return .{
            .feed_latency = FeedLatencyModel.default(),
            .order_latency = OrderLatencyModel.default(),
        };
    }

    /// Create with constant latencies
    pub fn constant(feed_ms: i64, entry_ms: i64, response_ms: i64) Self {
        return .{
            .feed_latency = FeedLatencyModel.constant(feed_ms),
            .order_latency = OrderLatencyModel.constant(entry_ms, response_ms),
        };
    }

    /// Create zero-latency simulator (for testing)
    pub fn zeroLatency() Self {
        return .{
            .feed_latency = FeedLatencyModel.constant(0),
            .order_latency = OrderLatencyModel.constant(0, 0),
        };
    }

    /// Simulate feed event (market data) delay
    /// Returns local timestamp when strategy receives the data
    pub fn simulateFeedEvent(self: *Self, exchange_time: i64) i64 {
        return self.feed_latency.simulate(exchange_time);
    }

    /// Simulate order submission
    /// Returns complete order timeline
    pub fn simulateOrderSubmit(self: *Self, submit_time: i64) OrderTimeline {
        return self.order_latency.simulateOrderFlow(submit_time);
    }

    /// Get current feed latency estimate
    pub fn getFeedLatency(self: *Self, time: i64) i64 {
        return self.feed_latency.getLatency(time);
    }

    /// Get current order round-trip estimate
    pub fn getOrderRoundtrip(self: *Self, time: i64) i64 {
        const entry = self.order_latency.entry_latency.getLatency(time);
        const response = self.order_latency.response_latency.getLatency(time);
        return entry + self.order_latency.exchange_process_ns + response;
    }

    /// Set all random seeds for reproducibility
    pub fn setSeeds(self: *Self, feed_seed: u64, entry_seed: u64, response_seed: u64) void {
        self.feed_latency.setSeed(feed_seed);
        self.order_latency.setSeeds(entry_seed, response_seed);
    }
};

// ============================================================================
// Latency Statistics
// ============================================================================

/// Latency statistics tracker
pub const LatencyStats = struct {
    /// Sample count
    count: u64,
    /// Sum of latencies (for mean)
    sum_ns: i64,
    /// Sum of squared latencies (for std)
    sum_squared_ns: i128,
    /// Minimum latency
    min_ns: i64,
    /// Maximum latency
    max_ns: i64,

    const Self = @This();

    pub fn init() Self {
        return .{
            .count = 0,
            .sum_ns = 0,
            .sum_squared_ns = 0,
            .min_ns = std.math.maxInt(i64),
            .max_ns = 0,
        };
    }

    /// Record a latency sample
    pub fn record(self: *Self, latency_ns: i64) void {
        self.count += 1;
        self.sum_ns += latency_ns;
        self.sum_squared_ns += @as(i128, latency_ns) * @as(i128, latency_ns);
        self.min_ns = @min(self.min_ns, latency_ns);
        self.max_ns = @max(self.max_ns, latency_ns);
    }

    /// Get mean latency in nanoseconds
    pub fn meanNs(self: Self) i64 {
        if (self.count == 0) return 0;
        return @divTrunc(self.sum_ns, @as(i64, @intCast(self.count)));
    }

    /// Get mean latency in milliseconds
    pub fn meanMs(self: Self) f64 {
        return @as(f64, @floatFromInt(self.meanNs())) / 1_000_000.0;
    }

    /// Get standard deviation in nanoseconds
    pub fn stdNs(self: Self) i64 {
        if (self.count < 2) return 0;

        const n = @as(i128, @intCast(self.count));
        const mean = @as(i128, self.sum_ns) / n;
        const variance = (self.sum_squared_ns / n) - (mean * mean);

        if (variance <= 0) return 0;
        return @intCast(@as(i128, @intFromFloat(@sqrt(@as(f64, @floatFromInt(variance))))));
    }

    /// Get standard deviation in milliseconds
    pub fn stdMs(self: Self) f64 {
        return @as(f64, @floatFromInt(self.stdNs())) / 1_000_000.0;
    }

    /// Get minimum latency in milliseconds
    pub fn minMs(self: Self) f64 {
        if (self.count == 0) return 0;
        return @as(f64, @floatFromInt(self.min_ns)) / 1_000_000.0;
    }

    /// Get maximum latency in milliseconds
    pub fn maxMs(self: Self) f64 {
        if (self.count == 0) return 0;
        return @as(f64, @floatFromInt(self.max_ns)) / 1_000_000.0;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "LatencyModel: constant latency" {
    var model = LatencyModel.constant(10_000_000); // 10ms
    const delayed = model.simulate(1000);
    try std.testing.expectEqual(@as(i64, 1000 + 10_000_000), delayed);
}

test "LatencyModel: constant latency ms helper" {
    var model = LatencyModel.constantMs(10); // 10ms
    const latency = model.getLatency(0);
    try std.testing.expectEqual(@as(i64, 10_000_000), latency);
}

test "LatencyModel: normal distribution" {
    var model = LatencyModel.normalMs(10, 2); // 10ms ± 2ms
    model.setSeed(12345);

    var total: i64 = 0;
    const samples: i64 = 1000;
    var min_sample: i64 = std.math.maxInt(i64);
    var max_sample: i64 = 0;

    for (0..@intCast(samples)) |_| {
        const latency = model.getLatency(0);
        total += latency;
        min_sample = @min(min_sample, latency);
        max_sample = @max(max_sample, latency);
    }

    const avg = @divFloor(total, samples);
    const avg_ms = @as(f64, @floatFromInt(avg)) / 1_000_000.0;

    // Mean should be close to 10ms
    try std.testing.expect(avg_ms > 8.0 and avg_ms < 12.0);

    // Should have some variation
    try std.testing.expect(max_sample > min_sample);
}

test "LatencyModel: interpolated" {
    const data = [_]LatencyDataPoint{
        .{ .timestamp = 0, .latency_ns = 5_000_000 }, // 5ms at t=0
        .{ .timestamp = 100, .latency_ns = 15_000_000 }, // 15ms at t=100
    };

    var model = LatencyModel.interpolated(&data);

    // At t=0, should be 5ms
    try std.testing.expectEqual(@as(i64, 5_000_000), model.getLatency(0));

    // At t=100, should be 15ms
    try std.testing.expectEqual(@as(i64, 15_000_000), model.getLatency(100));

    // At t=50, should be 10ms (interpolated)
    try std.testing.expectEqual(@as(i64, 10_000_000), model.getLatency(50));
}

test "OrderTimeline: calculations" {
    const timeline = OrderTimeline{
        .strategy_submit = 0,
        .exchange_arrive = 5_000_000, // 5ms
        .exchange_process = 5_100_000, // 5.1ms
        .strategy_ack = 10_100_000, // 10.1ms
        .total_roundtrip = 10_100_000,
    };

    try std.testing.expectEqual(@as(i64, 5_000_000), timeline.entryLatency());
    try std.testing.expectEqual(@as(i64, 5_000_000), timeline.responseLatency());
    try std.testing.expectEqual(@as(i64, 100_000), timeline.processingTime());
    try std.testing.expectApproxEqAbs(@as(f64, 10.1), timeline.roundtripMs(), 0.001);
}

test "OrderLatencyModel: default" {
    var model = OrderLatencyModel.default();
    const timeline = model.simulateOrderFlow(0);

    // Should have positive latencies
    try std.testing.expect(timeline.total_roundtrip > 0);
    try std.testing.expect(timeline.exchange_arrive > timeline.strategy_submit);
    try std.testing.expect(timeline.strategy_ack > timeline.exchange_process);

    // Default is 10ms round-trip (5ms + 0.1ms + 5ms)
    const expected_roundtrip = 10_100_000; // 10.1ms
    try std.testing.expectEqual(@as(i64, expected_roundtrip), timeline.total_roundtrip);
}

test "OrderLatencyModel: normal distribution" {
    var model = OrderLatencyModel.normalDistribution(8, 2, 7, 2);
    model.setSeeds(12345, 67890);

    var total_roundtrip: i64 = 0;
    const samples: i64 = 100;

    for (0..@intCast(samples)) |_| {
        const timeline = model.simulateOrderFlow(0);
        total_roundtrip += timeline.total_roundtrip;
    }

    const avg_roundtrip_ms = @as(f64, @floatFromInt(@divFloor(total_roundtrip, samples))) / 1_000_000.0;

    // Average should be around 15ms (8ms + 0.1ms + 7ms)
    try std.testing.expect(avg_roundtrip_ms > 10.0 and avg_roundtrip_ms < 20.0);
}

test "FeedLatencyModel: basic" {
    var model = FeedLatencyModel.constant(10);
    const local_time = model.simulate(1000);
    try std.testing.expectEqual(@as(i64, 1000 + 10_000_000), local_time);
}

test "LatencySimulator: default" {
    var sim = LatencySimulator.default();

    // Feed latency
    const local_time = sim.simulateFeedEvent(0);
    try std.testing.expectEqual(@as(i64, 10_000_000), local_time);

    // Order roundtrip
    const timeline = sim.simulateOrderSubmit(0);
    try std.testing.expectEqual(@as(i64, 10_100_000), timeline.total_roundtrip);
}

test "LatencySimulator: zero latency" {
    var sim = LatencySimulator.zeroLatency();

    const local_time = sim.simulateFeedEvent(1000);
    try std.testing.expectEqual(@as(i64, 1000), local_time);

    const timeline = sim.simulateOrderSubmit(1000);
    // Only exchange processing time
    try std.testing.expectEqual(@as(i64, 100_000), timeline.total_roundtrip);
}

test "LatencyStats: tracking" {
    var stats = LatencyStats.init();

    stats.record(10_000_000); // 10ms
    stats.record(12_000_000); // 12ms
    stats.record(8_000_000); // 8ms

    try std.testing.expectEqual(@as(u64, 3), stats.count);
    try std.testing.expectEqual(@as(i64, 10_000_000), stats.meanNs());
    try std.testing.expectApproxEqAbs(@as(f64, 10.0), stats.meanMs(), 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 8.0), stats.minMs(), 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 12.0), stats.maxMs(), 0.001);
}
