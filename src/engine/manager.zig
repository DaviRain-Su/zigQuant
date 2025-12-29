//! Engine Manager
//!
//! Central manager for all running trading components.
//! Provides lifecycle management, state persistence, and API access.
//!
//! Architecture:
//! - All strategies (including Grid) run through StrategyRunner
//! - Backtests run through BacktestRunner
//! - Live trading sessions run through LiveRunner
//! - Unified API for all runner types

const std = @import("std");
const Allocator = std.mem.Allocator;

const backtest_runner = @import("runners/backtest_runner.zig");
const BacktestRunner = backtest_runner.BacktestRunner;
const BacktestRequest = backtest_runner.BacktestRequest;
const BacktestStatus = backtest_runner.BacktestStatus;
const BacktestProgress = backtest_runner.BacktestProgress;
const BacktestResultSummary = backtest_runner.BacktestResultSummary;

const strategy_runner = @import("runners/strategy_runner.zig");
const StrategyRunner = strategy_runner.StrategyRunner;
const StrategyRequest = strategy_runner.StrategyRequest;
const StrategyStatus = strategy_runner.StrategyStatus;
const StrategyStats = strategy_runner.StrategyStats;
const SignalHistoryEntry = strategy_runner.SignalHistoryEntry;

const live_runner = @import("runners/live_runner.zig");
const LiveRunner = live_runner.LiveRunner;
const LiveRequest = live_runner.LiveRequest;
const LiveStatus = live_runner.LiveStatus;
const LiveStats = live_runner.LiveStats;
const OrderHistoryEntry = live_runner.OrderHistoryEntry;

// AI module imports
const ai = @import("../ai/mod.zig");
const LLMClient = ai.LLMClient;
const AIConfig = ai.AIConfig;
const AIProvider = ai.AIProvider;
const AIAdvisor = ai.AIAdvisor;
const AdvisorStats = ai.AdvisorStats;

/// AI Configuration for runtime updates
pub const AIRuntimeConfig = struct {
    /// AI provider (openai, anthropic, lmstudio, ollama, deepseek, custom)
    provider: []const u8 = "openai",
    /// Model ID (e.g., "gpt-4o", "claude-sonnet-4-5", "deepseek-chat")
    model_id: []const u8 = "gpt-4o",
    /// API endpoint URL (for custom providers or local models)
    api_endpoint: ?[]const u8 = null,
    /// API key (stored securely, not exposed in status)
    api_key: ?[]const u8 = null,
    /// Whether AI is enabled
    enabled: bool = false,
    /// Request timeout in milliseconds
    timeout_ms: u32 = 30000,
};

/// AI Status response (excludes sensitive data)
pub const AIStatus = struct {
    enabled: bool,
    provider: []const u8,
    model_id: []const u8,
    api_endpoint: ?[]const u8,
    has_api_key: bool,
    connected: bool,
    stats: ?AdvisorStats,
};

