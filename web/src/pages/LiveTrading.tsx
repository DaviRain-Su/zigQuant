// ============================================================================
// Trading Page - Unified live trading with strategy integration
// Supports: Testnet (Paper Trading) and Live Trading modes
// ============================================================================

import { useState } from 'react';
import { 
  Zap, 
  Pause, 
  Square, 
  Plus,
  Wifi,
  WifiOff,
  RefreshCw,
  TrendingUp,
  TrendingDown,
  Activity
} from 'lucide-react';
import { useLiveSessions, useStopLiveSession, useStartLiveSession } from '../hooks/useApi';
import { Card } from '../components/ui/Card';
import { Button } from '../components/ui/Button';
import { StatusBadge } from '../components/ui/Badge';
import { formatNumber, formatCurrency } from '../lib/utils';

// Connection status indicator component
function ConnectionIndicator({ status }: { status: string }) {
  const getStatusColor = () => {
    switch (status) {
      case 'connected': return 'text-green-500';
      case 'connecting': return 'text-yellow-500';
      case 'reconnecting': return 'text-orange-500';
      default: return 'text-red-500';
    }
  };

  const getStatusIcon = () => {
    switch (status) {
      case 'connected': return <Wifi className="w-4 h-4" />;
      case 'connecting': return <RefreshCw className="w-4 h-4 animate-spin" />;
      case 'reconnecting': return <RefreshCw className="w-4 h-4 animate-spin" />;
      default: return <WifiOff className="w-4 h-4" />;
    }
  };

  return (
    <div className={`flex items-center gap-1 ${getStatusColor()}`}>
      {getStatusIcon()}
      <span className="text-xs capitalize">{status}</span>
    </div>
  );
}

// Strategy options
const STRATEGIES = [
  { value: '', label: 'None (Data Only)' },
  { value: 'dual_ma', label: 'Dual Moving Average' },
  { value: 'rsi_mean_reversion', label: 'RSI Mean Reversion' },
  { value: 'bollinger_breakout', label: 'Bollinger Breakout' },
  { value: 'grid', label: 'Grid Trading' },
  { value: 'hybrid_ai', label: 'Hybrid AI' },
];

const TIMEFRAMES = ['1m', '5m', '15m', '30m', '1h', '4h', '1d'];

