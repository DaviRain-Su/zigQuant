//! 交易所适配器模块
//!
//! 提供各交易所的数据提供者和执行客户端实现。
//! 所有适配器都实现标准的 IDataProvider 和 IExecutionClient 接口。
//!
//! ## 支持的交易所
//! - hyperliquid: Hyperliquid 去中心化永续合约交易所
//! - (TODO) binance: 币安交易所
//! - (TODO) okx: OKX 交易所
//!
//! ## 架构
//! 每个交易所适配器包含:
//! - DataProvider: 实现 IDataProvider，用于市场数据订阅
//! - ExecutionClient: 实现 IExecutionClient，用于订单执行
//!
//! ## 使用示例
//! ```zig
//! const adapters = @import("adapters/mod.zig");
//!
//! // 创建 Hyperliquid 数据提供者
//! var provider = adapters.HyperliquidDataProvider.init(allocator, .{}, logger);
//! defer provider.deinit();
//!
//! // 添加到 DataEngine
//! try engine.addProvider(provider.asProvider());
//! ```

pub const hyperliquid = @import("hyperliquid/mod.zig");

// 重新导出主要类型
pub const HyperliquidDataProvider = hyperliquid.HyperliquidDataProvider;

// 测试
test {
    @import("std").testing.refAllDecls(@This());
}
