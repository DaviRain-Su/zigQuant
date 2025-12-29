// ============================================================================
// Backtest Results Component
// ============================================================================

import { useMemo } from 'react';
import { 
  X, 
  TrendingUp, 
  TrendingDown, 
  BarChart3,
  Target,
  Activity,
  Award,
  AlertTriangle,
  CheckCircle,
  XCircle,
  Loader2,
  ArrowUpCircle,
  ArrowDownCircle
} from 'lucide-react';
import { Card } from '../ui/Card';
import { Button } from '../ui/Button';
import { PnLChart } from '../charts/PnLChart';
import type { BacktestDetailedResult, BacktestTrade } from '../../types/api';
import { formatPercent, formatCurrency, cn } from '../../lib/utils';

interface BacktestResultsProps {
  result: BacktestDetailedResult;
  onClose: () => void;
}

// Metric Card Component
function MetricCard({ 
  label, 
  value, 
  icon: Icon, 
  color = 'gray',
  format = 'text'
}: { 
  label: string; 
  value: number | string; 
  icon: React.ElementType;
  color?: 'green' | 'red' | 'blue' | 'yellow' | 'gray';
  format?: 'percent' | 'currency' | 'number' | 'text';
}) {
  const colorClasses = {
    green: 'text-green-500 bg-green-500/10',
    red: 'text-red-500 bg-red-500/10',
    blue: 'text-blue-500 bg-blue-500/10',
    yellow: 'text-yellow-500 bg-yellow-500/10',
    gray: 'text-gray-400 bg-gray-700',
  };

  const formatValue = () => {
    if (typeof value === 'string') return value;
    switch (format) {
      case 'percent':
        return formatPercent(value);
      case 'currency':
        return formatCurrency(value);
      case 'number':
        return value.toLocaleString();
      default:
        return value.toString();
    }
  };

  return (
    <div className="p-4 bg-gray-800/50 rounded-lg">
      <div className="flex items-center gap-3">
        <div className={cn('p-2 rounded-lg', colorClasses[color])}>
          <Icon className="w-4 h-4" />
        </div>
        <div>
          <p className="text-xs text-gray-500 uppercase tracking-wider">{label}</p>
          <p className={cn('text-lg font-semibold', 
            color === 'green' ? 'text-green-500' : 
            color === 'red' ? 'text-red-500' : 
            'text-white'
          )}>
            {formatValue()}
          </p>
        </div>
      </div>
    </div>
  );
}

// Status Badge Component
function StatusBadge({ status }: { status: string }) {
  const config = {
    completed: { icon: CheckCircle, color: 'text-green-500 bg-green-500/10', label: 'Completed' },
    running: { icon: Loader2, color: 'text-blue-500 bg-blue-500/10', label: 'Running' },
    failed: { icon: XCircle, color: 'text-red-500 bg-red-500/10', label: 'Failed' },
    cancelled: { icon: AlertTriangle, color: 'text-yellow-500 bg-yellow-500/10', label: 'Cancelled' },
    pending: { icon: Activity, color: 'text-gray-400 bg-gray-700', label: 'Pending' },
  }[status] || { icon: Activity, color: 'text-gray-400 bg-gray-700', label: status };

  const Icon = config.icon;

  return (
    <div className={cn('flex items-center gap-2 px-3 py-1.5 rounded-full', config.color)}>
      <Icon className={cn('w-4 h-4', status === 'running' && 'animate-spin')} />
      <span className="text-sm font-medium">{config.label}</span>
    </div>
  );
}

