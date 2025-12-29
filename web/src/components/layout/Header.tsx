// ============================================================================
// Header Component
// ============================================================================

import { Bell, Moon, Sun, Wifi, WifiOff, AlertOctagon } from 'lucide-react';
import { cn } from '../../lib/utils';
import { useAppStore } from '../../stores/app';
import { useKillSwitch } from '../../hooks/useApi';

export function Header() {
  const { 
    theme, 
    setTheme, 
    wsConnected, 
    killSwitchActive,
    systemHealth 
  } = useAppStore();
  
  const killSwitch = useKillSwitch();

  const handleKillSwitch = () => {
    if (confirm('Are you sure you want to activate the Kill Switch? This will stop all strategies and cancel all orders.')) {
      killSwitch.mutate({
        reason: 'Manual activation from dashboard',
        cancelOrders: true,
        closePositions: false,
      });
    }
  };

  return (
    <header className="h-16 bg-gray-900 border-b border-gray-800 flex items-center justify-between px-6">
      {/* Left side - Status */}
      <div className="flex items-center gap-4">
        {/* Connection Status */}
        <div className={cn(
          'flex items-center gap-2 px-3 py-1.5 rounded-full text-sm',
          wsConnected 
            ? 'bg-green-500/10 text-green-500' 
            : 'bg-red-500/10 text-red-500'
        )}>
          {wsConnected ? (
            <>
              <Wifi className="w-4 h-4" />
              <span>Connected</span>
            </>
          ) : (
            <>
              <WifiOff className="w-4 h-4" />
              <span>Disconnected</span>
            </>
          )}
        </div>

        {/* System Health */}
        {systemHealth && (
          <div className="flex items-center gap-4 text-sm text-gray-400">
            <span>
              Strategies: <span className="text-white">{systemHealth.metrics.running_strategies}</span>
            </span>
            <span>
              Live: <span className="text-white">{systemHealth.metrics.running_live}</span>
            </span>
            <span>
              Backtests: <span className="text-white">{systemHealth.metrics.active_backtests}</span>
            </span>
          </div>
        )}
      </div>

      {/* Right side - Actions */}
      <div className="flex items-center gap-3">
        {/* Kill Switch Button */}
        <button
          onClick={handleKillSwitch}
          disabled={killSwitchActive || killSwitch.isPending}
          className={cn(
            'flex items-center gap-2 px-4 py-2 rounded-lg font-medium transition-colors',
            killSwitchActive
              ? 'bg-red-500 text-white cursor-not-allowed'
              : 'bg-red-500/10 text-red-500 hover:bg-red-500/20 border border-red-500/20'
          )}
        >
          <AlertOctagon className="w-4 h-4" />
          <span>{killSwitchActive ? 'Kill Switch Active' : 'Kill Switch'}</span>
        </button>

        {/* Notifications */}
        <button className="p-2 text-gray-400 hover:text-white hover:bg-gray-800 rounded-lg transition-colors relative">
          <Bell className="w-5 h-5" />
          <span className="absolute top-1 right-1 w-2 h-2 bg-red-500 rounded-full" />
        </button>

        {/* Theme Toggle */}
        <button
          onClick={() => setTheme(theme === 'dark' ? 'light' : 'dark')}
          className="p-2 text-gray-400 hover:text-white hover:bg-gray-800 rounded-lg transition-colors"
        >
          {theme === 'dark' ? (
            <Sun className="w-5 h-5" />
          ) : (
            <Moon className="w-5 h-5" />
          )}
        </button>
      </div>
    </header>
  );
}

export default Header;
