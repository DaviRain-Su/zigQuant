// ============================================================================
// Candlestick Chart with Trade Markers
// ============================================================================

import { useMemo } from 'react';
import {
  ComposedChart,
  Bar,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
  Scatter,
} from 'recharts';
import { formatCurrency } from '../../lib/utils';

// Types
export interface CandleData {
  timestamp: number;
  open: number;
  high: number;
  low: number;
  close: number;
  volume: number;
}

export interface TradeMarker {
  timestamp: number;
  price: number;
  side: 'buy' | 'sell';
  size?: number;
  pnl?: number;
}

interface CandlestickChartProps {
  candles: CandleData[];
  trades?: TradeMarker[];
  height?: number;
  showVolume?: boolean;
}

// Trade marker shape
const TradeMarkerShape = (props: any) => {
  const { cx, cy, payload } = props;
  const isBuy = payload.side === 'buy';
  const color = isBuy ? '#22c55e' : '#ef4444';
  const size = 8;
  
  if (isBuy) {
    // Triangle pointing up for buy
    return (
      <polygon
        points={`${cx},${cy - size} ${cx - size},${cy + size} ${cx + size},${cy + size}`}
        fill={color}
        stroke="#fff"
        strokeWidth={1}
      />
    );
  } else {
    // Triangle pointing down for sell
    return (
      <polygon
        points={`${cx},${cy + size} ${cx - size},${cy - size} ${cx + size},${cy - size}`}
        fill={color}
        stroke="#fff"
        strokeWidth={1}
      />
    );
  }
};

export function CandlestickChart({ 
  candles, 
  trades = [], 
  height = 400,
  // eslint-disable-next-line @typescript-eslint/no-unused-vars
  showVolume: _showVolume = true 
}: CandlestickChartProps) {
  
  // Process data for chart
  const chartData = useMemo(() => {
    return candles.map(candle => ({
      ...candle,
      // For bar chart, we need a range value
      range: [candle.low, candle.high],
      body: [Math.min(candle.open, candle.close), Math.max(candle.open, candle.close)],
      isGreen: candle.close >= candle.open,
    }));
  }, [candles]);

  // Merge trades into chart data
  const tradesWithData = useMemo(() => {
    return trades.map(trade => ({
      ...trade,
      // Find matching candle for y position
      y: trade.price,
    }));
  }, [trades]);

  // Calculate price range
  const priceRange = useMemo(() => {
    if (candles.length === 0) return { min: 0, max: 100 };
    const prices = candles.flatMap(c => [c.high, c.low]);
    const min = Math.min(...prices);
    const max = Math.max(...prices);
    const padding = (max - min) * 0.05;
    return { min: min - padding, max: max + padding };
  }, [candles]);

  // Format date for x-axis
  const formatDate = (timestamp: number) => {
    const date = new Date(timestamp);
    return date.toLocaleDateString('en-US', { 
      month: 'short', 
      day: 'numeric',
      hour: '2-digit',
      minute: '2-digit'
    });
  };

  // Custom tooltip
  const CustomTooltip = ({ active, payload }: any) => {
    if (active && payload && payload.length) {
      const data = payload[0].payload;
      return (
        <div className="bg-gray-800 border border-gray-700 rounded-lg p-3 shadow-lg">
          <p className="text-gray-400 text-xs mb-2">
            {formatDate(data.timestamp)}
          </p>
          <div className="grid grid-cols-2 gap-x-4 gap-y-1 text-sm">
            <span className="text-gray-500">Open:</span>
            <span className="text-white">{formatCurrency(data.open)}</span>
            <span className="text-gray-500">High:</span>
            <span className="text-green-500">{formatCurrency(data.high)}</span>
            <span className="text-gray-500">Low:</span>
            <span className="text-red-500">{formatCurrency(data.low)}</span>
            <span className="text-gray-500">Close:</span>
            <span className={data.isGreen ? 'text-green-500' : 'text-red-500'}>
              {formatCurrency(data.close)}
            </span>
            <span className="text-gray-500">Volume:</span>
            <span className="text-gray-300">{data.volume.toFixed(2)}</span>
          </div>
        </div>
      );
    }
    return null;
  };

  if (candles.length === 0) {
    return (
      <div 
        className="w-full flex items-center justify-center bg-gray-800/50 rounded-lg"
        style={{ height }}
      >
        <p className="text-gray-500">No candle data available</p>
      </div>
    );
  }

  return (
    <div className="w-full" style={{ height, minHeight: height }}>
      <ResponsiveContainer width="100%" height={height}>
        <ComposedChart
          data={chartData}
          margin={{ top: 10, right: 30, left: 0, bottom: 0 }}
        >
          <CartesianGrid strokeDasharray="3 3" stroke="#374151" />
          <XAxis 
            dataKey="timestamp" 
            tickFormatter={(ts) => new Date(ts).toLocaleDateString('en-US', { month: 'short', day: 'numeric' })}
            stroke="#6b7280"
            tick={{ fill: '#9ca3af', fontSize: 11 }}
            axisLine={{ stroke: '#374151' }}
          />
          <YAxis 
            domain={[priceRange.min, priceRange.max]}
            tickFormatter={(value) => `$${value.toLocaleString()}`}
            stroke="#6b7280"
            tick={{ fill: '#9ca3af', fontSize: 11 }}
            axisLine={{ stroke: '#374151' }}
            width={80}
          />
          <Tooltip content={<CustomTooltip />} />
          
          {/* Candlesticks as bars showing high-low range */}
          <Bar
            dataKey="high"
            fill="transparent"
            shape={(props: any) => {
              const { x, width, payload } = props;
              const isGreen = payload.close >= payload.open;
              const color = isGreen ? '#22c55e' : '#ef4444';
              const candleWidth = Math.max(width * 0.6, 2);
              const xPos = x + (width - candleWidth) / 2;
              
              // Calculate y positions based on domain
              const yScale = height / (priceRange.max - priceRange.min);
              const highY = (priceRange.max - payload.high) * yScale + 10;
              const lowY = (priceRange.max - payload.low) * yScale + 10;
              const openY = (priceRange.max - payload.open) * yScale + 10;
              const closeY = (priceRange.max - payload.close) * yScale + 10;
              const bodyTop = Math.min(openY, closeY);
              const bodyHeight = Math.max(Math.abs(closeY - openY), 1);
              
              return (
                <g>
                  {/* Wick */}
                  <line
                    x1={xPos + candleWidth / 2}
                    y1={highY}
                    x2={xPos + candleWidth / 2}
                    y2={lowY}
                    stroke={color}
                    strokeWidth={1}
                  />
                  {/* Body */}
                  <rect
                    x={xPos}
                    y={bodyTop}
                    width={candleWidth}
                    height={bodyHeight}
                    fill={color}
                    stroke={color}
                  />
                </g>
              );
            }}
          />

          {/* Trade markers */}
          {tradesWithData.length > 0 && (
            <Scatter
              data={tradesWithData}
              dataKey="price"
              shape={<TradeMarkerShape />}
            />
          )}
        </ComposedChart>
      </ResponsiveContainer>
    </div>
  );
}