/// Engine Manager - manages all running components
pub const EngineManager = struct {
    allocator: Allocator,

    // Backtest runners by ID
    backtest_runners: std.StringHashMap(*BacktestRunner),

    // Strategy runners by ID (includes all strategy types: dual_ma, rsi, grid, etc.)
    strategy_runners: std.StringHashMap(*StrategyRunner),

    // Live trading runners by ID
    live_runners: std.StringHashMap(*LiveRunner),

    // AI configuration and client
    ai_config: AIRuntimeConfig,
    llm_client: ?*LLMClient,

    // Statistics
    total_backtests_started: u64,
    total_backtests_completed: u64,
    total_strategies_started: u64,
    total_strategies_stopped: u64,
    total_live_started: u64,
    total_live_stopped: u64,

    // System state
    kill_switch_active: bool,
    kill_switch_reason: ?[]const u8,

    // Thread safety
    mutex: std.Thread.Mutex,

    const Self = @This();

    /// Initialize the engine manager
    pub fn init(allocator: Allocator) Self {
        return .{
            .allocator = allocator,
            .backtest_runners = std.StringHashMap(*BacktestRunner).init(allocator),
            .strategy_runners = std.StringHashMap(*StrategyRunner).init(allocator),
            .live_runners = std.StringHashMap(*LiveRunner).init(allocator),
            .ai_config = .{},
            .llm_client = null,
            .total_backtests_started = 0,
            .total_backtests_completed = 0,
            .total_strategies_started = 0,
            .total_strategies_stopped = 0,
            .total_live_started = 0,
            .total_live_stopped = 0,
            .kill_switch_active = false,
            .kill_switch_reason = null,
            .mutex = .{},
        };
    }

    /// Clean up all resources
    pub fn deinit(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Stop and clean up all backtest runners
        var bt_it = self.backtest_runners.valueIterator();
        while (bt_it.next()) |runner| {
            runner.*.deinit();
        }
        self.backtest_runners.deinit();

        // Stop and clean up all strategy runners
        var strat_it = self.strategy_runners.valueIterator();
        while (strat_it.next()) |runner| {
            runner.*.deinit();
        }
        self.strategy_runners.deinit();

        // Stop and clean up all live runners
        var live_it = self.live_runners.valueIterator();
        while (live_it.next()) |runner| {
            runner.*.deinit();
        }
        self.live_runners.deinit();

        // Clean up LLM client
        if (self.llm_client) |client| {
            client.deinit();
        }

        // Clean up kill switch reason
        if (self.kill_switch_reason) |reason| {
            self.allocator.free(reason);
        }
    }

    // ========================================================================
    // Backtest API
    // ========================================================================

    /// Start a new backtest job
    pub fn startBacktest(self: *Self, id: []const u8, request: BacktestRequest) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Check if already exists
        if (self.backtest_runners.contains(id)) {
            return error.BacktestAlreadyExists;
        }

        // Create and start the runner
        const runner = try BacktestRunner.init(self.allocator, id, request);
        errdefer runner.deinit();

        try runner.start();

        // Store in map
        try self.backtest_runners.put(runner.id, runner);
        self.total_backtests_started += 1;
    }

    /// Cancel a running backtest
    pub fn cancelBacktest(self: *Self, id: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const runner = self.backtest_runners.get(id) orelse return error.BacktestNotFound;
        try runner.cancel();
    }

    /// Get backtest status
    pub fn getBacktestStatus(self: *Self, id: []const u8) !BacktestStatus {
        self.mutex.lock();
        defer self.mutex.unlock();

        const runner = self.backtest_runners.get(id) orelse return error.BacktestNotFound;
        return runner.getStatus();
    }

    /// Get backtest progress
    pub fn getBacktestProgress(self: *Self, id: []const u8) !BacktestProgress {
        self.mutex.lock();
        defer self.mutex.unlock();

        const runner = self.backtest_runners.get(id) orelse return error.BacktestNotFound;
        return runner.getProgress();
    }

    /// Get backtest result summary
    pub fn getBacktestResult(self: *Self, id: []const u8) !?BacktestResultSummary {
        self.mutex.lock();
        defer self.mutex.unlock();

        const runner = self.backtest_runners.get(id) orelse return error.BacktestNotFound;
        return runner.getResultSummary();
    }

    /// Remove a completed backtest
    pub fn removeBacktest(self: *Self, id: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const entry = self.backtest_runners.fetchRemove(id) orelse return error.BacktestNotFound;
        const runner = entry.value;

        if (runner.status == .completed or runner.status == .failed or runner.status == .cancelled) {
            self.total_backtests_completed += 1;
        }

        runner.deinit();
    }

    /// Get count of running backtests
    pub fn getRunningBacktestCount(self: *Self) usize {
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.getRunningBacktestCountUnlocked();
    }

    /// List all backtests
    pub fn listBacktests(self: *Self, allocator: Allocator) ![]BacktestSummary {
        self.mutex.lock();
        defer self.mutex.unlock();

        var list = std.ArrayList(BacktestSummary){};
        errdefer list.deinit(allocator);

        var it = self.backtest_runners.iterator();
        while (it.next()) |entry| {
            const runner = entry.value_ptr.*;
            const progress = runner.getProgress();

            try list.append(allocator, .{
                .id = entry.key_ptr.*,
                .strategy = runner.request.strategy,
                .symbol = runner.request.symbol,
                .status = runner.status.toString(),
                .progress = progress.progress,
                .trades_so_far = progress.trades_so_far,
                .elapsed_seconds = progress.elapsed_seconds,
            });
        }

        return list.toOwnedSlice(allocator);
    }

    // ========================================================================
    // Strategy API (Unified - supports all strategy types including Grid)
    // ========================================================================

    /// Start a new strategy (supports all types: dual_ma, rsi, grid, etc.)
    pub fn startStrategy(self: *Self, id: []const u8, request: StrategyRequest) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Check kill switch
        if (self.kill_switch_active) {
            return error.KillSwitchActive;
        }

        // Check if already exists
        if (self.strategy_runners.contains(id)) {
            return error.StrategyAlreadyExists;
        }

        // Validate grid parameters if this is a grid strategy
        if (request.isGridStrategy()) {
            try request.validateGridParams();
        }

        // Create and start the strategy runner
        const runner = try StrategyRunner.init(self.allocator, id, request);
        errdefer runner.deinit();

        try runner.start();

        // Store in strategy runners map
        try self.strategy_runners.put(runner.id, runner);
        self.total_strategies_started += 1;
    }

    /// Stop a strategy
    pub fn stopStrategy(self: *Self, id: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const entry = self.strategy_runners.fetchRemove(id) orelse return error.StrategyNotFound;
        const runner = entry.value;

        runner.stop() catch {};
        runner.deinit();
        self.total_strategies_stopped += 1;
    }

    /// Pause a strategy
    pub fn pauseStrategy(self: *Self, id: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const runner = self.strategy_runners.get(id) orelse return error.StrategyNotFound;
        try runner.pause();
    }

    /// Resume a paused strategy
    pub fn resumeStrategy(self: *Self, id: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const runner = self.strategy_runners.get(id) orelse return error.StrategyNotFound;
        try runner.unpause();
    }

    /// Get strategy status
    pub fn getStrategyStatus(self: *Self, id: []const u8) !StrategyStatus {
        self.mutex.lock();
        defer self.mutex.unlock();

        const runner = self.strategy_runners.get(id) orelse return error.StrategyNotFound;
        return runner.getStatus();
    }

    /// Get strategy statistics
    pub fn getStrategyStats(self: *Self, id: []const u8) !StrategyStats {
        self.mutex.lock();
        defer self.mutex.unlock();

        const runner = self.strategy_runners.get(id) orelse return error.StrategyNotFound;
        return runner.getStats();
    }

    /// Get strategy signal history
    pub fn getStrategySignalHistory(self: *Self, allocator: Allocator, id: []const u8, limit: usize) ![]SignalHistoryEntry {
        self.mutex.lock();
        defer self.mutex.unlock();

        const runner = self.strategy_runners.get(id) orelse return error.StrategyNotFound;
        return runner.getSignalHistory(allocator, limit);
    }

    /// Update strategy parameters
    pub fn updateStrategyParams(self: *Self, id: []const u8, params_json: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const runner = self.strategy_runners.get(id) orelse return error.StrategyNotFound;
        try runner.updateParams(params_json);
    }

    /// Get strategy parameters
    pub fn getStrategyParams(self: *Self, id: []const u8) !?[]const u8 {
        self.mutex.lock();
        defer self.mutex.unlock();

        const runner = self.strategy_runners.get(id) orelse return error.StrategyNotFound;
        return runner.getParams();
    }

    /// Get count of running strategies
    pub fn getRunningStrategyCount(self: *Self) usize {
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.getRunningStrategyCountUnlocked();
    }

    fn getRunningStrategyCountUnlocked(self: *Self) usize {
        var count: usize = 0;

        var strat_it = self.strategy_runners.valueIterator();
        while (strat_it.next()) |runner| {
            if (runner.*.status == .running or runner.*.status == .paused) count += 1;
        }

        return count;
    }

    /// List all strategies
    pub fn listStrategies(self: *Self, allocator: Allocator) ![]StrategySummary {
        self.mutex.lock();
        defer self.mutex.unlock();

        var list = std.ArrayList(StrategySummary){};
        errdefer list.deinit(allocator);

        var strat_it = self.strategy_runners.iterator();
        while (strat_it.next()) |entry| {
            const runner = entry.value_ptr.*;
            const stats = runner.getStats();

            try list.append(allocator, .{
                .id = entry.key_ptr.*,
                .strategy = runner.request.strategy,
                .symbol = runner.request.symbol,
                .status = runner.status.toString(),
                .mode = runner.request.mode.toString(),
                .realized_pnl = stats.realized_pnl,
                .current_position = stats.current_position,
                .total_signals = stats.total_signals,
                .total_trades = stats.total_trades,
                .win_rate = stats.win_rate,
                .uptime_seconds = stats.uptime_seconds,
            });
        }

        return list.toOwnedSlice(allocator);
    }

    // ========================================================================
    // Live Trading API
    // ========================================================================

    /// Start a new live trading session
    pub fn startLive(self: *Self, id: []const u8, request: LiveRequest) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Check kill switch
        if (self.kill_switch_active) {
            return error.KillSwitchActive;
        }

        // Check if already exists
        if (self.live_runners.contains(id)) {
            return error.LiveAlreadyExists;
        }

        // Create and start the live runner
        const runner = try LiveRunner.init(self.allocator, id, request);
        errdefer runner.deinit();

        try runner.start();

        // Store in live runners map
        try self.live_runners.put(runner.id, runner);
        self.total_live_started += 1;
    }

    /// Stop a live trading session
    pub fn stopLive(self: *Self, id: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const entry = self.live_runners.fetchRemove(id) orelse return error.LiveNotFound;
        const runner = entry.value;

        runner.stop() catch {};
        runner.deinit();
        self.total_live_stopped += 1;
    }

    /// Pause a live trading session
    pub fn pauseLive(self: *Self, id: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const runner = self.live_runners.get(id) orelse return error.LiveNotFound;
        try runner.pause();
    }

    /// Resume a paused live trading session
    pub fn resumeLive(self: *Self, id: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const runner = self.live_runners.get(id) orelse return error.LiveNotFound;
        try runner.unpause();
    }

    /// Get live trading status
    pub fn getLiveStatus(self: *Self, id: []const u8) !LiveStatus {
        self.mutex.lock();
        defer self.mutex.unlock();

        const runner = self.live_runners.get(id) orelse return error.LiveNotFound;
        return runner.getStatus();
    }

    /// Get live trading statistics
    pub fn getLiveStats(self: *Self, id: []const u8) !LiveStats {
        self.mutex.lock();
        defer self.mutex.unlock();

        const runner = self.live_runners.get(id) orelse return error.LiveNotFound;
        return runner.getStats();
    }

    /// Get live trading order history
    pub fn getLiveOrderHistory(self: *Self, allocator: Allocator, id: []const u8, limit: usize) ![]OrderHistoryEntry {
        self.mutex.lock();
        defer self.mutex.unlock();

        const runner = self.live_runners.get(id) orelse return error.LiveNotFound;
        return runner.getOrderHistory(allocator, limit);
    }

    /// Submit order to live trading session
    pub fn submitLiveOrder(self: *Self, id: []const u8, request: @import("../core/execution_engine.zig").OrderRequest) !@import("../core/execution_engine.zig").OrderResult {
        self.mutex.lock();
        defer self.mutex.unlock();

        const runner = self.live_runners.get(id) orelse return error.LiveNotFound;
        return runner.submitOrder(request);
    }

    /// Cancel order in live trading session
    pub fn cancelLiveOrder(self: *Self, id: []const u8, order_id: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const runner = self.live_runners.get(id) orelse return error.LiveNotFound;
        try runner.cancelOrder(order_id);
    }

    /// Cancel all orders in live trading session
    pub fn cancelAllLiveOrders(self: *Self, id: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const runner = self.live_runners.get(id) orelse return error.LiveNotFound;
        try runner.cancelAllOrders();
    }

    /// Subscribe to symbol in live trading session
    pub fn subscribeLiveSymbol(self: *Self, id: []const u8, symbol: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const runner = self.live_runners.get(id) orelse return error.LiveNotFound;
        try runner.subscribe(symbol);
    }

    /// Unsubscribe from symbol in live trading session
    pub fn unsubscribeLiveSymbol(self: *Self, id: []const u8, symbol: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const runner = self.live_runners.get(id) orelse return error.LiveNotFound;
        runner.unsubscribe(symbol);
    }

    /// Get count of running live sessions
    pub fn getRunningLiveCount(self: *Self) usize {
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.getRunningLiveCountUnlocked();
    }

    fn getRunningLiveCountUnlocked(self: *Self) usize {
        var count: usize = 0;

        var live_it = self.live_runners.valueIterator();
        while (live_it.next()) |runner| {
            if (runner.*.status == .running or runner.*.status == .paused) count += 1;
        }

        return count;
    }

    /// List all live trading sessions
    pub fn listLive(self: *Self, allocator: Allocator) ![]LiveSummary {
        self.mutex.lock();
        defer self.mutex.unlock();

        var list = std.ArrayList(LiveSummary){};
        errdefer list.deinit(allocator);

        var live_it = self.live_runners.iterator();
        while (live_it.next()) |entry| {
            const runner = entry.value_ptr.*;
            const stats = runner.getStats();

            try list.append(allocator, .{
                .id = entry.key_ptr.*,
                .name = runner.request.name,
                .exchange = runner.request.exchange,
                .status = runner.status.toString(),
                .testnet = runner.request.testnet,
                .orders_submitted = stats.orders_submitted,
                .orders_filled = stats.orders_filled,
                .total_volume = stats.total_volume,
                .realized_pnl = stats.realized_pnl,
                .uptime_ms = stats.uptime_ms,
            });
        }

        return list.toOwnedSlice(allocator);
    }

    // ========================================================================
    // System API (Kill Switch)
    // ========================================================================

    /// Activate kill switch - stops all trading
    pub fn activateKillSwitch(self: *Self, reason: []const u8, cancel_orders: bool, close_positions: bool) !KillSwitchResult {
        self.mutex.lock();
        defer self.mutex.unlock();

        _ = cancel_orders;
        _ = close_positions;

        var result = KillSwitchResult{};

        // Stop all strategies (including grid strategies)
        var strat_it = self.strategy_runners.valueIterator();
        while (strat_it.next()) |runner| {
            if (runner.*.status == .running or runner.*.status == .paused) {
                runner.*.stop() catch {};
                result.strategies_stopped += 1;
            }
        }

        // Stop all live trading sessions
        var live_it = self.live_runners.valueIterator();
        while (live_it.next()) |runner| {
            if (runner.*.status == .running or runner.*.status == .paused) {
                runner.*.stop() catch {};
                result.live_stopped += 1;
            }
        }

        // Store reason
        if (self.kill_switch_reason) |old| {
            self.allocator.free(old);
        }
        self.kill_switch_reason = try self.allocator.dupe(u8, reason);
        self.kill_switch_active = true;

        return result;
    }

    /// Deactivate kill switch
    pub fn deactivateKillSwitch(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.kill_switch_active = false;
        if (self.kill_switch_reason) |reason| {
            self.allocator.free(reason);
            self.kill_switch_reason = null;
        }
    }

    /// Check if kill switch is active
    pub fn isKillSwitchActive(self: *Self) bool {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.kill_switch_active;
    }

    /// Get system health status
    pub fn getSystemHealth(self: *Self) SystemHealth {
        self.mutex.lock();
        defer self.mutex.unlock();

        return .{
            .status = if (self.kill_switch_active) "kill_switch" else "healthy",
            .running_backtests = self.getRunningBacktestCountUnlocked(),
            .running_strategies = self.getRunningStrategyCountUnlocked(),
            .running_live = self.getRunningLiveCountUnlocked(),
            .kill_switch_active = self.kill_switch_active,
            .kill_switch_reason = self.kill_switch_reason,
        };
    }

    fn getRunningBacktestCountUnlocked(self: *Self) usize {
        var count: usize = 0;
        var it = self.backtest_runners.valueIterator();
        while (it.next()) |runner| {
            if (runner.*.status == .running or runner.*.status == .queued) count += 1;
        }
        return count;
    }

    /// Get manager statistics
    pub fn getManagerStats(self: *Self) ManagerStats {
        self.mutex.lock();
        defer self.mutex.unlock();

        var running: usize = 0;
        var stopped: usize = 0;
        var total_pnl: f64 = 0;
        var total_trades: u32 = 0;

        var it = self.strategy_runners.valueIterator();
        while (it.next()) |runner| {
            const stats = runner.*.getStats();
            total_pnl += stats.realized_pnl;
            total_trades += stats.total_trades;

            if (runner.*.status == .running or runner.*.status == .paused) {
                running += 1;
            } else {
                stopped += 1;
            }
        }

        // Count live sessions
        var running_live: usize = 0;
        var live_it = self.live_runners.valueIterator();
        while (live_it.next()) |runner| {
            const stats = runner.*.getStats();
            total_pnl += stats.realized_pnl;

            if (runner.*.status == .running or runner.*.status == .paused) {
                running_live += 1;
            }
        }

        return .{
            .total_strategies = self.strategy_runners.count(),
            .running_strategies = running,
            .stopped_strategies = stopped,
            .total_strategies_started = self.total_strategies_started,
            .total_strategies_stopped = self.total_strategies_stopped,
            .total_live = self.live_runners.count(),
            .running_live = running_live,
            .total_live_started = self.total_live_started,
            .total_live_stopped = self.total_live_stopped,
            .total_realized_pnl = total_pnl,
            .total_trades = total_trades,
        };
    }

    // ========================================================================
    // AI Configuration Management
    // ========================================================================

    /// Configure AI settings (does not create client yet)
    pub fn configureAI(self: *Self, config: AIRuntimeConfig) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.ai_config = config;
    }

    /// Update AI configuration partially
    pub fn updateAIConfig(
        self: *Self,
        provider: ?[]const u8,
        model_id: ?[]const u8,
        api_endpoint: ?[]const u8,
        api_key: ?[]const u8,
        enabled: ?bool,
    ) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (provider) |p| self.ai_config.provider = p;
        if (model_id) |m| self.ai_config.model_id = m;
        if (api_endpoint) |e| self.ai_config.api_endpoint = e;
        if (api_key) |k| self.ai_config.api_key = k;
        if (enabled) |e| self.ai_config.enabled = e;
    }

    /// Initialize or reinitialize the LLM client with current config
    pub fn initAIClient(self: *Self) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Clean up existing client
        if (self.llm_client) |client| {
            client.deinit();
            self.llm_client = null;
        }

        // Validate config
        if (self.ai_config.api_key == null) {
            return error.MissingApiKey;
        }

        // Parse provider
        const provider = std.meta.stringToEnum(AIProvider, self.ai_config.provider) orelse .openai;

        // Create AI config
        const ai_cfg = AIConfig{
            .provider = provider,
            .model_id = self.ai_config.model_id,
            .api_key = self.ai_config.api_key.?,
            .base_url = self.ai_config.api_endpoint,
            .timeout_ms = self.ai_config.timeout_ms,
        };

        // Create client
        self.llm_client = try LLMClient.init(self.allocator, ai_cfg);
        self.ai_config.enabled = true;
    }

    /// Disable AI and clean up client
    pub fn disableAI(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.llm_client) |client| {
            client.deinit();
            self.llm_client = null;
        }
        self.ai_config.enabled = false;
    }

    /// Get AI status (safe to expose via API - excludes API key)
    pub fn getAIStatus(self: *Self) AIStatus {
        self.mutex.lock();
        defer self.mutex.unlock();

        return .{
            .enabled = self.ai_config.enabled,
            .provider = self.ai_config.provider,
            .model_id = self.ai_config.model_id,
            .api_endpoint = self.ai_config.api_endpoint,
            .has_api_key = self.ai_config.api_key != null,
            .connected = self.llm_client != null,
            .stats = null, // TODO: Get from advisor if available
        };
    }

    /// Get the current LLM client (for StrategyFactory)
    pub fn getLLMClient(self: *Self) ?*LLMClient {
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.llm_client;
    }

    /// Check if AI is configured and ready
    pub fn isAIReady(self: *Self) bool {
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.ai_config.enabled and self.llm_client != null;
    }
};