// New session dialog component
function NewSessionDialog({ onClose, onSubmit }: { 
  onClose: () => void; 
  onSubmit: (data: any) => void;
}) {
  const [name, setName] = useState('');
  const [symbols, setSymbols] = useState('BTC');
  const [exchange, setExchange] = useState('hyperliquid');
  const [testnet, setTestnet] = useState(true);
  const [strategy, setStrategy] = useState('');
  const [timeframe, setTimeframe] = useState('1h');
  const [initialCapital, setInitialCapital] = useState('0'); // 0 = use real balance
  const [leverage, setLeverage] = useState('1');
  // Grid specific
  const [upperPrice, setUpperPrice] = useState('');
  const [lowerPrice, setLowerPrice] = useState('');
  const [gridCount, setGridCount] = useState('10');
  const [orderSize, setOrderSize] = useState('0.001');

  const isGridStrategy = strategy === 'grid';

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    const data: any = {
      name: name || `session_${Date.now()}`,
      exchange,
      testnet,
      symbols: symbols.split(',').map(s => s.trim().toUpperCase()),
      timeframe,
      initial_capital: parseFloat(initialCapital) || 0, // 0 = use real balance
      leverage: Math.min(100, Math.max(1, parseInt(leverage) || 1)),
    };

    if (strategy) {
      data.strategy = strategy;
    }

    if (isGridStrategy) {
      data.upper_price = parseFloat(upperPrice);
      data.lower_price = parseFloat(lowerPrice);
      data.grid_count = parseInt(gridCount) || 10;
      data.order_size = parseFloat(orderSize) || 0.001;
    }

    onSubmit(data);
    onClose();
  };

  return (
    <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
      <div className="bg-gray-900 rounded-lg p-6 w-full max-w-md border border-gray-700 max-h-[90vh] overflow-y-auto">
        <h2 className="text-xl font-bold text-white mb-2">New Trading Session</h2>
        <p className="text-sm text-gray-400 mb-4">
          Create a new session with optional strategy. Enable Testnet for paper trading.
        </p>
        <form onSubmit={handleSubmit} className="space-y-4">
          <div>
            <label className="block text-sm text-gray-400 mb-1">Session Name</label>
            <input
              type="text"
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder="my_session"
              className="w-full bg-gray-800 border border-gray-700 rounded px-3 py-2 text-white"
            />
          </div>
          <div>
            <label className="block text-sm text-gray-400 mb-1">Symbols (comma-separated)</label>
            <input
              type="text"
              value={symbols}
              onChange={(e) => setSymbols(e.target.value)}
              placeholder="BTC, ETH"
              className="w-full bg-gray-800 border border-gray-700 rounded px-3 py-2 text-white"
            />
          </div>
          <div>
            <label className="block text-sm text-gray-400 mb-1">Exchange</label>
            <select
              value={exchange}
              onChange={(e) => setExchange(e.target.value)}
              className="w-full bg-gray-800 border border-gray-700 rounded px-3 py-2 text-white"
            >
              <option value="hyperliquid">Hyperliquid</option>
            </select>
          </div>
          <div>
            <label className="block text-sm text-gray-400 mb-1">Strategy</label>
            <select
              value={strategy}
              onChange={(e) => setStrategy(e.target.value)}
              className="w-full bg-gray-800 border border-gray-700 rounded px-3 py-2 text-white"
            >
              {STRATEGIES.map(s => (
                <option key={s.value} value={s.value}>{s.label}</option>
              ))}
            </select>
          </div>
          <div className="grid grid-cols-2 gap-4">
            <div>
              <label className="block text-sm text-gray-400 mb-1">Timeframe</label>
              <select
                value={timeframe}
                onChange={(e) => setTimeframe(e.target.value)}
                className="w-full bg-gray-800 border border-gray-700 rounded px-3 py-2 text-white"
              >
                {TIMEFRAMES.map(tf => (
                  <option key={tf} value={tf}>{tf}</option>
                ))}
              </select>
            </div>
            <div>
              <label className="block text-sm text-gray-400 mb-1">Initial Capital (0 = real balance)</label>
              <input
                type="number"
                value={initialCapital}
                onChange={(e) => setInitialCapital(e.target.value)}
                placeholder="0"
                className="w-full bg-gray-800 border border-gray-700 rounded px-3 py-2 text-white"
              />
            </div>
          </div>
          <div>
            <label className="block text-sm text-gray-400 mb-1">Leverage (1-100x)</label>
            <input
              type="number"
              min="1"
              max="100"
              value={leverage}
              onChange={(e) => setLeverage(e.target.value)}
              className="w-full bg-gray-800 border border-gray-700 rounded px-3 py-2 text-white"
            />
          </div>
          
          {/* Grid Strategy Parameters */}
          {isGridStrategy && (
            <div className="space-y-4 p-4 bg-gray-800/50 rounded-lg border border-gray-700">
              <h3 className="text-sm font-medium text-gray-300">Grid Parameters</h3>
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <label className="block text-sm text-gray-400 mb-1">Upper Price</label>
                  <input
                    type="number"
                    value={upperPrice}
                    onChange={(e) => setUpperPrice(e.target.value)}
                    placeholder="70000"
                    className="w-full bg-gray-800 border border-gray-700 rounded px-3 py-2 text-white"
                    required
                  />
                </div>
                <div>
                  <label className="block text-sm text-gray-400 mb-1">Lower Price</label>
                  <input
                    type="number"
                    value={lowerPrice}
                    onChange={(e) => setLowerPrice(e.target.value)}
                    placeholder="60000"
                    className="w-full bg-gray-800 border border-gray-700 rounded px-3 py-2 text-white"
                    required
                  />
                </div>
              </div>
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <label className="block text-sm text-gray-400 mb-1">Grid Levels</label>
                  <input
                    type="number"
                    value={gridCount}
                    onChange={(e) => setGridCount(e.target.value)}
                    className="w-full bg-gray-800 border border-gray-700 rounded px-3 py-2 text-white"
                  />
                </div>
                <div>
                  <label className="block text-sm text-gray-400 mb-1">Order Size (BTC)</label>
                  <input
                    type="number"
                    step="0.0001"
                    value={orderSize}
                    onChange={(e) => setOrderSize(e.target.value)}
                    placeholder="0.001"
                    className="w-full bg-gray-800 border border-gray-700 rounded px-3 py-2 text-white"
                  />
                </div>
              </div>
            </div>
          )}

          <div className="flex items-center gap-2">
            <input
              type="checkbox"
              id="testnet"
              checked={testnet}
              onChange={(e) => setTestnet(e.target.checked)}
              className="rounded bg-gray-800 border-gray-700"
            />
            <label htmlFor="testnet" className="text-sm text-gray-400">Use Testnet</label>
          </div>
          <div className="flex gap-2 justify-end mt-6">
            <Button type="button" variant="ghost" onClick={onClose}>Cancel</Button>
            <Button type="submit">Start Session</Button>
          </div>
        </form>
      </div>
    </div>
  );
}