// Simple version for quick display
export function SimpleCandlestickChart({ 
  candles, 
  height = 200 
}: { 
  candles: CandleData[]; 
  height?: number 
}) {
  const priceRange = useMemo(() => {
    if (candles.length === 0) return { min: 0, max: 100 };
    const prices = candles.flatMap(c => [c.high, c.low]);
    const min = Math.min(...prices);
    const max = Math.max(...prices);
    const padding = (max - min) * 0.02;
    return { min: min - padding, max: max + padding };
  }, [candles]);

  if (candles.length === 0) {
    return (
      <div 
        className="w-full flex items-center justify-center bg-gray-800/50 rounded-lg"
        style={{ height }}
      >
        <p className="text-gray-500 text-sm">No data</p>
      </div>
    );
  }

  // For simple chart, just show price line
  return (
    <div className="w-full" style={{ height, minHeight: height }}>
      <ResponsiveContainer width="100%" height={height}>
        <ComposedChart data={candles} margin={{ top: 5, right: 5, left: 0, bottom: 0 }}>
          <YAxis domain={[priceRange.min, priceRange.max]} hide />
          <Bar
            dataKey="close"
            fill="#3b82f6"
            shape={(props: any) => {
              const { x, width, payload, y } = props;
              const isGreen = payload.close >= payload.open;
              return (
                <rect
                  x={x}
                  y={y}
                  width={Math.max(width * 0.8, 1)}
                  height={2}
                  fill={isGreen ? '#22c55e' : '#ef4444'}
                />
              );
            }}
          />
        </ComposedChart>
      </ResponsiveContainer>
    </div>
  );
}

export default CandlestickChart;