// Trade List Item
function TradeListItem({ trade, index }: { trade: BacktestTrade; index: number }) {
  const isProfit = trade.pnl >= 0;
  const entryDate = new Date(trade.entry_time).toLocaleString();
  const exitDate = new Date(trade.exit_time).toLocaleString();
  
  return (
    <div className={cn(
      'flex items-center gap-4 p-3 rounded-lg border',
      isProfit ? 'bg-green-500/5 border-green-500/20' : 'bg-red-500/5 border-red-500/20'
    )}>
      <div className="flex items-center gap-2 w-16">
        {trade.side === 'long' ? (
          <ArrowUpCircle className="w-4 h-4 text-green-500" />
        ) : (
          <ArrowDownCircle className="w-4 h-4 text-red-500" />
        )}
        <span className="text-xs text-gray-400">#{index + 1}</span>
      </div>
      
      <div className="flex-1 grid grid-cols-4 gap-4 text-sm">
        <div>
          <p className="text-gray-500 text-xs">Entry</p>
          <p className="text-white">${trade.entry_price.toFixed(2)}</p>
          <p className="text-xs text-gray-500">{entryDate}</p>
        </div>
        <div>
          <p className="text-gray-500 text-xs">Exit</p>
          <p className="text-white">${trade.exit_price.toFixed(2)}</p>
          <p className="text-xs text-gray-500">{exitDate}</p>
        </div>
        <div>
          <p className="text-gray-500 text-xs">Size</p>
          <p className="text-white">{trade.size.toFixed(4)}</p>
        </div>
        <div className="text-right">
          <p className="text-gray-500 text-xs">PnL</p>
          <p className={isProfit ? 'text-green-500' : 'text-red-500'}>
            {isProfit ? '+' : ''}{formatCurrency(trade.pnl)}
          </p>
          <p className={cn('text-xs', isProfit ? 'text-green-400' : 'text-red-400')}>
            {isProfit ? '+' : ''}{(trade.pnl_percent * 100).toFixed(2)}%
          </p>
        </div>
      </div>
    </div>
  );
}

