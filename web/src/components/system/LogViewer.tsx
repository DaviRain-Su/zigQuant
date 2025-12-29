// ============================================================================
// Log Viewer Component
// ============================================================================

import { useState, useEffect, useRef } from 'react';
import { 
  Terminal, 
  RefreshCw, 
  Trash2, 
  Filter,
  ChevronDown,
  AlertTriangle,
  AlertCircle,
  Info,
  Bug,
  Zap
} from 'lucide-react';
import { Card } from '../ui/Card';
import { Button } from '../ui/Button';
import { logsApi } from '../../api/endpoints';
import type { LogEntry, LogLevel } from '../../types/api';
import { cn } from '../../lib/utils';

interface LogViewerProps {
  className?: string;
  maxHeight?: string;
  autoRefresh?: boolean;
  refreshInterval?: number;
}

// Level configuration with icons and colors
const levelConfig: Record<LogLevel, { icon: React.ElementType; color: string; bg: string }> = {
  trace: { icon: Zap, color: 'text-gray-500', bg: 'bg-gray-500/10' },
  debug: { icon: Bug, color: 'text-cyan-500', bg: 'bg-cyan-500/10' },
  info: { icon: Info, color: 'text-green-500', bg: 'bg-green-500/10' },
  warn: { icon: AlertTriangle, color: 'text-yellow-500', bg: 'bg-yellow-500/10' },
  error: { icon: AlertCircle, color: 'text-red-500', bg: 'bg-red-500/10' },
  fatal: { icon: AlertCircle, color: 'text-red-600', bg: 'bg-red-600/20' },
};

// Format timestamp
function formatTime(timestamp: number): string {
  const date = new Date(timestamp);
  return date.toLocaleTimeString('en-US', {
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    hour12: false,
  }) + '.' + String(date.getMilliseconds()).padStart(3, '0');
}

