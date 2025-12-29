// ============================================================================
// API Types for zigQuant Dashboard
// Matches the Zig backend REST API responses
// ============================================================================

// ============================================================================
// Common Types
// ============================================================================

export interface ApiResponse<T> {
  success: boolean;
  data?: T;
  error?: ApiError;
}

export interface ApiError {
  code: string;
  message: string;
  details?: Record<string, unknown>;
}

// ============================================================================
// Health & System Types
// ============================================================================

export interface HealthStatus {
  status: 'healthy' | 'unhealthy';
  version: string;
  uptime: number;
  requests: number;
  timestamp: number;
}

export interface SystemHealth {
  status: string;
  components: {
    api_server: string;
    engine_manager: string;
  };
  metrics: {
    running_strategies: number;
    running_live: number;
    active_backtests: number;
    kill_switch_active: boolean;
    uptime_seconds: number;
  };
}

// ============================================================================
// Strategy Types
// ============================================================================

export type StrategyType = 
  | 'dual_ma' 
  | 'rsi_mean_reversion' 
  | 'bollinger_breakout' 
  | 'grid' 
  | 'hybrid_ai';

export type StrategyStatus = 
  | 'running' 
  | 'stopped' 
  | 'paused' 
  | 'error' 
  | 'starting' 
  | 'stopping';

export type TradingMode = 'paper' | 'live' | 'testnet';

export interface StrategySummary {
  id: string;
  strategy: StrategyType;
  symbol: string;
  status: StrategyStatus;
  mode: TradingMode;
  realized_pnl: number;
  current_position: number;
  total_signals: number;
  total_trades: number;
  win_rate: number;
  uptime_seconds: number;
}

export interface StrategyRequest {
  strategy: StrategyType;
  symbol: string;
  timeframe?: string;
  mode?: TradingMode;
  initial_capital?: number;
  check_interval_ms?: number;
  risk_enabled?: boolean;
  max_daily_loss_pct?: number;
  max_position_size?: number;
  // Grid specific
  upper_price?: number;
  lower_price?: number;
  grid_count?: number;
  order_size?: number;
  take_profit_pct?: number;
  // Hybrid AI specific
  ai_weight?: number;
  technical_weight?: number;
  params?: Record<string, unknown>;
}

export interface StrategyStats {
  total_signals: number;
  total_trades: number;
  realized_pnl: number;
  unrealized_pnl: number;
  current_position: number;
  win_rate: number;
  max_drawdown: number;
  sharpe_ratio: number;
  start_time: number;
  last_signal_time: number;
}

// ============================================================================
// Backtest Types
// ============================================================================

export type BacktestStatus = 
  | 'pending' 
  | 'running' 
  | 'completed' 
  | 'failed' 
  | 'cancelled';

export interface BacktestRequest {
  strategy: StrategyType;
  symbol: string;
  timeframe: string;
  start_date: string;
  end_date: string;
  initial_capital?: number;
  commission?: number;
  slippage?: number;
  data_file?: string;
  params?: string;  // Backend expects params as JSON string
}

export interface BacktestSummary {
  id: string;
  strategy: string;
  symbol: string;
  status: BacktestStatus;
  progress: number;
  trades_so_far: number;
  elapsed_seconds: number;
}

export interface BacktestResult {
  id: string;
  status: BacktestStatus;
  progress: number;
  total_trades: number;
  metrics?: BacktestMetrics;
  error?: string;
}

export interface BacktestMetrics {
  total_return: number;
  sharpe_ratio: number;
  max_drawdown: number;
  win_rate: number;
  profit_factor: number;
  total_trades: number;
  winning_trades: number;
  losing_trades: number;
  avg_trade_pnl: number;
  best_trade: number;
  worst_trade: number;
  net_profit?: number;
  total_commission?: number;
}

