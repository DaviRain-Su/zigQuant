// ============================================================================
// Dashboard Page
// ============================================================================

import { 
  Activity, 
  Zap, 
  Brain,
  AlertTriangle,
  CheckCircle,
  Clock,
  Server,
  BarChart3
} from 'lucide-react';
import { useSystemHealth, useLiveSessions, useBacktests, useAIConfig } from '../hooks/useApi';
import { Card } from '../components/ui/Card';
import { Badge } from '../components/ui/Badge';
import { PnLChart } from '../components/charts/PnLChart';
import { LogViewer } from '../components/system/LogViewer';

export default function Dashboard() {
  const { data: health, isLoading: healthLoading } = useSystemHealth();
  const { data: liveData } = useLiveSessions();
  const { data: backtestsData } = useBacktests();
  const { data: aiConfig } = useAIConfig();

  const liveSessions = liveData?.sessions || [];
  const backtests = backtestsData?.backtests || [];

  const activeSessions = liveSessions.filter(s => s.status === 'running').length;
  const testnetSessions = liveSessions.filter(s => s.testnet).length;
  const liveTradingSessions = liveSessions.filter(s => !s.testnet && s.status === 'running').length;
  const runningBacktests = backtests.filter(b => b.status === 'running').length;

  return (
    <div className="space-y-6">
      {/* Page Header */}
      <div>
        <h1 className="text-2xl font-bold text-white">Dashboard</h1>
        <p className="text-gray-400 mt-1">Overview of your trading system</p>
      </div>

      {/* Status Cards */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
        {/* System Status */}
        <Card>
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm text-gray-400">System Status</p>
              <div className="flex items-center gap-2 mt-1">
                {healthLoading ? (
                  <span className="text-gray-500">Loading...</span>
                ) : health?.status === 'healthy' ? (
                  <>
                    <CheckCircle className="w-5 h-5 text-green-500" />
                    <span className="text-lg font-semibold text-green-500">Healthy</span>
                  </>
                ) : (
                  <>
                    <AlertTriangle className="w-5 h-5 text-yellow-500" />
                    <span className="text-lg font-semibold text-yellow-500">Degraded</span>
                  </>
                )}
              </div>
            </div>
            <Server className="w-10 h-10 text-gray-600" />
          </div>
          <div className="mt-3 text-xs text-gray-500">
            Uptime: {health?.metrics?.uptime_seconds ? `${health.metrics.uptime_seconds}s` : 'N/A'}
          </div>
        </Card>

        {/* Active Trading Sessions */}
        <Card>
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm text-gray-400">Active Trading</p>
              <p className="text-2xl font-bold text-white mt-1">{activeSessions}</p>
            </div>
            <Activity className="w-10 h-10 text-blue-500" />
          </div>
          <div className="mt-3 text-xs text-gray-500">
            {testnetSessions} testnet / {liveTradingSessions} live
          </div>
        </Card>

        {/* Running Backtests */}
        <Card>
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm text-gray-400">Running Backtests</p>
              <p className="text-2xl font-bold text-white mt-1">{runningBacktests}</p>
            </div>
            <Zap className="w-10 h-10 text-yellow-500" />
          </div>
          <div className="mt-3 text-xs text-gray-500">
            {backtests.length} total backtests
          </div>
        </Card>

        {/* AI Status */}
        <Card>
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm text-gray-400">AI Assistant</p>
              <div className="flex items-center gap-2 mt-1">
                {aiConfig?.enabled ? (
                  <>
                    <span className="w-2 h-2 rounded-full bg-green-500"></span>
                    <span className="text-lg font-semibold text-green-500">Enabled</span>
                  </>
                ) : (
                  <>
                    <span className="w-2 h-2 rounded-full bg-gray-500"></span>
                    <span className="text-lg font-semibold text-gray-500">Disabled</span>
                  </>
                )}
              </div>
            </div>
            <Brain className="w-10 h-10 text-purple-500" />
          </div>
          <div className="mt-3 text-xs text-gray-500">
            {aiConfig?.provider || 'Not configured'}
          </div>
        </Card>
      </div>

      {/* Charts Section */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* PnL Chart */}
        <Card className="p-0">
          <div className="p-4 border-b border-gray-800">
            <h2 className="text-lg font-semibold text-white flex items-center gap-2">
              <BarChart3 className="w-5 h-5" />
              Performance Overview
            </h2>
          </div>
          <div className="p-4" style={{ minHeight: 300 }}>
            <PnLChart height={280} />
          </div>
        </Card>

        {/* Recent Activity */}
        <Card className="p-0">
          <div className="p-4 border-b border-gray-800">
            <h2 className="text-lg font-semibold text-white flex items-center gap-2">
              <Clock className="w-5 h-5" />
              Recent Activity
            </h2>
          </div>
          <div className="p-4 space-y-3">
            {backtests.slice(0, 5).map((backtest) => (
              <div key={backtest.id} className="flex items-center justify-between py-2 border-b border-gray-800 last:border-0">
                <div>
                  <p className="text-sm font-medium text-white">{backtest.strategy || 'Backtest'}</p>
                  <p className="text-xs text-gray-500">{backtest.status}</p>
                </div>
                <Badge variant={backtest.status === 'completed' ? 'success' : backtest.status === 'running' ? 'info' : 'default'}>
                  {backtest.status}
                </Badge>
              </div>
            ))}
            {backtests.length === 0 && (
              <p className="text-gray-500 text-center py-4">No recent activity</p>
            )}
          </div>
        </Card>
      </div>

      {/* Active Items */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* Active Trading Sessions */}
        <Card className="p-0">
          <div className="p-4 border-b border-gray-800">
            <h2 className="text-lg font-semibold text-white">Active Trading Sessions</h2>
          </div>
          <div className="p-4 space-y-2">
            {liveSessions.filter(s => s.status === 'running').map((session) => (
              <div key={session.id} className="flex items-center justify-between p-2 bg-gray-800/50 rounded-lg">
                <div>
                  <div className="flex items-center gap-2">
                    <span className="text-sm text-white">{session.name || session.id}</span>
                    {session.testnet && (
                      <span className="text-xs bg-yellow-500/20 text-yellow-500 px-1.5 py-0.5 rounded">
                        Testnet
                      </span>
                    )}
                    {!session.testnet && (
                      <span className="text-xs bg-green-500/20 text-green-500 px-1.5 py-0.5 rounded">
                        Live
                      </span>
                    )}
                  </div>
                  <p className="text-xs text-gray-500">
                    {session.exchange} {session.strategy ? `- ${session.strategy}` : ''}
                  </p>
                </div>
                <span className="w-2 h-2 rounded-full bg-green-500 animate-pulse"></span>
              </div>
            ))}
            {activeSessions === 0 && (
              <p className="text-gray-500 text-center py-2">No active trading sessions</p>
            )}
          </div>
        </Card>

        {/* Running Backtests */}
        <Card className="p-0">
          <div className="p-4 border-b border-gray-800">
            <h2 className="text-lg font-semibold text-white">Running Backtests</h2>
          </div>
          <div className="p-4 space-y-2">
            {backtests.filter(b => b.status === 'running').map((backtest) => (
              <div key={backtest.id} className="flex items-center justify-between p-2 bg-gray-800/50 rounded-lg">
                <span className="text-sm text-white">{backtest.id}</span>
                <div className="w-20 h-2 bg-gray-700 rounded-full overflow-hidden">
                  <div 
                    className="h-full bg-blue-500 transition-all duration-300" 
                    style={{ width: `${(backtest.progress || 0) * 100}%` }}
                  ></div>
                </div>
              </div>
            ))}
            {runningBacktests === 0 && (
              <p className="text-gray-500 text-center py-2">No running backtests</p>
            )}
          </div>
        </Card>
      </div>

      {/* System Logs */}
      <div>
        <LogViewer maxHeight="350px" autoRefresh={true} refreshInterval={5000} />
      </div>
    </div>
  );
}
