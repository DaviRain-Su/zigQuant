//! Hyperliquid 适配器模块
//!
//! 提供 Hyperliquid 交易所的数据提供者和执行客户端实现。
//!
//! ## 模块结构
//! - data_provider: 实现 IDataProvider 接口，用于市场数据订阅
//! - execution_client: 实现 IExecutionClient 接口，用于订单执行
//!
//! ## 使用示例
//! ```zig
//! const hl = @import("adapters/hyperliquid/mod.zig");
//!
//! // 数据提供者
//! var provider = hl.HyperliquidDataProvider.init(allocator, .{}, logger);
//! defer provider.deinit();
//! const data_provider = provider.asProvider();
//!
//! // 执行客户端
//! var exec = try hl.HyperliquidExecutionClient.init(allocator, .{
//!     .testnet = true,
//!     .private_key = pk,
//! }, logger, null);
//! defer exec.deinit();
//! const exec_client = exec.asClient();
//! ```

pub const data_provider = @import("data_provider.zig");
pub const execution_client = @import("execution_client.zig");

// 重新导出主要类型
pub const HyperliquidDataProvider = data_provider.HyperliquidDataProvider;
pub const HyperliquidExecutionClient = execution_client.HyperliquidExecutionClient;

// 测试
test {
    @import("std").testing.refAllDecls(@This());
}
