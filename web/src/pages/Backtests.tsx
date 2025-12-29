// ============================================================================
// Backtests Page
// ============================================================================

import { useState } from 'react';
import { 
  Plus,
  BarChart3,
  Loader2,
  Eye,
  Clock
} from 'lucide-react';
import { useBacktests, useBacktest, useRunBacktest, useCancelBacktest } from '../hooks/useApi';
import { Card } from '../components/ui/Card';
import { Button } from '../components/ui/Button';
import { StatusBadge } from '../components/ui/Badge';
import { BacktestForm } from '../components/trading/BacktestForm';
import { BacktestResults } from '../components/trading/BacktestResults';
import type { BacktestRequest } from '../types/api';

export default function Backtests() {
  const { data, isLoading, error } = useBacktests();
  const runBacktest = useRunBacktest();
  const cancelBacktest = useCancelBacktest();
  
  // Modal states
  const [showNewBacktest, setShowNewBacktest] = useState(false);
  const [selectedBacktestId, setSelectedBacktestId] = useState<string | null>(null);
  
  // Get selected backtest details
  const { data: selectedBacktest } = useBacktest(selectedBacktestId || '');

  const backtests = data?.backtests || [];
  const runningBacktests = backtests.filter(b => b.status === 'running');
  const completedBacktests = backtests.filter(b => b.status === 'completed');
  const failedBacktests = backtests.filter(b => b.status === 'failed');

  // Handle new backtest submission
  const handleRunBacktest = async (request: BacktestRequest) => {
    try {
      const result = await runBacktest.mutateAsync(request);
      setShowNewBacktest(false);
      // Auto-select the new backtest to show progress
      if (result.id) {
        setSelectedBacktestId(result.id);
      }
    } catch (err) {
      console.error('Failed to run backtest:', err);
    }
  };

  // Handle cancel backtest
  const handleCancel = async (id: string) => {
    try {
      await cancelBacktest.mutateAsync(id);
    } catch (err) {
      console.error('Failed to cancel backtest:', err);
    }
  };

  // Handle view backtest
  const handleView = (id: string) => {
    setSelectedBacktestId(id);
  };

  return (
    <div className="space-y-6">
      {/* Page Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-white">Backtests</h1>
          <p className="text-gray-400 mt-1">Run and analyze strategy backtests</p>
        </div>
        <Button 
          icon={<Plus className="w-4 h-4" />}
          onClick={() => setShowNewBacktest(true)}
        >
          New Backtest
        </Button>
      </div>

      {/* Stats Overview */}
      <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
        <Card>
          <div className="text-sm text-gray-400">Total Backtests</div>
          <div className="text-2xl font-bold text-white mt-1">{backtests.length}</div>
        </Card>
        <Card>
          <div className="text-sm text-gray-400">Running</div>
          <div className="text-2xl font-bold text-blue-500 mt-1">{runningBacktests.length}</div>
        </Card>
        <Card>
          <div className="text-sm text-gray-400">Completed</div>
          <div className="text-2xl font-bold text-green-500 mt-1">{completedBacktests.length}</div>
        </Card>
        <Card>
          <div className="text-sm text-gray-400">Failed</div>
          <div className="text-2xl font-bold text-red-500 mt-1">{failedBacktests.length}</div>
        </Card>
      </div>

      {/* Running Backtests */}
      {runningBacktests.length > 0 && (
        <Card padding="none">
          <div className="p-4 border-b border-gray-800">
            <h2 className="text-lg font-semibold text-white flex items-center gap-2">
              <Loader2 className="w-5 h-5 animate-spin text-blue-500" />
              Running Backtests
            </h2>
          </div>
          <div className="divide-y divide-gray-800">
            {runningBacktests.map((backtest) => (
              <div key={backtest.id} className="p-4">
                <div className="flex items-center justify-between mb-3">
                  <div>
                    <h3 className="font-medium text-white">{backtest.strategy}</h3>
                    <p className="text-sm text-gray-500">{backtest.symbol}</p>
                  </div>
                  <div className="flex items-center gap-2">
                    <Button 
                      size="sm" 
                      variant="secondary"
                      icon={<Eye className="w-4 h-4" />}
                      onClick={() => handleView(backtest.id)}
                    >
                      View
                    </Button>
                    <Button 
                      size="sm" 
                      variant="danger"
                      onClick={() => handleCancel(backtest.id)}
                      loading={cancelBacktest.isPending}
                    >
                      Cancel
                    </Button>
                  </div>
                </div>
                <div className="w-full h-2 bg-gray-700 rounded-full overflow-hidden">
                  <div 
                    className="h-full bg-blue-500 transition-all duration-300" 
                    style={{ width: `${(backtest.progress || 0) * 100}%` }}
                  ></div>
                </div>
                <div className="flex items-center justify-between mt-2">
                  <p className="text-xs text-gray-500">
                    {Math.round((backtest.progress || 0) * 100)}% complete
                  </p>
                  <p className="text-xs text-gray-500">
                    {backtest.trades_so_far || 0} trades
                  </p>
                </div>
              </div>
            ))}
          </div>
        </Card>
      )}

      {/* All Backtests */}
      <Card padding="none">
        <div className="p-4 border-b border-gray-800">
          <h2 className="text-lg font-semibold text-white">Backtest History</h2>
        </div>
        
        {isLoading ? (
          <div className="p-8 text-center text-gray-500">
            <Loader2 className="w-8 h-8 animate-spin mx-auto mb-2" />
            Loading backtests...
          </div>
        ) : error ? (
          <div className="p-8 text-center text-red-500">Failed to load backtests</div>
        ) : backtests.length === 0 ? (
          <div className="p-8 text-center">
            <BarChart3 className="w-12 h-12 text-gray-600 mx-auto mb-3" />
            <p className="text-gray-400">No backtests yet</p>
            <p className="text-gray-500 text-sm mt-1">Run your first backtest to analyze strategy performance</p>
            <Button 
              className="mt-4" 
              icon={<Plus className="w-4 h-4" />}
              onClick={() => setShowNewBacktest(true)}
            >
              Run Backtest
            </Button>
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full">
              <thead className="bg-gray-800/50">
                <tr>
                  <th className="px-4 py-3 text-left text-xs font-medium text-gray-400 uppercase tracking-wider">ID</th>
                  <th className="px-4 py-3 text-left text-xs font-medium text-gray-400 uppercase tracking-wider">Strategy</th>
                  <th className="px-4 py-3 text-left text-xs font-medium text-gray-400 uppercase tracking-wider">Symbol</th>
                  <th className="px-4 py-3 text-left text-xs font-medium text-gray-400 uppercase tracking-wider">Status</th>
                  <th className="px-4 py-3 text-left text-xs font-medium text-gray-400 uppercase tracking-wider">Trades</th>
                  <th className="px-4 py-3 text-left text-xs font-medium text-gray-400 uppercase tracking-wider">Duration</th>
                  <th className="px-4 py-3 text-right text-xs font-medium text-gray-400 uppercase tracking-wider">Actions</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-800">
                {backtests.map((backtest) => (
                  <tr key={backtest.id} className="hover:bg-gray-800/30">
                    <td className="px-4 py-4 whitespace-nowrap">
                      <span className="text-white font-mono text-sm">{backtest.id.slice(0, 8)}</span>
                    </td>
                    <td className="px-4 py-4 whitespace-nowrap">
                      <span className="text-white">{backtest.strategy}</span>
                    </td>
                    <td className="px-4 py-4 whitespace-nowrap text-gray-400">
                      {backtest.symbol || 'BTCUSDT'}
                    </td>
                    <td className="px-4 py-4 whitespace-nowrap">
                      <StatusBadge status={backtest.status} />
                    </td>
                    <td className="px-4 py-4 whitespace-nowrap text-gray-400">
                      {backtest.trades_so_far || '-'}
                    </td>
                    <td className="px-4 py-4 whitespace-nowrap text-gray-500">
                      <div className="flex items-center gap-1">
                        <Clock className="w-3 h-3" />
                        {backtest.elapsed_seconds ? `${backtest.elapsed_seconds}s` : '-'}
                      </div>
                    </td>
                    <td className="px-4 py-4 whitespace-nowrap text-right">
                      <div className="flex items-center justify-end gap-2">
                        <Button 
                          size="sm" 
                          variant="ghost" 
                          icon={<Eye className="w-4 h-4" />}
                          onClick={() => handleView(backtest.id)}
                        >
                          View
                        </Button>
                        {backtest.status === 'running' && (
                          <Button 
                            size="sm" 
                            variant="danger"
                            onClick={() => handleCancel(backtest.id)}
                            loading={cancelBacktest.isPending}
                          >
                            Cancel
                          </Button>
                        )}
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Card>

      {/* New Backtest Modal */}
      {showNewBacktest && (
        <BacktestForm
          onSubmit={handleRunBacktest}
          onCancel={() => setShowNewBacktest(false)}
          isLoading={runBacktest.isPending}
        />
      )}

      {/* Backtest Results Modal */}
      {selectedBacktestId && selectedBacktest && (
        <BacktestResults
          result={selectedBacktest}
          onClose={() => setSelectedBacktestId(null)}
        />
      )}
    </div>
  );
}
