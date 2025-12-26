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

    /// Run backtest for given strategy and configuration
    pub fn run(
        self: *BacktestEngine,
        strategy: IStrategy,
        config: BacktestConfig,
    ) !BacktestResult {
        const metadata = strategy.getMetadata();
        try self.logger.info("Starting backtest: {s} on {s}/{s}", .{
            metadata.name,
            config.pair.base,
            config.pair.quote,
        });

        // 1. Validate configuration
        try config.validate();

        // 2. Load historical data
        var candles = try self.data_feed.load(
            config.pair,
            config.timeframe,
            config.start_time,
            config.end_time,
        );
        defer candles.deinit();

        if (candles.candles.len < 10) {
            return BacktestError.InsufficientData;
        }

        try self.logger.info("Loaded {} candles", .{candles.candles.len});

        // 3. Initialize strategy
        const strategy_context = StrategyContext{
            .allocator = self.allocator,
            .logger = self.logger,
        };
        try strategy.init(strategy_context);

        // 4. Calculate indicators (populate all indicators once before loop)
        try self.logger.info("Calculating indicators...", .{});
        try strategy.populateIndicators(&candles);
        try self.logger.info("Indicators populated successfully", .{});

        // 5. Initialize account and position manager
        var account = Account.init(config.initial_capital);
        var position_mgr = PositionManager.init(self.allocator);
        var executor = OrderExecutor.init(self.allocator, self.logger, config);

        var trades = try std.ArrayList(Trade).initCapacity(self.allocator, 50);
        defer trades.deinit(self.allocator);

        var equity_curve = try std.ArrayList(EquitySnapshot).initCapacity(
            self.allocator,
            candles.candles.len,
        );
        defer equity_curve.deinit(self.allocator);

        // 6. Event loop - iterate through each candle
        try self.logger.info("Starting simulation...", .{});

        for (candles.candles, 0..) |candle, i| {
            // 6.1 Update position unrealized P&L
            if (position_mgr.getPosition()) |pos| {
                pos.updateUnrealizedPnL(candle.close);
                try account.updateEquity(pos.unrealized_pnl);
            } else {
                try account.updateEquity(Decimal.ZERO);
            }

            // 6.2 Record equity snapshot
            equity_curve.appendAssumeCapacity(EquitySnapshot{
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
                const position = position_mgr.getPosition().?;
                const exit_signal = try strategy.generateExitSignal(&candles, position.*);

                if (exit_signal) |signal| {
                    try self.handleExit(
                        &executor,
                        &position_mgr,
                        &account,
                        &trades,
                        signal,
                        candle,
                    );
                    continue; // Skip entry check after exit
                }
            }

            // 6.4 Check for entry signal if we don't have a position
            if (!position_mgr.hasPosition()) {
                const entry_signal = try strategy.generateEntrySignal(&candles, i);

                if (entry_signal) |signal| {
                    try self.handleEntry(
                        &executor,
                        &position_mgr,
                        &account,
                        strategy,
                        signal,
                        candle,
                    );
                }
            }

            // 6.5 Progress logging
            if (i > 0 and i % 1000 == 0) {
                try self.logger.debug("Progress: {}/{} candles", .{ i, candles.candles.len });
            }
        }

        // 7. Force close remaining positions
        if (position_mgr.getPosition()) |pos| {
            const last_candle = candles.candles[candles.candles.len - 1];
            const force_exit_signal = Signal{
                .timestamp = last_candle.timestamp,
                .pair = config.pair,
                .type = if (pos.side == .long) .exit_long else .exit_short,
                .side = if (pos.side == .long) .sell else .buy,
                .price = last_candle.close,
                .strength = 1.0,
                .metadata = null,
            };

            try self.handleExit(
                &executor,
                &position_mgr,
                &account,
                &trades,
                force_exit_signal,
                last_candle,
            );

            try self.logger.warn("Force closed remaining position", .{});
        }

        // 8. Generate results
        try self.logger.info("Backtest complete: {} trades", .{trades.items.len});

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

        try self.logger.info("Opened {s} position: {} @ {}", .{
            @tagName(pos_side),
            fill.fill_size,
            fill.fill_price,
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
        const duration_minutes: u64 = @intCast(@divTrunc(duration_ms, 60000));

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

        try self.logger.info("Closed position: PnL={}, Return={d:.2}%", .{
            net_pnl,
            pnl_percent.toFloat() * 100,
        });

        // 7. Close position
        position_mgr.closePosition();
    }
};

// ============================================================================
// Tests (Will run integration tests from separate file)
// ============================================================================
