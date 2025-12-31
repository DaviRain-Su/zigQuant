//! Backtest Engine - Core Engine
//!
//! Main backtesting orchestrator using event-driven simulation.
//! Refactored to use the new IStrategy interface with separate
//! indicator calculation and signal generation methods.

const std = @import("std");
const Decimal = @import("../core/decimal.zig").Decimal;
const Timestamp = @import("../core/time.zig").Timestamp;
const Logger = @import("../core/logger.zig").Logger;
const Candle = @import("../market/candles.zig").Candle;
const Candles = @import("../market/candles.zig").Candles;
const IStrategy = @import("../strategy/interface.zig").IStrategy;
const StrategyContext = @import("../strategy/interface.zig").StrategyContext;
const Signal = @import("../strategy/signal.zig").Signal;
const SignalType = @import("../strategy/signal.zig").SignalType;
const PositionSide = @import("types.zig").PositionSide;

const BacktestConfig = @import("types.zig").BacktestConfig;
const BacktestResult = @import("types.zig").BacktestResult;
const Trade = @import("types.zig").Trade;
const EquitySnapshot = @import("types.zig").EquitySnapshot;
const BacktestError = @import("types.zig").BacktestError;

const HistoricalDataFeed = @import("data_feed.zig").HistoricalDataFeed;
const OrderExecutor = @import("executor.zig").OrderExecutor;
const OrderEvent = @import("event.zig").OrderEvent;
const Account = @import("account.zig").Account;
const Position = @import("position.zig").Position;
const PositionManager = @import("position.zig").PositionManager;

// ============================================================================
// Backtest Engine
// ============================================================================