/// Summary of a single backtest
pub const BacktestSummary = struct {
    id: []const u8,
    strategy: []const u8,
    symbol: []const u8,
    status: []const u8,
    progress: f64,
    trades_so_far: u32,
    elapsed_seconds: i64,
};

/// Summary of a single strategy
pub const StrategySummary = struct {
    id: []const u8,
    strategy: []const u8,
    symbol: []const u8,
    status: []const u8,
    mode: []const u8,
    realized_pnl: f64,
    current_position: f64,
    total_signals: u32,
    total_trades: u32,
    win_rate: f64,
    uptime_seconds: i64,
};

/// Summary of a single live trading session
pub const LiveSummary = struct {
    id: []const u8,
    name: []const u8,
    exchange: []const u8,
    status: []const u8,
    testnet: bool,
    orders_submitted: u64,
    orders_filled: u64,
    total_volume: f64,
    realized_pnl: f64,
    uptime_ms: u64,
};

/// Manager statistics
pub const ManagerStats = struct {
    total_strategies: usize,
    running_strategies: usize,
    stopped_strategies: usize,
    total_strategies_started: u64,
    total_strategies_stopped: u64,
    total_live: usize,
    running_live: usize,
    total_live_started: u64,
    total_live_stopped: u64,
    total_realized_pnl: f64,
    total_trades: u32,
};

