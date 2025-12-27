//! Trading 模块
//!
//! 提供交易相关功能:
//! - Paper Trading (模拟交易)
//! - 模拟账户和执行器
//! - 策略热重载
//!
//! ## 模块结构
//! - paper_trading: Paper Trading 引擎
//! - simulated_account: 模拟账户 (余额、仓位、PnL)
//! - simulated_executor: 模拟订单执行器
//! - hot_reload: 策略热重载管理器
//!
//! ## 使用示例
//! ```zig
//! const trading = @import("trading/mod.zig");
//!
//! var engine = trading.PaperTradingEngine.init(allocator, .{
//!     .initial_balance = Decimal.fromInt(10000),
//! });
//! defer engine.deinit();
//!
//! engine.start();
//! _ = try engine.buy("ETH", Decimal.fromFloat(0.1), Decimal.fromInt(2000));
//! engine.stop();
//! ```

pub const paper_trading = @import("paper_trading.zig");
pub const simulated_account = @import("simulated_account.zig");
pub const simulated_executor = @import("simulated_executor.zig");
pub const hot_reload = @import("hot_reload.zig");

// 重新导出主要类型 - Paper Trading
pub const PaperTradingEngine = paper_trading.PaperTradingEngine;
pub const PaperTradingConfig = paper_trading.PaperTradingConfig;
pub const SimulatedAccount = simulated_account.SimulatedAccount;
pub const SimulatedExecutor = simulated_executor.SimulatedExecutor;
pub const SimulatedExecutorConfig = simulated_executor.SimulatedExecutorConfig;
pub const Position = simulated_account.Position;
pub const Trade = simulated_account.Trade;
pub const OrderFill = simulated_account.OrderFill;
pub const Stats = simulated_account.Stats;

// 重新导出主要类型 - Hot Reload
pub const HotReloadManager = hot_reload.HotReloadManager;
pub const HotReloadManagerConfig = hot_reload.HotReloadManagerConfig;
pub const HotReloadConfig = hot_reload.HotReloadConfig;
pub const ConfigParam = hot_reload.ConfigParam;
pub const RiskConfig = hot_reload.RiskConfig;
pub const IHotReloadable = hot_reload.IHotReloadable;
pub const ParamValidator = hot_reload.ParamValidator;
pub const SafeReloadScheduler = hot_reload.SafeReloadScheduler;

// 测试
test {
    @import("std").testing.refAllDecls(@This());
}
