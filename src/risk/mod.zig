//! Risk Management Module (v0.8.0)
//!
//! Provides comprehensive risk management capabilities:
//! - RiskEngine: Pre-trade risk checks and Kill Switch
//! - StopLossManager: Automated stop loss / take profit management
//! - MoneyManager: Position sizing strategies (Kelly, Fixed Fraction, etc.)
//! - RiskMetricsMonitor: Real-time risk metrics (VaR, Sharpe, Drawdown)
//! - AlertManager: Multi-channel alert system

const std = @import("std");

// Core risk modules
pub const risk_engine = @import("risk_engine.zig");
pub const stop_loss = @import("stop_loss.zig");
pub const money_manager = @import("money_manager.zig");
pub const metrics = @import("metrics.zig");
pub const alert = @import("alert.zig");

// Re-export main types
pub const RiskEngine = risk_engine.RiskEngine;
pub const RiskConfig = risk_engine.RiskConfig;
pub const RiskCheckResult = risk_engine.RiskCheckResult;
pub const RiskRejectReason = risk_engine.RiskRejectReason;
pub const RiskCheckDetails = risk_engine.RiskCheckDetails;
pub const RiskEngineStats = risk_engine.RiskEngineStats;

pub const StopLossManager = stop_loss.StopLossManager;
pub const StopConfig = stop_loss.StopConfig;
pub const StopType = stop_loss.StopType;
pub const TimeStopAction = stop_loss.TimeStopAction;
pub const StopTrigger = stop_loss.StopTrigger;
pub const StopLossStats = stop_loss.StopLossStats;

pub const MoneyManager = money_manager.MoneyManager;
pub const MoneyManagementConfig = money_manager.MoneyManagementConfig;
pub const MoneyManagementMethod = money_manager.MoneyManagementMethod;
pub const KellyResult = money_manager.KellyResult;
pub const FixedFractionResult = money_manager.FixedFractionResult;
pub const RiskParityResult = money_manager.RiskParityResult;
pub const AntiMartingaleResult = money_manager.AntiMartingaleResult;
pub const PositionContext = money_manager.PositionContext;
pub const PositionRecommendation = money_manager.PositionRecommendation;
pub const TradeResult = money_manager.TradeResult;
pub const MoneyManagerStats = money_manager.MoneyManagerStats;

pub const RiskMetricsMonitor = metrics.RiskMetricsMonitor;
pub const RiskMetricsConfig = metrics.RiskMetricsConfig;
pub const EquitySnapshot = metrics.EquitySnapshot;
pub const VaRResult = metrics.VaRResult;
pub const CVaRResult = metrics.CVaRResult;
pub const DrawdownResult = metrics.DrawdownResult;
pub const SharpeResult = metrics.SharpeResult;
pub const SortinoResult = metrics.SortinoResult;
pub const CalmarResult = metrics.CalmarResult;
pub const RiskMetricsReport = metrics.RiskMetricsReport;

pub const AlertManager = alert.AlertManager;
pub const AlertConfig = alert.AlertConfig;
pub const Alert = alert.Alert;
pub const AlertLevel = alert.AlertLevel;
pub const AlertCategory = alert.AlertCategory;
pub const ChannelType = alert.ChannelType;
pub const AlertDetails = alert.AlertDetails;
pub const AlertStats = alert.AlertStats;
pub const IAlertChannel = alert.IAlertChannel;
pub const ConsoleChannel = alert.ConsoleChannel;

test {
    std.testing.refAllDecls(@This());
    _ = risk_engine;
    _ = stop_loss;
    _ = money_manager;
    _ = metrics;
    _ = alert;
}
