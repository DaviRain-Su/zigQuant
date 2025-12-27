//! Hyperliquid 适配器模块
//!
//! 提供 Hyperliquid 交易所的数据提供者和执行客户端实现。
//!
//! ## 模块结构
//! - data_provider: 实现 IDataProvider 接口，用于市场数据订阅
//! - (TODO) execution_client: 实现 IExecutionClient 接口，用于订单执行
//!
//! ## 使用示例
//! ```zig
//! const hl = @import("adapters/hyperliquid/mod.zig");
//!
//! var provider = hl.HyperliquidDataProvider.init(allocator, .{}, logger);
//! defer provider.deinit();
//!
//! // 作为 IDataProvider 使用
//! const data_provider = provider.asProvider();
//! try data_provider.connect();
//! try data_provider.subscribe(.{ .symbol = "ETH", .sub_type = .orderbook });
//! ```

pub const data_provider = @import("data_provider.zig");

// 重新导出主要类型
pub const HyperliquidDataProvider = data_provider.HyperliquidDataProvider;

// 测试
test {
    @import("std").testing.refAllDecls(@This());
}