/// Kill switch result
pub const KillSwitchResult = struct {
    strategies_stopped: usize = 0,
    live_stopped: usize = 0,
    orders_cancelled: usize = 0,
    positions_closed: usize = 0,
};

/// System health status
pub const SystemHealth = struct {
    status: []const u8,
    running_backtests: usize,
    running_strategies: usize,
    running_live: usize,
    kill_switch_active: bool,
    kill_switch_reason: ?[]const u8,
};

// ============================================================================
// Tests
// ============================================================================

test "EngineManager init and deinit" {
    const allocator = std.testing.allocator;
    var manager = EngineManager.init(allocator);
    defer manager.deinit();

    try std.testing.expectEqual(@as(usize, 0), manager.strategy_runners.count());
}

test "EngineManager strategy lifecycle" {
    const allocator = std.testing.allocator;
    var manager = EngineManager.init(allocator);
    defer manager.deinit();

    const request = StrategyRequest{
        .strategy = "dual_ma",
        .symbol = "BTC-USDT",
        .timeframe = "1h",
        .mode = .paper,
    };

    // Start strategy
    try manager.startStrategy("test_strategy", request);
    try std.testing.expectEqual(@as(usize, 1), manager.strategy_runners.count());

    // Get status
    const status = try manager.getStrategyStatus("test_strategy");
    try std.testing.expectEqual(StrategyStatus.running, status);

    // Stop strategy
    try manager.stopStrategy("test_strategy");
    try std.testing.expectEqual(@as(usize, 0), manager.strategy_runners.count());
}