/// Main backtesting engine
pub const BacktestEngine = struct {
    allocator: std.mem.Allocator,
    logger: Logger,
    data_feed: HistoricalDataFeed,

    pub fn init(allocator: std.mem.Allocator, logger: Logger) BacktestEngine {
        return .{
            .allocator = allocator,
            .logger = logger,
            .data_feed = HistoricalDataFeed.init(allocator, logger),
        };
    }

    /// Run backtest for given strategy and configuration (legacy method)
    /// Run backtest (with chunked processing for memory efficiency)
    pub fn run(
        self: *BacktestEngine,
        strategy: IStrategy,
        config: BacktestConfig,
        progress_callback: ?*const fn (progress: f64, current: usize, total: usize) void,
    ) !BacktestResult {
        return self.runChunked(strategy, config, progress_callback, 10_000);
    }

    /// Run backtest with chunked data processing for memory efficiency
    pub fn runChunked(
        self: *BacktestEngine,
        strategy: IStrategy,
        config: BacktestConfig,
        progress_callback: ?*const fn (progress: f64, current: usize, total: usize) void,
        chunk_size: usize,
    ) !BacktestResult {
        const metadata = strategy.getMetadata();
        try self.logger.info("Starting chunked backtest: {s} on {s}/{s} (chunk_size={d})", .{
            metadata.name,
            config.pair.base,
            config.pair.quote,
            chunk_size,
        });

        // 1. Validate configuration
        try config.validate();

        // 2. Create chunked data iterator
        const data_file = config.data_file orelse return BacktestError.DataFeedError;
        var iterator = try self.data_feed.createChunkedIterator(
            config.pair,
            config.timeframe,
            data_file,
            chunk_size,
        );
        defer iterator.deinit();

        // Check if we have any data by getting first chunk
        var first_chunk = (try iterator.nextChunk()) orelse return BacktestError.InsufficientData;
        defer first_chunk.deinit();

        if (first_chunk.candles.len < 10) {
            return BacktestError.InsufficientData;
        }

        try self.logger.info("Starting chunked processing with chunk_size={d}", .{chunk_size});

        // 3. Initialize strategy
        const strategy_context = StrategyContext{
            .allocator = self.allocator,
            .logger = self.logger,
        };
        try strategy.init(strategy_context);

        // 4. Initialize account and position manager (persistent across chunks)
        var account = Account.init(config.initial_capital);
        var position_mgr = PositionManager.init(self.allocator);
        var executor = OrderExecutor.init(self.allocator, self.logger, config);

        var trades = try std.ArrayList(Trade).initCapacity(self.allocator, 50);
        defer trades.deinit(self.allocator);

        var equity_curve = try std.ArrayList(EquitySnapshot).initCapacity(self.allocator, 100_000);
        defer equity_curve.deinit(self.allocator);

        // 5. Process chunks
        try self.logger.info("Starting chunked simulation...", .{});

        var total_candles_processed: usize = 0;

        // Process first chunk
        try self.processChunk(
            strategy,
            &account,
            &position_mgr,
            &executor,
            &trades,
            &equity_curve,
            first_chunk,
            &total_candles_processed,
            progress_callback,
        );

        // Process remaining chunks
        while (try iterator.nextChunk()) |chunk_val| {
            var chunk = chunk_val;
            defer chunk.deinit();

            try self.processChunk(
                strategy,
                &account,
                &position_mgr,
                &executor,
                &trades,
                &equity_curve,
                chunk,
                &total_candles_processed,
                progress_callback,
            );
        }

        // 6. Force close remaining positions (using last processed candle info)
        if (position_mgr.getPosition()) |pos| {
            // Create a synthetic exit signal with current market price
            // In a real implementation, you'd want to get the actual last candle
            const force_exit_signal = Signal{
                .timestamp = Timestamp{ .millis = std.time.timestamp() * 1000 },
                .pair = config.pair,
                .type = if (pos.side == .long) .exit_long else .exit_short,
                .side = if (pos.side == .long) .sell else .buy,
                .price = pos.entry_price, // Use entry price as approximation
                .strength = 1.0,
                .metadata = null,
            };

            // Create a synthetic candle for exit
            const synthetic_candle = Candle{
                .timestamp = force_exit_signal.timestamp,
                .open = pos.entry_price,
                .high = pos.entry_price,
                .low = pos.entry_price,
                .close = pos.entry_price,
                .volume = Decimal.fromInt(0),
            };

            try self.handleExit(
                &executor,
                &position_mgr,
                &account,
                &trades,
                force_exit_signal,
                synthetic_candle,
            );

            try self.logger.warn("Force closed remaining position", .{});
        }

        // 7. Generate results
        try self.logger.info("Chunked backtest complete: {} trades, {} total candles processed", .{ trades.items.len, total_candles_processed });

        var result = BacktestResult.init(
            self.allocator,
            config,
            metadata.name,
        );

        result.trades = try trades.toOwnedSlice(self.allocator);
        result.equity_curve = try equity_curve.toOwnedSlice(self.allocator);

        try result.calculateStats();

        return result;
    }

    /// Handle entry signal
    fn handleEntry(
        self: *BacktestEngine,
        executor: *OrderExecutor,
        position_mgr: *PositionManager,
        account: *Account,
        strategy: IStrategy,
        signal: Signal,
        candle: Candle,
    ) !void {
        // 1. Calculate position size using strategy's position sizing logic
        const position_size = try strategy.calculatePositionSize(signal, account.*);

        // Verify sufficient funds
        const entry_cost = candle.close.mul(position_size);
        if (!account.hasSufficientFunds(entry_cost)) {
            try self.logger.warn("Insufficient funds for entry", .{});
            return;
        }

        // Verify position size is valid (positive)
        if (!position_size.isPositive()) {
            try self.logger.warn("Invalid position size from strategy: {}", .{position_size});
            return;
        }

        // 2. Create market order
        const order_side = switch (signal.type) {
            .entry_long => OrderEvent.OrderSide.buy,
            .entry_short => OrderEvent.OrderSide.sell,
            else => return,
        };

        const order = OrderEvent{
            .id = executor.generateOrderId(),
            .timestamp = signal.timestamp,
            .pair = signal.pair,
            .side = order_side,
            .order_type = .market,
            .price = signal.price,
            .size = position_size,
        };

        // 3. Execute order (simulate fill)
        const fill = try executor.executeMarketOrder(order, candle);

        // 4. Update account balance
        const cost = fill.fill_price.mul(fill.fill_size);
        const total_cost = cost.add(fill.commission);
        account.balance = account.balance.sub(total_cost);
        account.total_commission = account.total_commission.add(fill.commission);

        // 5. Open position
        const pos_side = if (signal.type == .entry_long) PositionSide.long else PositionSide.short;
        const position = Position.init(
            signal.pair,
            pos_side,
            fill.fill_size,
            fill.fill_price,
            signal.timestamp,
        );
        try position_mgr.openPosition(position);

        try self.logger.info("Opened {s} position: {d:.6} @ {d:.2}", .{
            @tagName(pos_side),
            fill.fill_size.toFloat(),
            fill.fill_price.toFloat(),
        });
    }

    /// Handle exit signal
    fn handleExit(
        self: *BacktestEngine,
        executor: *OrderExecutor,
        position_mgr: *PositionManager,
        account: *Account,
        trades: *std.ArrayList(Trade),
        signal: Signal,
        candle: Candle,
    ) !void {
        const position = position_mgr.getPosition() orelse return;

        // 1. Create exit order (opposite side)
        const order_side = OrderEvent.OrderSide.fromPositionSideExit(position.side);

        const order = OrderEvent{
            .id = executor.generateOrderId(),
            .timestamp = signal.timestamp,
            .pair = signal.pair,
            .side = order_side,
            .order_type = .market,
            .price = signal.price,
            .size = position.size,
        };

        // 2. Execute order
        const fill = try executor.executeMarketOrder(order, candle);

        // 3. Calculate P&L
        const pnl = position.calculatePnL(fill.fill_price);
        const net_pnl = pnl.sub(fill.commission);

        // 4. Update account
        const proceeds = fill.fill_price.mul(fill.fill_size);
        account.balance = account.balance.add(proceeds);
        account.balance = account.balance.add(net_pnl);
        account.total_commission = account.total_commission.add(fill.commission);

        // 5. Calculate trade metrics
        const duration_ms = signal.timestamp.millis - position.entry_time.millis;
        const duration_minutes: u64 = if (duration_ms > 0)
            @intCast(@divTrunc(duration_ms, 60000))
        else
            0; // Prevent negative duration

        const entry_cost = position.entry_price.mul(position.size);
        const pnl_percent = try net_pnl.div(entry_cost);

        // 6. Record trade
        try trades.append(self.allocator, Trade{
            .id = order.id,
            .pair = position.pair,
            .side = position.side,
            .entry_time = position.entry_time,
            .exit_time = signal.timestamp,
            .entry_price = position.entry_price,
            .exit_price = fill.fill_price,
            .size = position.size,
            .pnl = net_pnl,
            .pnl_percent = pnl_percent,
            .commission = fill.commission,
            .duration_minutes = duration_minutes,
        });

        try self.logger.info("Closed position: PnL={d:.2}, Return={d:.2}%", .{
            net_pnl.toFloat(),
            pnl_percent.toFloat() * 100,
        });

        // 7. Close position
        position_mgr.closePosition();
    }

    /// Process a single chunk of candles (contains {d} candles)
    fn processChunk(
        self: *BacktestEngine,
        strategy: IStrategy,
        account: *Account,
        position_mgr: *PositionManager,
        executor: *OrderExecutor,
        trades: *std.ArrayList(Trade),
        equity_curve: *std.ArrayList(EquitySnapshot),
        chunk: Candles,
        total_processed: *usize,
        progress_callback: ?*const fn (progress: f64, current: usize, total: usize) void,
    ) !void {
        // Create mutable copy for indicators calculation
        var mutable_candles = Candles.init(self.allocator, chunk.pair, chunk.timeframe);
        defer mutable_candles.deinit();

        // Copy candle data
        var candle_list = try std.ArrayList(Candle).initCapacity(self.allocator, chunk.candles.len);
        defer candle_list.deinit(self.allocator);
        try candle_list.appendSlice(self.allocator, chunk.candles);

        // Create new candles with mutable data
        mutable_candles.candles = try candle_list.toOwnedSlice(self.allocator);

        // Calculate indicators for this chunk
        try strategy.populateIndicators(&mutable_candles);

        // Process each candle in the chunk
        for (mutable_candles.candles, 0..) |candle, i| {
            const global_index = total_processed.* + i;

            // 6.1 Update position unrealized P&L
            if (position_mgr.getPosition()) |pos| {
                pos.updateUnrealizedPnL(candle.close);
                try account.updateEquity(pos.unrealized_pnl);
            } else {
                try account.updateEquity(Decimal.ZERO);
            }

            // 6.2 Record equity snapshot
            try equity_curve.append(self.allocator, EquitySnapshot{
                .timestamp = candle.timestamp,
                .equity = account.equity,
                .balance = account.balance,
                .unrealized_pnl = if (position_mgr.getPosition()) |pos|
                    pos.unrealized_pnl
                else
                    Decimal.ZERO,
            });

            // 6.3 Check for exit signal if we have a position
            if (position_mgr.hasPosition()) {
                const current_position = position_mgr.getPosition().?;
                const exit_signal = try strategy.generateExitSignal(&mutable_candles, current_position.*);

                if (exit_signal) |signal| {
                    defer signal.deinit();
                    try self.handleExit(
                        executor,
                        position_mgr,
                        account,
                        trades,
                        signal,
                        candle,
                    );
                    continue; // Skip entry check after exit
                }
            }

            // 6.4 Check for entry signal if we don't have a position
            if (!position_mgr.hasPosition()) {
                const entry_signal = try strategy.generateEntrySignal(&mutable_candles, i);

                if (entry_signal) |signal| {
                    defer signal.deinit();
                    try self.handleEntry(
                        executor,
                        position_mgr,
                        account,
                        strategy,
                        signal,
                        candle,
                    );
                }
            }

            // 6.5 Progress logging and callback
            if (global_index > 0 and global_index % 1000 == 0) {
                const progress = @as(f64, @floatFromInt(global_index)) / @as(f64, @floatFromInt(258_000_000)); // Estimate for 1s data
                try self.logger.debug("Progress: {d:.1}% (candle {d})", .{ progress * 100, global_index });
                if (progress_callback) |callback| {
                    callback(progress, global_index, 258_000_000);
                }
            }
        }

        total_processed.* += chunk.candles.len;
    }
};

// ============================================================================
// Tests (Will run integration tests from separate file)
// ============================================================================