// Trading mode filter options
type TradingModeFilter = 'all' | 'testnet' | 'live';

export default function LiveTrading() {
  const { data, isLoading, error } = useLiveSessions();
  const stopSession = useStopLiveSession();
  const startSession = useStartLiveSession();
  const [showNewDialog, setShowNewDialog] = useState(false);
  const [modeFilter, setModeFilter] = useState<TradingModeFilter>('all');

  const allSessions = data?.sessions || [];
  
  // Filter sessions by mode
  const sessions = allSessions.filter(s => {
    if (modeFilter === 'all') return true;
    if (modeFilter === 'testnet') return s.testnet;
    if (modeFilter === 'live') return !s.testnet;
    return true;
  });
  
  const activeSessions = sessions.filter(s => s.status === 'running');
  
  // Stats for mode counts
  const testnetCount = allSessions.filter(s => s.testnet).length;
  const liveCount = allSessions.filter(s => !s.testnet).length;
  
  // Calculate totals
  const totalPnL = sessions.reduce((sum, s) => sum + (s.realized_pnl || 0), 0);
  // Unused for now, but could be used in the future
  // const totalUnrealizedPnL = sessions.reduce((sum, s) => sum + (s.unrealized_pnl || 0), 0);
  const totalOrders = sessions.reduce((sum, s) => sum + (s.orders_submitted || 0), 0);

  const handleStop = async (id: string) => {
    try {
      await stopSession.mutateAsync(id);
    } catch (err) {
      console.error('Failed to stop session:', err);
    }
  };

  const handleStartSession = async (data: any) => {
    try {
      await startSession.mutateAsync(data);
    } catch (err) {
      console.error('Failed to start session:', err);
    }
  };

  return (
    <div className="space-y-6">
      {/* New Session Dialog */}
      {showNewDialog && (
        <NewSessionDialog 
          onClose={() => setShowNewDialog(false)}
          onSubmit={handleStartSession}
        />
      )}

      {/* Page Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-white">Trading</h1>
          <p className="text-gray-400 mt-1">
            Manage trading sessions with integrated strategy execution
          </p>
        </div>
        <div className="flex items-center gap-3">
          {/* Mode Filter */}
          <div className="flex items-center gap-1 bg-gray-800 rounded-lg p-1">
            <button
              onClick={() => setModeFilter('all')}
              className={`px-3 py-1.5 text-sm rounded-md transition-colors ${
                modeFilter === 'all' 
                  ? 'bg-blue-600 text-white' 
                  : 'text-gray-400 hover:text-white'
              }`}
            >
              All ({allSessions.length})
            </button>
            <button
              onClick={() => setModeFilter('testnet')}
              className={`px-3 py-1.5 text-sm rounded-md transition-colors ${
                modeFilter === 'testnet' 
                  ? 'bg-yellow-600 text-white' 
                  : 'text-gray-400 hover:text-white'
              }`}
            >
              Testnet ({testnetCount})
            </button>
            <button
              onClick={() => setModeFilter('live')}
              className={`px-3 py-1.5 text-sm rounded-md transition-colors ${
                modeFilter === 'live' 
                  ? 'bg-green-600 text-white' 
                  : 'text-gray-400 hover:text-white'
              }`}
            >
              Live ({liveCount})
            </button>
          </div>
          <Button 
            icon={<Plus className="w-4 h-4" />}
            onClick={() => setShowNewDialog(true)}
            loading={startSession.isPending}
          >
            New Session
          </Button>
        </div>
      </div>

      {/* Stats Overview */}
      <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
        <Card>
          <div className="flex items-center gap-2">
            <Activity className="w-5 h-5 text-green-500" />
            <span className="text-sm text-gray-400">Active Sessions</span>
          </div>
          <div className="text-2xl font-bold text-green-500 mt-2">{activeSessions.length}</div>
        </Card>
        <Card>
          <div className="text-sm text-gray-400">Total Sessions</div>
          <div className="text-2xl font-bold text-white mt-1">{sessions.length}</div>
        </Card>
        <Card>
          <div className="flex items-center gap-2">
            {totalPnL >= 0 ? (
              <TrendingUp className="w-5 h-5 text-green-500" />
            ) : (
              <TrendingDown className="w-5 h-5 text-red-500" />
            )}
            <span className="text-sm text-gray-400">Realized PnL</span>
          </div>
          <div className={`text-2xl font-bold mt-1 ${totalPnL >= 0 ? 'text-green-500' : 'text-red-500'}`}>
            {formatCurrency(totalPnL)}
          </div>
        </Card>
        <Card>
          <div className="text-sm text-gray-400">Total Orders</div>
          <div className="text-2xl font-bold text-white mt-1">{totalOrders}</div>
        </Card>
      </div>

      {/* Active Sessions */}
      {activeSessions.length > 0 && (
        <div className="space-y-4">
          <h2 className="text-lg font-semibold text-white">Active Sessions</h2>
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
            {activeSessions.map((session) => (
              <Card key={session.id} className="p-0">
                <div className="p-4 border-b border-gray-800">
                  <div className="flex items-center justify-between">
                    <div className="flex items-center gap-3">
                      <div className="p-2 bg-green-500/10 rounded-lg">
                        <Zap className="w-5 h-5 text-green-500" />
                      </div>
                      <div>
                        <h3 className="font-medium text-white">{session.name || session.id}</h3>
                        <div className="flex items-center gap-2 mt-1">
                          <span className="text-sm text-gray-500">{session.exchange}</span>
                          {session.testnet && (
                            <span className="text-xs bg-yellow-500/20 text-yellow-500 px-1.5 py-0.5 rounded">
                              Testnet
                            </span>
                          )}
                        </div>
                      </div>
                    </div>
                    <div className="flex flex-col items-end gap-1">
                      <StatusBadge status={session.status} />
                      <ConnectionIndicator status={session.connection_status} />
                    </div>
                  </div>
                </div>

                {/* Strategy & Symbols */}
                <div className="px-4 py-2 border-b border-gray-800 flex flex-wrap items-center gap-2">
                  {session.strategy && session.strategy !== 'none' && (
                    <span className="text-xs bg-purple-500/20 text-purple-400 px-2 py-0.5 rounded">
                      {session.strategy}
                    </span>
                  )}
                  <span className="text-xs bg-gray-700 text-gray-300 px-2 py-0.5 rounded">
                    {session.timeframe}
                  </span>
                  {session.leverage > 1 && (
                    <span className="text-xs bg-orange-500/20 text-orange-400 px-2 py-0.5 rounded">
                      {session.leverage}x
                    </span>
                  )}
                  {session.symbols && session.symbols.map((sym) => (
                    <span key={sym} className="text-xs bg-blue-500/20 text-blue-400 px-2 py-0.5 rounded">
                      {sym}
                    </span>
                  ))}
                </div>

                {/* Account Balance */}
                <div className="px-4 py-3 border-b border-gray-800 bg-gray-800/30">
                  <div className="flex justify-between items-center">
                    <div>
                      <div className="text-xs text-gray-500">Account Balance</div>
                      <div className="text-lg font-semibold text-white">
                        {formatCurrency(session.account_balance)}
                      </div>
                    </div>
                    <div className="text-right">
                      <div className="text-xs text-gray-500">Available</div>
                      <div className="text-lg font-semibold text-green-400">
                        {formatCurrency(session.available_balance)}
                      </div>
                    </div>
                  </div>
                </div>

                {/* Position Info */}
                {session.current_position !== 0 && (
                  <div className="px-4 py-2 border-b border-gray-800 bg-blue-500/5">
                    <div className="flex justify-between items-center">
                      <div className="flex items-center gap-2">
                        <span className={`text-xs px-1.5 py-0.5 rounded ${session.current_position > 0 ? 'bg-green-500/20 text-green-400' : 'bg-red-500/20 text-red-400'}`}>
                          {session.current_position > 0 ? 'LONG' : 'SHORT'}
                        </span>
                        <span className="text-white font-medium">
                          {Math.abs(session.current_position).toFixed(4)}
                        </span>
                      </div>
                      <div className="text-right">
                        <span className="text-xs text-gray-500">Entry: </span>
                        <span className="text-white">{formatCurrency(session.entry_price)}</span>
                      </div>
                    </div>
                  </div>
                )}

                {/* Stats Grid */}
                <div className="p-4 grid grid-cols-2 gap-4">
                  <div>
                    <div className="text-xs text-gray-500">Last Price</div>
                    <div className="text-lg font-semibold text-white">
                      {session.last_price > 0 ? formatCurrency(session.last_price) : '-'}
                    </div>
                  </div>
                  <div>
                    <div className="text-xs text-gray-500">Unrealized PnL</div>
                    <div className={`text-lg font-semibold ${session.unrealized_pnl >= 0 ? 'text-green-500' : 'text-red-500'}`}>
                      {formatCurrency(session.unrealized_pnl)}
                    </div>
                  </div>
                  <div>
                    <div className="text-xs text-gray-500">Orders (Sub/Fill)</div>
                    <div className="text-lg font-semibold text-white">
                      {session.orders_submitted}/{session.orders_filled}
                    </div>
                  </div>
                  <div>
                    <div className="text-xs text-gray-500">Ticks</div>
                    <div className="text-lg font-semibold text-white">
                      {formatNumber(session.ticks)}
                    </div>
                  </div>
                </div>

                <div className="px-4 pb-4 flex items-center justify-between">
                  <div className="flex items-center gap-4 text-sm">
                    <div>
                      <span className="text-gray-500">Realized PnL:</span>
                      <span className={`ml-1 ${session.realized_pnl >= 0 ? 'text-green-500' : 'text-red-500'}`}>
                        {formatCurrency(session.realized_pnl)}
                      </span>
                    </div>
                    {session.reconnects > 0 && (
                      <div>
                        <span className="text-gray-500">Reconnects:</span>
                        <span className="ml-1 text-yellow-500">{session.reconnects}</span>
                      </div>
                    )}
                  </div>
                  <div className="flex items-center gap-2">
                    <Button size="sm" variant="ghost" icon={<Pause className="w-4 h-4" />}>
                      Pause
                    </Button>
                    <Button 
                      size="sm" 
                      variant="danger" 
                      onClick={() => handleStop(session.id)}
                      loading={stopSession.isPending}
                      icon={<Square className="w-4 h-4" />}
                    >
                      Stop
                    </Button>
                  </div>
                </div>
              </Card>
            ))}
          </div>
        </div>
      )}

      {/* All Sessions Table */}
      <Card padding="none">
        <div className="p-4 border-b border-gray-800">
          <h2 className="text-lg font-semibold text-white">All Sessions</h2>
        </div>
        
        {isLoading ? (
          <div className="p-8 text-center text-gray-500">Loading sessions...</div>
        ) : error ? (
          <div className="p-8 text-center text-red-500">Failed to load sessions</div>
        ) : sessions.length === 0 ? (
          <div className="p-8 text-center">
            <Zap className="w-12 h-12 text-gray-600 mx-auto mb-3" />
            <p className="text-gray-400">No live sessions</p>
            <p className="text-gray-500 text-sm mt-1">Start a live trading session to begin</p>
            <Button 
              className="mt-4" 
              icon={<Plus className="w-4 h-4" />}
              onClick={() => setShowNewDialog(true)}
            >
              Start Session
            </Button>
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full">
              <thead className="bg-gray-800/50">
                <tr>
                  <th className="px-4 py-3 text-left text-xs font-medium text-gray-400 uppercase">Session</th>
                  <th className="px-4 py-3 text-left text-xs font-medium text-gray-400 uppercase">Strategy</th>
                  <th className="px-4 py-3 text-left text-xs font-medium text-gray-400 uppercase">Symbols</th>
                  <th className="px-4 py-3 text-left text-xs font-medium text-gray-400 uppercase">Status</th>
                  <th className="px-4 py-3 text-right text-xs font-medium text-gray-400 uppercase">Balance</th>
                  <th className="px-4 py-3 text-right text-xs font-medium text-gray-400 uppercase">Position</th>
                  <th className="px-4 py-3 text-right text-xs font-medium text-gray-400 uppercase">PnL</th>
                  <th className="px-4 py-3 text-right text-xs font-medium text-gray-400 uppercase">Actions</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-800">
                {sessions.map((session) => (
                  <tr key={session.id} className="hover:bg-gray-800/30">
                    <td className="px-4 py-4 whitespace-nowrap">
                      <div>
                        <span className="text-white font-medium">{session.name || session.id}</span>
                        <div className="text-xs text-gray-500 flex items-center gap-1">
                          {session.exchange}
                          {session.testnet && (
                            <span className="text-yellow-500">(testnet)</span>
                          )}
                        </div>
                      </div>
                    </td>
                    <td className="px-4 py-4 whitespace-nowrap">
                      {session.strategy && session.strategy !== 'none' ? (
                        <div className="flex flex-col gap-1">
                          <div className="flex items-center gap-1">
                            <span className="text-xs bg-purple-500/20 text-purple-400 px-1.5 py-0.5 rounded">
                              {session.strategy}
                            </span>
                            {session.leverage > 1 && (
                              <span className="text-xs bg-orange-500/20 text-orange-400 px-1.5 py-0.5 rounded">
                                {session.leverage}x
                              </span>
                            )}
                          </div>
                          <span className="text-xs text-gray-500">{session.timeframe}</span>
                        </div>
                      ) : (
                        <span className="text-xs text-gray-500">-</span>
                      )}
                    </td>
                    <td className="px-4 py-4 whitespace-nowrap">
                      <div className="flex gap-1">
                        {session.symbols?.slice(0, 3).map((sym) => (
                          <span key={sym} className="text-xs bg-blue-500/20 text-blue-400 px-1.5 py-0.5 rounded">
                            {sym}
                          </span>
                        ))}
                        {session.symbols && session.symbols.length > 3 && (
                          <span className="text-xs text-gray-500">+{session.symbols.length - 3}</span>
                        )}
                      </div>
                    </td>
                    <td className="px-4 py-4 whitespace-nowrap">
                      <div className="flex items-center gap-2">
                        <StatusBadge status={session.status} />
                        <ConnectionIndicator status={session.connection_status} />
                      </div>
                    </td>
                    <td className="px-4 py-4 whitespace-nowrap text-right">
                      <div className="text-white">{formatCurrency(session.account_balance)}</div>
                      <div className="text-xs text-gray-500">Avail: {formatCurrency(session.available_balance)}</div>
                    </td>
                    <td className="px-4 py-4 whitespace-nowrap text-right">
                      {session.current_position !== 0 ? (
                        <div>
                          <span className={session.current_position > 0 ? 'text-green-500' : 'text-red-500'}>
                            {session.current_position > 0 ? '+' : ''}{session.current_position.toFixed(4)}
                          </span>
                          <div className="text-xs text-gray-500">@ {formatCurrency(session.entry_price)}</div>
                        </div>
                      ) : (
                        <span className="text-gray-500">-</span>
                      )}
                    </td>
                    <td className="px-4 py-4 whitespace-nowrap text-right">
                      <span className={session.realized_pnl >= 0 ? 'text-green-500' : 'text-red-500'}>
                        {formatCurrency(session.realized_pnl)}
                      </span>
                    </td>
                    <td className="px-4 py-4 whitespace-nowrap text-right">
                      {session.status === 'running' && (
                        <Button 
                          size="sm" 
                          variant="danger" 
                          onClick={() => handleStop(session.id)}
                          loading={stopSession.isPending}
                        >
                          Stop
                        </Button>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Card>
    </div>
  );
}