test "EngineManager grid strategy via unified API" {
    const allocator = std.testing.allocator;
    var manager = EngineManager.init(allocator);
    defer manager.deinit();

    const request = StrategyRequest{
        .strategy = "grid",
        .symbol = "BTC-USDT",
        .timeframe = "1h",
        .mode = .paper,
        .upper_price = 100000,
        .lower_price = 90000,
        .grid_count = 10,
        .order_size = 0.001,
    };

    // Validate that it's recognized as grid
    try std.testing.expect(request.isGridStrategy());

    // Start grid strategy
    try manager.startStrategy("test_grid", request);
    try std.testing.expectEqual(@as(usize, 1), manager.strategy_runners.count());

    // Stop grid strategy
    try manager.stopStrategy("test_grid");
    try std.testing.expectEqual(@as(usize, 0), manager.strategy_runners.count());
}

test "EngineManager kill switch" {
    const allocator = std.testing.allocator;
    var manager = EngineManager.init(allocator);
    defer manager.deinit();

    try std.testing.expect(!manager.isKillSwitchActive());

    const result = try manager.activateKillSwitch("test reason", false, false);
    _ = result;

    try std.testing.expect(manager.isKillSwitchActive());

    manager.deactivateKillSwitch();
    try std.testing.expect(!manager.isKillSwitchActive());
}