export function BacktestResults({ result, onClose }: BacktestResultsProps) {
  const metrics = result.metrics;
  const isComplete = result.status === 'completed';
  const hasFailed = result.status === 'failed';
  const trades = result.trades || [];
  const equityCurve = result.equity_curve || [];

  // Convert equity curve for PnL chart
  const pnlData = useMemo(() => {
    if (equityCurve.length === 0) return [];
    const initialEquity = equityCurve[0]?.equity || 0;
    return equityCurve.map(snapshot => ({
      timestamp: snapshot.timestamp,
      equity: snapshot.equity,
      balance: snapshot.balance,
      pnl: snapshot.equity - initialEquity,
      pnlPercent: initialEquity > 0 ? ((snapshot.equity - initialEquity) / initialEquity) * 100 : 0,
    }));
  }, [equityCurve]);

  // Determine overall performance color
  const getPerformanceColor = (value: number) => value >= 0 ? 'green' : 'red';

  return (
    <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-[100] p-4">
      <Card className="w-full max-w-6xl max-h-[95vh] overflow-y-auto">
        {/* Header */}
        <div className="flex items-center justify-between p-4 border-b border-gray-800 sticky top-0 bg-gray-900/95 backdrop-blur z-10">
          <div className="flex items-center gap-3">
            <div className="p-2 bg-blue-500/20 rounded-lg">
              <BarChart3 className="w-5 h-5 text-blue-500" />
            </div>
            <div>
              <h2 className="text-lg font-semibold text-white">Backtest Results</h2>
              <p className="text-sm text-gray-400 font-mono">{result.id}</p>
            </div>
          </div>
          <div className="flex items-center gap-3">
            <StatusBadge status={result.status} />
            <button
              onClick={onClose}
              className="p-2 hover:bg-gray-800 rounded-lg transition-colors"
            >
              <X className="w-5 h-5 text-gray-400" />
            </button>
          </div>
        </div>

        {/* Progress Bar (for running backtests) */}
        {result.status === 'running' && (
          <div className="px-4 pt-4">
            <div className="flex items-center justify-between text-sm mb-2">
              <span className="text-gray-400">Progress</span>
              <span className="text-white font-medium">{Math.round(result.progress * 100)}%</span>
            </div>
            <div className="w-full h-2 bg-gray-700 rounded-full overflow-hidden">
              <div 
                className="h-full bg-blue-500 transition-all duration-300" 
                style={{ width: `${result.progress * 100}%` }}
              />
            </div>
          </div>
        )}

        {/* Error Message */}
        {hasFailed && result.error && (
          <div className="m-4 p-4 bg-red-500/10 border border-red-500/30 rounded-lg">
            <div className="flex items-center gap-2 text-red-500">
              <XCircle className="w-5 h-5" />
              <span className="font-medium">Backtest Failed</span>
            </div>
            <p className="mt-2 text-sm text-red-400">{result.error}</p>
          </div>
        )}

        {/* Metrics Section */}
        {metrics && (
          <div className="p-4 space-y-6">
            {/* Key Metrics */}
            <div>
              <h3 className="text-sm font-medium text-gray-400 uppercase tracking-wider mb-3">
                Performance Summary
              </h3>
              <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
                <MetricCard
                  label="Total Return"
                  value={metrics.total_return}
                  icon={metrics.total_return >= 0 ? TrendingUp : TrendingDown}
                  color={getPerformanceColor(metrics.total_return)}
                  format="percent"
                />
                <MetricCard
                  label="Sharpe Ratio"
                  value={metrics.sharpe_ratio.toFixed(2)}
                  icon={Award}
                  color={metrics.sharpe_ratio >= 1 ? 'green' : metrics.sharpe_ratio >= 0 ? 'yellow' : 'red'}
                />
                <MetricCard
                  label="Max Drawdown"
                  value={metrics.max_drawdown}
                  icon={TrendingDown}
                  color="red"
                  format="percent"
                />
                <MetricCard
                  label="Win Rate"
                  value={metrics.win_rate}
                  icon={Target}
                  color={metrics.win_rate >= 0.5 ? 'green' : 'yellow'}
                  format="percent"
                />
              </div>
            </div>

            {/* Trade Statistics */}
            <div>
              <h3 className="text-sm font-medium text-gray-400 uppercase tracking-wider mb-3">
                Trade Statistics
              </h3>
              <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
                <MetricCard
                  label="Total Trades"
                  value={metrics.total_trades}
                  icon={Activity}
                  format="number"
                />
                <MetricCard
                  label="Winning Trades"
                  value={metrics.winning_trades}
                  icon={CheckCircle}
                  color="green"
                  format="number"
                />
                <MetricCard
                  label="Losing Trades"
                  value={metrics.losing_trades}
                  icon={XCircle}
                  color="red"
                  format="number"
                />
                <MetricCard
                  label="Profit Factor"
                  value={metrics.profit_factor.toFixed(2)}
                  icon={BarChart3}
                  color={metrics.profit_factor >= 1 ? 'green' : 'red'}
                />
              </div>
            </div>

            {/* Equity Curve / PnL Chart */}
            {pnlData.length > 0 && (
              <div>
                <h3 className="text-sm font-medium text-gray-400 uppercase tracking-wider mb-3">
                  Equity Curve
                </h3>
                <div className="bg-gray-800/50 rounded-lg p-4">
                  <PnLChart data={pnlData} height={300} />
                </div>
              </div>
            )}

            {/* Trade History with Visual Markers */}
            {trades.length > 0 && (
              <div>
                <h3 className="text-sm font-medium text-gray-400 uppercase tracking-wider mb-3">
                  Trade History ({trades.length} trades)
                </h3>
                <div className="space-y-2 max-h-80 overflow-y-auto">
                  {trades.slice(0, 50).map((trade, index) => (
                    <TradeListItem key={trade.id} trade={trade} index={index} />
                  ))}
                  {trades.length > 50 && (
                    <p className="text-center text-gray-500 text-sm py-2">
                      Showing first 50 trades of {trades.length} total
                    </p>
                  )}
                </div>
              </div>
            )}

            {/* Empty state for equity curve */}
            {pnlData.length === 0 && trades.length === 0 && (
              <div>
                <h3 className="text-sm font-medium text-gray-400 uppercase tracking-wider mb-3">
                  Equity Curve
                </h3>
                <div className="h-64 bg-gray-800/50 rounded-lg flex items-center justify-center">
                  <div className="text-center text-gray-500">
                    <BarChart3 className="w-8 h-8 mx-auto mb-2 opacity-50" />
                    <p>No detailed trade data available</p>
                    <p className="text-xs mt-1">Run a new backtest to see the equity curve</p>
                  </div>
                </div>
              </div>
            )}
          </div>
        )}

        {/* Loading State */}
        {!metrics && result.status === 'running' && (
          <div className="p-8 flex flex-col items-center justify-center">
            <Loader2 className="w-8 h-8 text-blue-500 animate-spin mb-4" />
            <p className="text-gray-400">Running backtest...</p>
            <p className="text-sm text-gray-500 mt-1">
              {result.total_trades} trades processed
            </p>
          </div>
        )}

        {/* Footer */}
        <div className="flex items-center justify-end gap-3 p-4 border-t border-gray-800">
          {isComplete && (
            <Button variant="secondary">
              Export Results
            </Button>
          )}
          <Button onClick={onClose}>
            Close
          </Button>
        </div>
      </Card>
    </div>
  );
}
