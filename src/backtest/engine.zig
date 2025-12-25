//! Backtest Engine - Core Engine
//!
//! Main backtesting orchestrator using event-driven simulation.

const std = @import("std");
const Decimal = @import("../core/decimal.zig").Decimal;
const Timestamp = @import("../core/time.zig").Timestamp;
const Logger = @import("../core/logger.zig").Logger;
const Candle = @import("../market/candles.zig").Candle;
const Candles = @import("../market/candles.zig").Candles;
const IStrategy = @import("../strategy/interface.zig").IStrategy;
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
        self.logger.info("Starting backtest: {s} on {s}/{s}", .{
            strategy.getName(),
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

        self.logger.info("Loaded {} candles", .{candles.candles.len});

        // 3. Populate indicators
        try strategy.populateIndicators(&candles);
        self.logger.info("Indicators calculated", .{});

        // 4. Initialize backtest state
        var account = Account.init(config.initial_capital);
        var position_mgr = PositionManager.init(self.allocator);
        var executor = OrderExecutor.init(self.allocator, self.logger, config);

        var trades = std.ArrayList(Trade).init(self.allocator);
        defer trades.deinit();

        var equity_curve = try std.ArrayList(EquitySnapshot).initCapacity(
            self.allocator,
            candles.candles.len,
        );
        defer equity_curve.deinit();

        // 5. Run event loop
        self.logger.info("Starting simulation...", .{});

        for (candles.candles, 0..) |candle, i| {
            // 5.1 Update position unrealized P&L
            if (position_mgr.getPosition()) |pos| {
                try pos.updateUnrealizedPnL(candle.close);
                try account.updateEquity(pos.unrealized_pnl);
            } else {
                try account.updateEquity(Decimal.ZERO);
            }

            // 5.2 Record equity snapshot
            equity_curve.appendAssumeCapacity(EquitySnapshot{
                .timestamp = candle.timestamp,
                .equity = account.equity,
                .balance = account.balance,
                .unrealized_pnl = if (position_mgr.getPosition()) |pos|
                    pos.unrealized_pnl
                else
                    Decimal.ZERO,
            });

            // 5.3 Check exit signals (if in position)
            if (position_mgr.hasPosition()) {
                const exit_signal = try strategy.generateExitSignal(&candles, i);
                if (exit_signal) |sig| {
                    if (sig.signal_type != .hold) {
                        try self.handleExit(
                            &executor,
                            &position_mgr,
                            &account,
                            &trades,
                            sig,
                            candle,
                        );
                        continue; // Skip entry check after exit
                    }
                }
            }

            // 5.4 Check entry signals (if no position)
            if (!position_mgr.hasPosition()) {
                const entry_signal = try strategy.generateEntrySignal(&candles, i);
                if (entry_signal) |sig| {
                    if (sig.signal_type == .entry_long or sig.signal_type == .entry_short) {
                        try self.handleEntry(
                            &executor,
                            &position_mgr,
                            &account,
                            strategy,
                            sig,
                            candle,
                        );
                    }
                }
            }

            // 5.5 Progress logging
            if (i > 0 and i % 1000 == 0) {
                self.logger.debug("Progress: {}/{} candles", .{ i, candles.candles.len });
            }
        }

        // 6. Force close remaining positions
        if (position_mgr.getPosition()) |pos| {
            const last_candle = candles.candles[candles.candles.len - 1];
            const force_exit_signal = Signal{
                .timestamp = last_candle.timestamp,
                .pair = config.pair,
                .signal_type = if (pos.side == .long) .exit_long else .exit_short,
                .side = pos.side,
                .price = last_candle.close,
                .strength = Decimal.fromFloat(1.0),
                .metadata = .{},
            };

            try self.handleExit(
                &executor,
                &position_mgr,
                &account,
                &trades,
                force_exit_signal,
                last_candle,
            );

            self.logger.warn("Force closed remaining position", .{});
        }

        // 7. Generate results
        self.logger.info("Backtest complete: {} trades", .{trades.items.len});

        var result = BacktestResult.init(
            self.allocator,
            config,
            strategy.getName(),
        );

        result.trades = try trades.toOwnedSlice();
        result.equity_curve = try equity_curve.toOwnedSlice();

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
        // 1. Calculate position size
        const position_size = try strategy.calculatePositionSize(signal, account.*);

        // Verify sufficient funds
        const entry_cost = candle.close.mul(position_size);
        if (!account.hasSufficientFunds(entry_cost)) {
            self.logger.warn("Insufficient funds for entry", .{});
            return;
        }

        // 2. Create market order
        const order_side = switch (signal.signal_type) {
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
        const total_cost = try cost.add(fill.commission);
        account.balance = try account.balance.sub(total_cost);
        account.total_commission = try account.total_commission.add(fill.commission);

        // 5. Open position
        const pos_side = if (signal.signal_type == .entry_long) PositionSide.long else PositionSide.short;
        const position = Position.init(
            signal.pair,
            pos_side,
            fill.fill_size,
            fill.fill_price,
            signal.timestamp,
        );
        try position_mgr.openPosition(position);

        self.logger.info("Opened {s} position: {} @ {}", .{
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
        const net_pnl = try pnl.sub(fill.commission);

        // 4. Update account
        const proceeds = fill.fill_price.mul(fill.fill_size);
        account.balance = try account.balance.add(proceeds);
        account.balance = try account.balance.add(net_pnl);
        account.total_commission = try account.total_commission.add(fill.commission);

        // 5. Calculate trade metrics
        const duration_ms = signal.timestamp.millis - position.entry_time.millis;
        const duration_minutes: u64 = @intCast(@divTrunc(duration_ms, 60000));

        const entry_cost = position.entry_price.mul(position.size);
        const pnl_percent = try net_pnl.div(entry_cost);

        // 6. Record trade
        try trades.append(Trade{
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

        self.logger.info("Closed position: PnL={}, Return={d:.2}%", .{
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
