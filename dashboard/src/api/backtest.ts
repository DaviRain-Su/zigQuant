import api from './index'

export interface BacktestConfig {
  strategy_id: string
  symbol: string
  timeframe: string
  start_date: string
  end_date: string
  initial_capital: number
  parameters?: Record<string, unknown>
}

export interface BacktestResult {
  id: string
  strategy_id: string
  status: 'pending' | 'running' | 'completed' | 'failed'
  metrics?: BacktestMetrics
  equity_curve?: EquityPoint[]
  trades?: Trade[]
}

export interface BacktestMetrics {
  total_return: number
  sharpe_ratio: number
  max_drawdown: number
  win_rate: number
  profit_factor: number
  total_trades: number
  winning_trades: number
  losing_trades: number
}

export interface EquityPoint {
  timestamp: number
  equity: number
}

export interface Trade {
  id: string
  symbol: string
  side: 'buy' | 'sell'
  price: number
  quantity: number
  timestamp: number
  pnl?: number
}

export async function runBacktest(config: BacktestConfig): Promise<BacktestResult> {
  const response = await api.post('/backtest', config)
  return response.data
}

export async function getBacktestResult(id: string): Promise<BacktestResult> {
  const response = await api.get(`/backtest/${id}`)
  return response.data
}

export async function getBacktestTrades(id: string): Promise<Trade[]> {
  const response = await api.get(`/backtest/${id}/trades`)
  return response.data.trades
}

export async function getBacktestEquity(id: string): Promise<EquityPoint[]> {
  const response = await api.get(`/backtest/${id}/equity`)
  return response.data.equity_curve
}

export async function listBacktestResults(): Promise<BacktestResult[]> {
  const response = await api.get('/backtest/results')
  return response.data.results
}
