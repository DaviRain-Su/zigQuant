# AlertSystem - API 参考

> 完整的 API 文档

**最后更新**: 2025-12-27

---

## 类型定义

```zig
pub const AlertLevel = enum(u8) {
    debug = 0,
    info = 1,
    warning = 2,
    critical = 3,
    emergency = 4,

    pub fn toString(self: AlertLevel) []const u8;
    pub fn emoji(self: AlertLevel) []const u8;
};

pub const AlertCategory = enum {
    risk_position_exceeded,
    risk_leverage_exceeded,
    risk_daily_loss,
    risk_drawdown,
    risk_kill_switch,
    trade_executed,
    trade_failed,
    trade_stop_loss,
    trade_take_profit,
    system_connected,
    system_disconnected,
    system_error,
    strategy_started,
    strategy_stopped,
    strategy_signal,
};

pub const ChannelType = enum {
    console,
    telegram,
    email,
    webhook,
    slack,
    discord,
};
```

---

## 函数

### `sendAlert`
发送自定义告警

### `info` / `warning` / `critical`
快捷告警方法

### `riskAlert`
发送风险相关告警

### `addChannel`
添加告警通道

### `getStats`
获取告警统计

---

## 返回类型

```zig
pub const AlertStats = struct {
    total_alerts: u64,
    by_debug: u64,
    by_info: u64,
    by_warning: u64,
    by_critical: u64,
    by_emergency: u64,
    history_size: usize,
};
```
