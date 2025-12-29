// ============================================================================
// PnL Chart Component
// ============================================================================

import { useMemo } from 'react';
import { 
  AreaChart, 
  Area, 
  XAxis, 
  YAxis, 
  CartesianGrid, 
  Tooltip, 
  ResponsiveContainer 
} from 'recharts';
import { formatCurrency } from '../../lib/utils';

interface PnLDataPoint {
  timestamp: number;
  value?: number;
  equity?: number;
  pnl: number;
  pnlPercent?: number;
  balance?: number;
}

interface PnLChartProps {
  data?: PnLDataPoint[];
  height?: number;
}

// Demo data for when no real data is available
const generateDemoData = (): PnLDataPoint[] => {
  const data: PnLDataPoint[] = [];
  let value = 10000;
  const now = Date.now();
  
  for (let i = 30; i >= 0; i--) {
    const change = (Math.random() - 0.48) * 200;
    value += change;
    data.push({
      timestamp: now - i * 24 * 60 * 60 * 1000,
      value: Math.max(8000, value),
      pnl: change,
    });
  }
  
  return data;
};

export function PnLChart({ data, height = 300 }: PnLChartProps) {
  const chartData = useMemo(() => {
    if (data && data.length > 0) {
      // Normalize data - support both 'value' and 'equity' fields
      return data.map(d => ({
        ...d,
        value: d.value ?? d.equity ?? 0,
      }));
    }
    return generateDemoData();
  }, [data]);

  const minValue = Math.min(...chartData.map(d => d.value ?? d.equity ?? 0));
  const maxValue = Math.max(...chartData.map(d => d.value ?? d.equity ?? 0));
  const firstValue = chartData[0]?.value ?? chartData[0]?.equity ?? 0;
  const lastValue = chartData[chartData.length - 1]?.value ?? chartData[chartData.length - 1]?.equity ?? 0;
  const isPositive = lastValue >= firstValue;

  const formatDate = (timestamp: number) => {
    return new Date(timestamp).toLocaleDateString('en-US', { 
      month: 'short', 
      day: 'numeric' 
    });
  };

  // eslint-disable-next-line @typescript-eslint/no-unused-vars
  const CustomTooltip = ({ active, payload, label: _label }: any) => {
    if (active && payload && payload.length) {
      const data = payload[0].payload;
      const value = data.value ?? data.equity ?? 0;
      const pnl = data.pnl ?? 0;
      const pnlPercent = data.pnlPercent;
      
      return (
        <div className="bg-gray-800 border border-gray-700 rounded-lg p-3 shadow-lg">
          <p className="text-gray-400 text-xs mb-1">
            {formatDate(data.timestamp)}
          </p>
          <p className="text-white font-medium">
            Equity: {formatCurrency(value)}
          </p>
          <p className={`text-sm ${pnl >= 0 ? 'text-green-500' : 'text-red-500'}`}>
            PnL: {pnl >= 0 ? '+' : ''}{formatCurrency(pnl)}
            {pnlPercent !== undefined && (
              <span className="ml-1">({pnlPercent >= 0 ? '+' : ''}{pnlPercent.toFixed(2)}%)</span>
            )}
          </p>
          {data.balance !== undefined && (
            <p className="text-gray-400 text-xs mt-1">
              Balance: {formatCurrency(data.balance)}
            </p>
          )}
        </div>
      );
    }
    return null;
  };

  return (
    <div className="w-full" style={{ height, minHeight: height }}>
      <ResponsiveContainer width="100%" height={height} minHeight={height}>
        <AreaChart
          data={chartData}
          margin={{ top: 10, right: 10, left: 0, bottom: 0 }}
        >
          <defs>
            <linearGradient id="colorValue" x1="0" y1="0" x2="0" y2="1">
              <stop 
                offset="5%" 
                stopColor={isPositive ? '#22c55e' : '#ef4444'} 
                stopOpacity={0.3}
              />
              <stop 
                offset="95%" 
                stopColor={isPositive ? '#22c55e' : '#ef4444'} 
                stopOpacity={0}
              />
            </linearGradient>
          </defs>
          <CartesianGrid strokeDasharray="3 3" stroke="#374151" vertical={false} />
          <XAxis 
            dataKey="timestamp" 
            tickFormatter={formatDate}
            stroke="#6b7280"
            tick={{ fill: '#9ca3af', fontSize: 12 }}
            axisLine={{ stroke: '#374151' }}
          />
          <YAxis 
            domain={[minValue * 0.99, maxValue * 1.01]}
            tickFormatter={(value) => `$${(value / 1000).toFixed(1)}k`}
            stroke="#6b7280"
            tick={{ fill: '#9ca3af', fontSize: 12 }}
            axisLine={{ stroke: '#374151' }}
            width={60}
          />
          <Tooltip content={<CustomTooltip />} />
          <Area
            type="monotone"
            dataKey="value"
            stroke={isPositive ? '#22c55e' : '#ef4444'}
            strokeWidth={2}
            fillOpacity={1}
            fill="url(#colorValue)"
          />
        </AreaChart>
      </ResponsiveContainer>
    </div>
  );
}

// Equity Curve Chart
interface EquityCurveProps {
  data?: Array<{ timestamp: number; equity: number }>;
  height?: number;
}

export function EquityCurve({ data, height = 200 }: EquityCurveProps) {
  const chartData = useMemo(() => {
    if (data && data.length > 0) return data;
    // Generate demo equity curve
    const demo: Array<{ timestamp: number; equity: number }> = [];
    let equity = 10000;
    const now = Date.now();
    
    for (let i = 100; i >= 0; i--) {
      equity += (Math.random() - 0.45) * 50;
      demo.push({
        timestamp: now - i * 60 * 60 * 1000,
        equity: Math.max(9000, equity),
      });
    }
    return demo;
  }, [data]);

  return (
    <div className="w-full" style={{ height, minHeight: height }}>
      <ResponsiveContainer width="100%" height={height} minHeight={height}>
        <AreaChart data={chartData} margin={{ top: 5, right: 5, left: 0, bottom: 0 }}>
          <defs>
            <linearGradient id="equityGradient" x1="0" y1="0" x2="0" y2="1">
              <stop offset="5%" stopColor="#3b82f6" stopOpacity={0.3} />
              <stop offset="95%" stopColor="#3b82f6" stopOpacity={0} />
            </linearGradient>
          </defs>
          <Area
            type="monotone"
            dataKey="equity"
            stroke="#3b82f6"
            strokeWidth={1.5}
            fillOpacity={1}
            fill="url(#equityGradient)"
          />
        </AreaChart>
      </ResponsiveContainer>
    </div>
  );
}
