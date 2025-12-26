//! Backtest Result Export Example (v0.4.0)
//!
//! 此示例展示如何导出和加载回测结果。
//!
//! 功能：
//! 1. 导出回测结果到 JSON 格式
//! 2. 导出回测结果到 CSV 格式
//! 3. 从文件加载历史回测结果
//! 4. 比较多个回测结果
//!
//! 运行：
//!   zig build run-example-export

const std = @import("std");
const zigQuant = @import("zigQuant");

pub fn main() !void {
    

    std.debug.print("\n", .{});
    std.debug.print("╔════════════════════════════════════════════════════════════╗\n", .{});
    std.debug.print("║       zigQuant v0.4.0 - Backtest Result Export             ║\n", .{});
    std.debug.print("╚════════════════════════════════════════════════════════════╝\n", .{});
    std.debug.print("\n", .{});

    // ═══════════════════════════════════════════════════════════
    // 1. 导出格式介绍
    // ═══════════════════════════════════════════════════════════
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
    std.debug.print("1. 支持的导出格式\n", .{});
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("   JSON 格式:\n", .{});
    std.debug.print("     - 完整保留所有数据结构\n", .{});
    std.debug.print("     - 支持嵌套对象 (交易记录、权益曲线)\n", .{});
    std.debug.print("     - 可用于 Web 可视化\n", .{});
    std.debug.print("     - 文件扩展名: .json\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("   CSV 格式:\n", .{});
    std.debug.print("     - 表格化数据，易于 Excel 分析\n", .{});
    std.debug.print("     - 分离导出: 摘要、交易、权益曲线\n", .{});
    std.debug.print("     - 适合数据分析和报表\n", .{});
    std.debug.print("     - 文件扩展名: .csv\n", .{});
    std.debug.print("\n", .{});

    // ═══════════════════════════════════════════════════════════
    // 2. JSON 导出示例
    // ═══════════════════════════════════════════════════════════
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
    std.debug.print("2. JSON 导出示例\n", .{});
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("   代码示例:\n", .{});
    std.debug.print("   ```zig\n", .{});
    std.debug.print("   const json_exporter = zigQuant.backtest_json_exporter;\n", .{});
    std.debug.print("   \n", .{});
    std.debug.print("   // 导出完整结果\n", .{});
    std.debug.print("   try json_exporter.exportToFile(\n", .{});
    std.debug.print("       allocator,\n", .{});
    std.debug.print("       backtest_result,\n", .{});
    std.debug.print("       \"results/backtest_2024.json\",\n", .{});
    std.debug.print("   );\n", .{});
    std.debug.print("   ```\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("   输出 JSON 结构:\n", .{});
    std.debug.print("   ```json\n", .{});
    std.debug.print("   {{\n", .{});
    std.debug.print("     \"strategy_name\": \"DualMA\",\n", .{});
    std.debug.print("     \"config\": {{\n", .{});
    std.debug.print("       \"pair\": \"BTC/USDT\",\n", .{});
    std.debug.print("       \"timeframe\": \"1h\",\n", .{});
    std.debug.print("       \"initial_capital\": 10000.0\n", .{});
    std.debug.print("     }},\n", .{});
    std.debug.print("     \"metrics\": {{\n", .{});
    std.debug.print("       \"net_profit\": 2500.50,\n", .{});
    std.debug.print("       \"total_return\": 0.25,\n", .{});
    std.debug.print("       \"sharpe_ratio\": 1.85,\n", .{});
    std.debug.print("       \"max_drawdown\": 0.12,\n", .{});
    std.debug.print("       \"win_rate\": 0.58,\n", .{});
    std.debug.print("       \"profit_factor\": 1.65\n", .{});
    std.debug.print("     }},\n", .{});
    std.debug.print("     \"trades\": [...],\n", .{});
    std.debug.print("     \"equity_curve\": [...]\n", .{});
    std.debug.print("   }}\n", .{});
    std.debug.print("   ```\n", .{});
    std.debug.print("\n", .{});

    // ═══════════════════════════════════════════════════════════
    // 3. CSV 导出示例
    // ═══════════════════════════════════════════════════════════
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
    std.debug.print("3. CSV 导出示例\n", .{});
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("   代码示例:\n", .{});
    std.debug.print("   ```zig\n", .{});
    std.debug.print("   const csv_exporter = zigQuant.backtest_csv_exporter;\n", .{});
    std.debug.print("   \n", .{});
    std.debug.print("   // 导出交易记录\n", .{});
    std.debug.print("   try csv_exporter.exportTrades(\n", .{});
    std.debug.print("       allocator,\n", .{});
    std.debug.print("       backtest_result.trades,\n", .{});
    std.debug.print("       \"results/trades.csv\",\n", .{});
    std.debug.print("   );\n", .{});
    std.debug.print("   \n", .{});
    std.debug.print("   // 导出权益曲线\n", .{});
    std.debug.print("   try csv_exporter.exportEquityCurve(\n", .{});
    std.debug.print("       allocator,\n", .{});
    std.debug.print("       backtest_result.equity_curve,\n", .{});
    std.debug.print("       \"results/equity.csv\",\n", .{});
    std.debug.print("   );\n", .{});
    std.debug.print("   ```\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("   交易记录 CSV 格式:\n", .{});
    std.debug.print("   ```\n", .{});
    std.debug.print("   id,entry_time,exit_time,side,entry_price,exit_price,quantity,pnl,return_pct\n", .{});
    std.debug.print("   1,2024-01-15 10:00,2024-01-15 14:30,long,42500.00,43200.00,0.5,350.00,1.65%\n", .{});
    std.debug.print("   2,2024-01-16 09:15,2024-01-16 16:00,short,43500.00,43100.00,0.5,200.00,0.92%\n", .{});
    std.debug.print("   ```\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("   权益曲线 CSV 格式:\n", .{});
    std.debug.print("   ```\n", .{});
    std.debug.print("   timestamp,equity,drawdown,position\n", .{});
    std.debug.print("   2024-01-15 00:00,10000.00,0.00,0\n", .{});
    std.debug.print("   2024-01-15 10:00,10000.00,0.00,1\n", .{});
    std.debug.print("   2024-01-15 14:30,10350.00,0.00,0\n", .{});
    std.debug.print("   ```\n", .{});
    std.debug.print("\n", .{});

    // ═══════════════════════════════════════════════════════════
    // 4. 加载历史结果
    // ═══════════════════════════════════════════════════════════
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
    std.debug.print("4. 加载历史结果\n", .{});
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("   代码示例:\n", .{});
    std.debug.print("   ```zig\n", .{});
    std.debug.print("   const result_loader = zigQuant.backtest_result_loader;\n", .{});
    std.debug.print("   \n", .{});
    std.debug.print("   // 从 JSON 加载\n", .{});
    std.debug.print("   const result = try result_loader.loadFromJson(\n", .{});
    std.debug.print("       allocator,\n", .{});
    std.debug.print("       \"results/backtest_2024.json\",\n", .{});
    std.debug.print("   );\n", .{});
    std.debug.print("   defer result.deinit();\n", .{});
    std.debug.print("   \n", .{});
    std.debug.print("   // 使用加载的结果\n", .{});
    std.debug.print("   std.debug.print(\"Net Profit: {{}}\", .{{result.net_profit}});\n", .{});
    std.debug.print("   ```\n", .{});
    std.debug.print("\n", .{});

    // ═══════════════════════════════════════════════════════════
    // 5. 结果比较
    // ═══════════════════════════════════════════════════════════
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
    std.debug.print("5. 多策略结果比较\n", .{});
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
    std.debug.print("\n", .{});

    // 模拟比较多个策略
    const strategies = [_]struct {
        name: []const u8,
        net_profit: f64,
        sharpe: f64,
        max_dd: f64,
        win_rate: f64,
    }{
        .{ .name = "DualMA", .net_profit = 2500.50, .sharpe = 1.85, .max_dd = 12.5, .win_rate = 58.0 },
        .{ .name = "RSI_MR", .net_profit = 1800.25, .sharpe = 1.42, .max_dd = 15.2, .win_rate = 52.0 },
        .{ .name = "BB_BO", .net_profit = 3200.00, .sharpe = 2.10, .max_dd = 18.5, .win_rate = 45.0 },
        .{ .name = "MACD_Div", .net_profit = 2100.75, .sharpe = 1.65, .max_dd = 10.8, .win_rate = 55.0 },
    };

    std.debug.print("   ┌────────────┬────────────┬─────────┬─────────┬──────────┐\n", .{});
    std.debug.print("   │ Strategy   │ Net Profit │  Sharpe │ Max DD  │ Win Rate │\n", .{});
    std.debug.print("   ├────────────┼────────────┼─────────┼─────────┼──────────┤\n", .{});

    for (strategies) |s| {
        std.debug.print("   │ {s: <10} │ ${d: >9.2} │  {d: >5.2}  │ {d: >5.1}%  │  {d: >5.1}%  │\n", .{ s.name, s.net_profit, s.sharpe, s.max_dd, s.win_rate });
    }

    std.debug.print("   └────────────┴────────────┴─────────┴─────────┴──────────┘\n", .{});
    std.debug.print("\n", .{});

    std.debug.print("   比较代码示例:\n", .{});
    std.debug.print("   ```zig\n", .{});
    std.debug.print("   const export = zigQuant.backtest_export;\n", .{});
    std.debug.print("   \n", .{});
    std.debug.print("   // 加载多个结果\n", .{});
    std.debug.print("   const results = [_]*BacktestResult{{\n", .{});
    std.debug.print("       &dual_ma_result,\n", .{});
    std.debug.print("       &rsi_mr_result,\n", .{});
    std.debug.print("       &bb_bo_result,\n", .{});
    std.debug.print("   }};\n", .{});
    std.debug.print("   \n", .{});
    std.debug.print("   // 导出比较报告\n", .{});
    std.debug.print("   try export.exportComparison(\n", .{});
    std.debug.print("       allocator,\n", .{});
    std.debug.print("       &results,\n", .{});
    std.debug.print("       \"results/comparison.csv\",\n", .{});
    std.debug.print("   );\n", .{});
    std.debug.print("   ```\n", .{});
    std.debug.print("\n", .{});

    // ═══════════════════════════════════════════════════════════
    // 6. 目录结构建议
    // ═══════════════════════════════════════════════════════════
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
    std.debug.print("6. 推荐目录结构\n", .{});
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("   results/\n", .{});
    std.debug.print("   ├── backtests/\n", .{});
    std.debug.print("   │   ├── dual_ma_2024-01.json\n", .{});
    std.debug.print("   │   ├── dual_ma_2024-02.json\n", .{});
    std.debug.print("   │   └── ...\n", .{});
    std.debug.print("   ├── optimizations/\n", .{});
    std.debug.print("   │   ├── grid_search_2024-01.json\n", .{});
    std.debug.print("   │   └── walk_forward_2024-01.json\n", .{});
    std.debug.print("   ├── trades/\n", .{});
    std.debug.print("   │   ├── trades_2024-01.csv\n", .{});
    std.debug.print("   │   └── ...\n", .{});
    std.debug.print("   └── reports/\n", .{});
    std.debug.print("       ├── monthly_summary.csv\n", .{});
    std.debug.print("       └── strategy_comparison.csv\n", .{});
    std.debug.print("\n", .{});

    // ═══════════════════════════════════════════════════════════
    // 总结
    // ═══════════════════════════════════════════════════════════
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
    std.debug.print("总结\n", .{});
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("   导出功能用途:\n", .{});
    std.debug.print("     1. 持久化回测结果，避免重复计算\n", .{});
    std.debug.print("     2. 使用外部工具分析 (Excel, Python, R)\n", .{});
    std.debug.print("     3. 生成可视化报表\n", .{});
    std.debug.print("     4. 历史结果对比和趋势分析\n", .{});
    std.debug.print("     5. 团队协作和结果共享\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("   格式选择建议:\n", .{});
    std.debug.print("     - JSON: 完整性要求高，需要程序化处理\n", .{});
    std.debug.print("     - CSV:  需要 Excel 分析，生成报表\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("╔════════════════════════════════════════════════════════════╗\n", .{});
    std.debug.print("║                    示例运行完成                             ║\n", .{});
    std.debug.print("╚════════════════════════════════════════════════════════════╝\n", .{});
    std.debug.print("\n", .{});
}
