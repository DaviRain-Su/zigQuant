//! 存储模块共享类型
//!
//! 定义数据持久化模块使用的共享类型。

const std = @import("std");
const Decimal = @import("../core/decimal.zig").Decimal;

// ============================================================================
// K 线数据类型
// ============================================================================

/// 存储用 K 线数据
pub const StoredCandle = struct {
    /// 时间戳 (毫秒)
    timestamp: i64,
    /// 开盘价
    open: f64,
    /// 最高价
    high: f64,
    /// 最低价
    low: f64,
    /// 收盘价
    close: f64,
    /// 成交量
    volume: f64,

    /// 从 Decimal 类型的 Candle 转换
    pub fn fromCandle(candle: anytype) StoredCandle {
        return .{
            .timestamp = candle.timestamp,
            .open = candle.open.toFloat(),
            .high = candle.high.toFloat(),
            .low = candle.low.toFloat(),
            .close = candle.close.toFloat(),
            .volume = candle.volume.toFloat(),
        };
    }

    /// 转换为带 Decimal 的结构
    pub fn toDecimalCandle(self: StoredCandle) struct {
        timestamp: i64,
        open: Decimal,
        high: Decimal,
        low: Decimal,
        close: Decimal,
        volume: Decimal,
    } {
        return .{
            .timestamp = self.timestamp,
            .open = Decimal.fromFloat(self.open),
            .high = Decimal.fromFloat(self.high),
            .low = Decimal.fromFloat(self.low),
            .close = Decimal.fromFloat(self.close),
            .volume = Decimal.fromFloat(self.volume),
        };
    }
};

// ============================================================================
// 回测结果类型
// ============================================================================

/// 回测结果记录
pub const BacktestRecord = struct {
    /// 记录 ID
    id: i64 = 0,
    /// 策略名称
    strategy: []const u8,
    /// 交易对
    symbol: []const u8,
    /// 时间周期
    timeframe: []const u8,
    /// 开始时间
    start_time: i64,
    /// 结束时间
    end_time: i64,
    /// 总收益率
    total_return: f64,
    /// 夏普比率
    sharpe_ratio: f64,
    /// 最大回撤
    max_drawdown: f64,
    /// 总交易次数
    total_trades: i32,
    /// 胜率
    win_rate: f64,
    /// 参数 JSON
    params_json: ?[]const u8 = null,
    /// 创建时间
    created_at: i64 = 0,

    /// 释放分配的字符串
    pub fn deinit(self: *BacktestRecord, allocator: std.mem.Allocator) void {
        allocator.free(self.strategy);
        allocator.free(self.symbol);
        allocator.free(self.timeframe);
        if (self.params_json) |p| {
            allocator.free(p);
        }
    }
};

/// 交易记录
pub const TradeRecord = struct {
    /// 记录 ID
    id: i64 = 0,
    /// 回测 ID
    backtest_id: i64,
    /// 时间戳
    timestamp: i64,
    /// 买卖方向
    side: []const u8,
    /// 价格
    price: f64,
    /// 数量
    quantity: f64,
    /// 盈亏
    pnl: ?f64 = null,

    /// 释放分配的字符串
    pub fn deinit(self: *TradeRecord, allocator: std.mem.Allocator) void {
        allocator.free(self.side);
    }
};

// ============================================================================
// 数据库统计
// ============================================================================

/// 数据库统计信息
pub const DbStats = struct {
    /// K 线记录数
    candle_count: i64,
    /// 回测结果数
    result_count: i64,
    /// 交易记录数
    trade_count: i64,
    /// 数据库文件大小 (bytes)
    file_size: u64,
};

// ============================================================================
// 缓存条目
// ============================================================================

/// 缓存条目
pub const CacheEntry = struct {
    /// K 线数据
    candles: []StoredCandle,
    /// 最后访问时间
    last_access: i64,
    /// 是否已修改
    dirty: bool,
};

// ============================================================================
// 存储错误
// ============================================================================

/// 存储操作错误
pub const StorageError = error{
    /// 初始化失败
    InitFailed,
    /// 读取失败
    ReadFailed,
    /// 写入失败
    WriteFailed,
    /// 文件打开失败
    FileOpenFailed,
    /// 文件读取失败
    FileReadFailed,
    /// 文件写入失败
    FileWriteFailed,
    /// 数据解析失败
    ParseFailed,
    /// 记录不存在
    RecordNotFound,
    /// 索引已存在
    DuplicateKey,
    /// 内存不足
    OutOfMemory,
    /// 无效参数
    InvalidArgument,
    /// 数据库损坏
    DatabaseCorrupted,
};

// ============================================================================
// 时间周期
// ============================================================================

/// 时间周期字符串
pub const Timeframe = struct {
    pub const @"1s" = "1s";
    pub const @"1m" = "1m";
    pub const @"3m" = "3m";
    pub const @"5m" = "5m";
    pub const @"15m" = "15m";
    pub const @"30m" = "30m";
    pub const @"1h" = "1h";
    pub const @"2h" = "2h";
    pub const @"4h" = "4h";
    pub const @"6h" = "6h";
    pub const @"8h" = "8h";
    pub const @"12h" = "12h";
    pub const @"1d" = "1d";
    pub const @"3d" = "3d";
    pub const @"1w" = "1w";
    pub const @"1M" = "1M";

    /// 验证时间周期字符串
    pub fn isValid(tf: []const u8) bool {
        const valid = [_][]const u8{
            "1s", "1m", "3m", "5m", "15m", "30m",
            "1h", "2h", "4h", "6h", "8h", "12h",
            "1d", "3d", "1w", "1M",
        };
        for (valid) |v| {
            if (std.mem.eql(u8, tf, v)) return true;
        }
        return false;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "StoredCandle: conversion" {
    const candle = StoredCandle{
        .timestamp = 1000000,
        .open = 100.5,
        .high = 105.0,
        .low = 99.0,
        .close = 103.0,
        .volume = 1000.0,
    };

    const decimal_candle = candle.toDecimalCandle();
    try std.testing.expectEqual(@as(i64, 1000000), decimal_candle.timestamp);
    try std.testing.expect(decimal_candle.open.toFloat() > 100.0);
}

test "Timeframe: validation" {
    try std.testing.expect(Timeframe.isValid("1m"));
    try std.testing.expect(Timeframe.isValid("1h"));
    try std.testing.expect(Timeframe.isValid("1d"));
    try std.testing.expect(!Timeframe.isValid("2m"));
    try std.testing.expect(!Timeframe.isValid(""));
}

test "BacktestRecord: basic" {
    const allocator = std.testing.allocator;

    var record = BacktestRecord{
        .strategy = try allocator.dupe(u8, "dual_ma"),
        .symbol = try allocator.dupe(u8, "ETH"),
        .timeframe = try allocator.dupe(u8, "1h"),
        .start_time = 0,
        .end_time = 86400000,
        .total_return = 0.15,
        .sharpe_ratio = 2.5,
        .max_drawdown = 0.08,
        .total_trades = 42,
        .win_rate = 0.65,
    };
    defer record.deinit(allocator);

    try std.testing.expectEqualStrings("dual_ma", record.strategy);
    try std.testing.expectEqual(@as(f64, 0.15), record.total_return);
}