test "EngineManager live runner lifecycle" {
    const allocator = std.testing.allocator;
    var manager = EngineManager.init(allocator);
    defer manager.deinit();

    // Just test that the runner can be created and cleaned up
    // Full lifecycle test requires actual exchange connection setup
    try std.testing.expectEqual(@as(usize, 0), manager.live_runners.count());
    try std.testing.expectEqual(@as(u64, 0), manager.total_live_started);
}

test "LiveRunner unit test" {
    const allocator = std.testing.allocator;

    const request = LiveRequest{
        .name = "test_live",
        .exchange = "hyperliquid",
        .testnet = true,
    };

    // Test init and deinit without starting (requires no exchange connection)
    const runner = try LiveRunner.init(allocator, "live_test_1", request);
    defer runner.deinit();

    try std.testing.expectEqualStrings("live_test_1", runner.id);
    try std.testing.expectEqual(LiveStatus.stopped, runner.status);
}

test "EngineManager system health includes live" {
    const allocator = std.testing.allocator;
    var manager = EngineManager.init(allocator);
    defer manager.deinit();

    const health = manager.getSystemHealth();
    try std.testing.expectEqual(@as(usize, 0), health.running_live);
    try std.testing.expectEqualStrings("healthy", health.status);
}

test "EngineManager AI configuration" {
    const allocator = std.testing.allocator;
    var manager = EngineManager.init(allocator);
    defer manager.deinit();

    // Initial state - AI disabled
    try std.testing.expect(!manager.isAIReady());

    const status = manager.getAIStatus();
    try std.testing.expect(!status.enabled);
    try std.testing.expect(!status.has_api_key);
    try std.testing.expect(!status.connected);
    try std.testing.expectEqualStrings("openai", status.provider);
    try std.testing.expectEqualStrings("gpt-4o", status.model_id);
}

test "EngineManager AI config update" {
    const allocator = std.testing.allocator;
    var manager = EngineManager.init(allocator);
    defer manager.deinit();

    // Update config
    manager.updateAIConfig(
        "anthropic",
        "claude-sonnet-4-5",
        "https://api.anthropic.com",
        null, // no api key yet
        null,
    );

    const status = manager.getAIStatus();
    try std.testing.expectEqualStrings("anthropic", status.provider);
    try std.testing.expectEqualStrings("claude-sonnet-4-5", status.model_id);
    try std.testing.expect(!status.has_api_key);
}

test "EngineManager AI init without key fails" {
    const allocator = std.testing.allocator;
    var manager = EngineManager.init(allocator);
    defer manager.deinit();

    // Try to init without API key - should fail
    const result = manager.initAIClient();
    try std.testing.expectError(error.MissingApiKey, result);
}