// Trade details for chart visualization
export interface BacktestTrade {
  id: number;
  side: 'long' | 'short';
  entry_time: number;
  exit_time: number;
  entry_price: number;
  exit_price: number;
  size: number;
  pnl: number;
  pnl_percent: number;
  commission: number;
}

// Equity snapshot for PnL chart
export interface EquitySnapshot {
  timestamp: number;
  equity: number;
  balance: number;
}

// Extended backtest result with trades and equity curve
export interface BacktestDetailedResult extends BacktestResult {
  trades?: BacktestTrade[];
  equity_curve?: EquitySnapshot[];
}

// ============================================================================
// Live Trading Types
// ============================================================================

export type LiveStatus = 
  | 'stopped' 
  | 'starting' 
  | 'running' 
  | 'paused' 
  | 'stopping' 
  | 'error';

export type LiveTradingMode = 'paper' | 'live' | 'hybrid';

export interface LiveRequest {
  session_id: string;
  strategy_type: StrategyType;
  exchange: string;
  symbol: string;
  mode?: LiveTradingMode;
  initial_capital?: number;
  params?: Record<string, unknown>;
}

export type ConnectionStatus = 'disconnected' | 'connecting' | 'connected' | 'reconnecting';

export interface LiveSummary {
  id: string;
  name: string;
  exchange: string;
  status: LiveStatus;
  connection_status: ConnectionStatus;
  testnet: boolean;
  // Strategy info (NEW)
  strategy: string;
  timeframe: string;
  leverage: number;
  symbols: string[];
  // Position info (NEW)
  current_position: number;
  entry_price: number;
  // Account balance (NEW)
  account_balance: number;
  available_balance: number;
  initial_capital: number;
  // Order stats
  orders_submitted: number;
  orders_filled: number;
  orders_cancelled: number;
  orders_rejected: number;
  total_volume: number;
  realized_pnl: number;
  unrealized_pnl: number;
  last_price: number;
  uptime_ms: number;
  ticks: number;
  reconnects: number;
}

export interface LiveStats {
  ticks_processed: number;
  orders_placed: number;
  orders_filled: number;
  current_pnl: number;
  start_time: number;
  uptime_seconds: number;
}

// ============================================================================
// AI Configuration Types
// ============================================================================

export type AIProvider = 
  | 'openai' 
  | 'anthropic' 
  | 'lmstudio' 
  | 'ollama' 
  | 'deepseek' 
  | 'custom';

export interface AIConfig {
  provider: string;
  model_id: string;
  api_endpoint?: string | null;
  api_key?: string;
}

export interface AIStatus {
  enabled: boolean;
  provider: string;
  model_id: string;
  api_endpoint: string | null;
  has_api_key: boolean;
  connected: boolean;
}

// ============================================================================
// Manager Stats Types
// ============================================================================

export interface ManagerStats {
  total_strategies: number;
  running_strategies: number;
  stopped_strategies: number;
  total_strategies_started: number;
  total_strategies_stopped: number;
  total_live: number;
  running_live: number;
  total_live_started: number;
  total_live_stopped: number;
  total_realized_pnl: number;
  total_trades: number;
}

export interface KillSwitchResult {
  strategies_stopped: number;
  live_stopped: number;
  orders_cancelled: number;
  positions_closed: number;
}

// ============================================================================
// Auth Types
// ============================================================================

export interface LoginRequest {
  username: string;
  password: string;
}

export interface AuthResponse {
  token: string;
  expires_at: number;
}

export interface UserInfo {
  user_id: string;
  username: string;
  role: string;
}

// ============================================================================
// Log Types
// ============================================================================

export type LogLevel = 'trace' | 'debug' | 'info' | 'warn' | 'error' | 'fatal';

export interface LogEntry {
  level: LogLevel;
  message: string;
  timestamp: number;
  source?: string;
  context?: string;
}

export interface LogsResponse {
  logs: LogEntry[];
  total: number;
  has_more: boolean;
  message?: string;
}

export interface LogsQuery {
  limit?: number;
  level?: LogLevel;
  since?: number;
}