export function LogViewer({ 
  className, 
  maxHeight = '400px',
  autoRefresh = true,
  refreshInterval = 3000
}: LogViewerProps) {
  const [logs, setLogs] = useState<LogEntry[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [filter, setFilter] = useState<LogLevel | 'all'>('all');
  const [showFilterMenu, setShowFilterMenu] = useState(false);
  const [isAutoRefresh, setIsAutoRefresh] = useState(autoRefresh);
  const containerRef = useRef<HTMLDivElement>(null);
  const [autoScroll, setAutoScroll] = useState(true);

  // Fetch logs
  const fetchLogs = async () => {
    try {
      setLoading(true);
      setError(null);
      
      const options = filter !== 'all' ? { level: filter, limit: 200 } : { limit: 200 };
      const response = await logsApi.getLogs(options);
      
      if (response.success && response.data) {
        setLogs(response.data.logs);
      } else {
        setError('Failed to fetch logs');
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to fetch logs');
    } finally {
      setLoading(false);
    }
  };

  // Initial fetch and auto-refresh
  useEffect(() => {
    fetchLogs();
    
    if (isAutoRefresh) {
      const interval = setInterval(fetchLogs, refreshInterval);
      return () => clearInterval(interval);
    }
  }, [filter, isAutoRefresh, refreshInterval]);

  // Auto-scroll to bottom
  useEffect(() => {
    if (autoScroll && containerRef.current) {
      containerRef.current.scrollTop = containerRef.current.scrollHeight;
    }
  }, [logs, autoScroll]);

  // Handle scroll to detect if user scrolled up
  const handleScroll = () => {
    if (containerRef.current) {
      const { scrollTop, scrollHeight, clientHeight } = containerRef.current;
      const isAtBottom = scrollHeight - scrollTop - clientHeight < 50;
      setAutoScroll(isAtBottom);
    }
  };

  // Clear logs display
  const clearLogs = () => {
    setLogs([]);
  };

  const filterOptions: { value: LogLevel | 'all'; label: string }[] = [
    { value: 'all', label: 'All Levels' },
    { value: 'trace', label: 'Trace' },
    { value: 'debug', label: 'Debug' },
    { value: 'info', label: 'Info' },
    { value: 'warn', label: 'Warning' },
    { value: 'error', label: 'Error' },
    { value: 'fatal', label: 'Fatal' },
  ];

  return (
    <Card className={cn('flex flex-col', className)}>
      {/* Header */}
      <div className="flex items-center justify-between p-3 border-b border-gray-800">
        <div className="flex items-center gap-2">
          <Terminal className="w-4 h-4 text-gray-400" />
          <span className="text-sm font-medium text-white">System Logs</span>
          <span className="text-xs text-gray-500">({logs.length})</span>
        </div>
        
        <div className="flex items-center gap-2">
          {/* Filter dropdown */}
          <div className="relative">
            <Button
              variant="ghost"
              size="sm"
              onClick={() => setShowFilterMenu(!showFilterMenu)}
              className="flex items-center gap-1"
            >
              <Filter className="w-3 h-3" />
              <span className="text-xs">{filter === 'all' ? 'All' : filter}</span>
              <ChevronDown className="w-3 h-3" />
            </Button>
            
            {showFilterMenu && (
              <div className="absolute right-0 mt-1 w-32 bg-gray-800 border border-gray-700 rounded-lg shadow-lg z-10">
                {filterOptions.map(option => (
                  <button
                    key={option.value}
                    onClick={() => {
                      setFilter(option.value);
                      setShowFilterMenu(false);
                    }}
                    className={cn(
                      'w-full px-3 py-1.5 text-left text-xs hover:bg-gray-700 first:rounded-t-lg last:rounded-b-lg',
                      filter === option.value ? 'text-blue-400' : 'text-gray-300'
                    )}
                  >
                    {option.label}
                  </button>
                ))}
              </div>
            )}
          </div>

          {/* Auto-refresh toggle */}
          <Button
            variant={isAutoRefresh ? 'secondary' : 'ghost'}
            size="sm"
            onClick={() => setIsAutoRefresh(!isAutoRefresh)}
            title={isAutoRefresh ? 'Disable auto-refresh' : 'Enable auto-refresh'}
          >
            <RefreshCw className={cn('w-3 h-3', isAutoRefresh && 'animate-spin')} />
          </Button>

          {/* Manual refresh */}
          <Button
            variant="ghost"
            size="sm"
            onClick={fetchLogs}
            disabled={loading}
          >
            <RefreshCw className={cn('w-3 h-3', loading && 'animate-spin')} />
          </Button>

          {/* Clear */}
          <Button
            variant="ghost"
            size="sm"
            onClick={clearLogs}
          >
            <Trash2 className="w-3 h-3" />
          </Button>
        </div>
      </div>

      {/* Log container */}
      <div 
        ref={containerRef}
        onScroll={handleScroll}
        className="flex-1 overflow-y-auto font-mono text-xs"
        style={{ maxHeight }}
      >
        {error && (
          <div className="p-4 text-center text-red-400">
            <AlertCircle className="w-5 h-5 mx-auto mb-2" />
            {error}
          </div>
        )}

        {!error && logs.length === 0 && (
          <div className="p-8 text-center text-gray-500">
            <Terminal className="w-8 h-8 mx-auto mb-2 opacity-50" />
            <p>No logs available</p>
            <p className="text-xs mt-1">Logs will appear here when the system generates them</p>
          </div>
        )}

        {logs.map((log, index) => {
          const config = levelConfig[log.level] || levelConfig.info;
          const Icon = config.icon;
          
          return (
            <div 
              key={index}
              className={cn(
                'flex items-start gap-2 px-3 py-1.5 border-b border-gray-800/50 hover:bg-gray-800/30',
                log.level === 'error' && 'bg-red-500/5',
                log.level === 'fatal' && 'bg-red-600/10',
                log.level === 'warn' && 'bg-yellow-500/5'
              )}
            >
              {/* Level icon */}
              <div className={cn('p-1 rounded', config.bg)}>
                <Icon className={cn('w-3 h-3', config.color)} />
              </div>
              
              {/* Timestamp */}
              <span className="text-gray-500 whitespace-nowrap">
                {formatTime(log.timestamp)}
              </span>
              
              {/* Source */}
              {log.source && (
                <span className="text-blue-400 whitespace-nowrap">
                  [{log.source}]
                </span>
              )}
              
              {/* Message */}
              <span className={cn(
                'flex-1 break-words',
                log.level === 'error' || log.level === 'fatal' ? 'text-red-300' :
                log.level === 'warn' ? 'text-yellow-300' :
                'text-gray-300'
              )}>
                {log.message}
              </span>
            </div>
          );
        })}
      </div>

      {/* Footer with auto-scroll indicator */}
      {!autoScroll && logs.length > 0 && (
        <div className="px-3 py-1 border-t border-gray-800 text-center">
          <button
            onClick={() => {
              setAutoScroll(true);
              if (containerRef.current) {
                containerRef.current.scrollTop = containerRef.current.scrollHeight;
              }
            }}
            className="text-xs text-blue-400 hover:text-blue-300"
          >
            Scroll to bottom
          </button>
        </div>
      )}
    </Card>
  );
}

export default LogViewer;
