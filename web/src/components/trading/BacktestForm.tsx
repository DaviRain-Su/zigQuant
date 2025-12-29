// ============================================================================
// Backtest Form Component
// ============================================================================

import { useState } from 'react';
import { X, Play, Settings, Database, Calendar, DollarSign } from 'lucide-react';
import { Button } from '../ui/Button';
import { Input } from '../ui/Input';
import { Select } from '../ui/Select';
import { Card } from '../ui/Card';
import type { BacktestRequest, StrategyType } from '../../types/api';

interface BacktestFormProps {
  onSubmit: (request: BacktestRequest) => void;
  onCancel: () => void;
  isLoading?: boolean;
}

// Strategy options
const STRATEGY_OPTIONS = [
  { value: 'dual_ma', label: 'Dual Moving Average' },
  { value: 'rsi_mean_reversion', label: 'RSI Mean Reversion' },
  { value: 'bollinger_breakout', label: 'Bollinger Breakout' },
  { value: 'grid', label: 'Grid Trading' },
  { value: 'hybrid_ai', label: 'Hybrid AI' },
];

// Timeframe options
const TIMEFRAME_OPTIONS = [
  { value: '1s', label: '1 Second' },
  { value: '1m', label: '1 Minute' },
  { value: '3m', label: '3 Minutes' },
  { value: '5m', label: '5 Minutes' },
  { value: '15m', label: '15 Minutes' },
  { value: '30m', label: '30 Minutes' },
  { value: '1h', label: '1 Hour' },
  { value: '2h', label: '2 Hours' },
  { value: '4h', label: '4 Hours' },
  { value: '6h', label: '6 Hours' },
  { value: '8h', label: '8 Hours' },
  { value: '12h', label: '12 Hours' },
  { value: '1d', label: '1 Day' },
];

// Default strategy parameters
const DEFAULT_PARAMS: Record<StrategyType, Record<string, number>> = {
  dual_ma: {
    short_period: 10,
    long_period: 20,
  },
  rsi_mean_reversion: {
    rsi_period: 14,
    oversold: 30,
    overbought: 70,
  },
  bollinger_breakout: {
    period: 20,
    std_dev: 2.0,
  },
  grid: {
    upper_price: 100000,
    lower_price: 90000,
    grid_count: 20,
    order_size: 0.01,
  },
  hybrid_ai: {
    ai_weight: 0.5,
    technical_weight: 0.5,
  },
};

export function BacktestForm({ onSubmit, onCancel, isLoading }: BacktestFormProps) {
  const [strategy, setStrategy] = useState<StrategyType>('dual_ma');
  const [symbol, setSymbol] = useState('BTCUSDT');
  const [timeframe, setTimeframe] = useState('1h');
  const [startDate, setStartDate] = useState('2024-01-01');
  const [endDate, setEndDate] = useState('2024-12-31');
  const [initialCapital, setInitialCapital] = useState(10000);
  const [params, setParams] = useState<Record<string, number>>(DEFAULT_PARAMS.dual_ma);
  const [showAdvanced, setShowAdvanced] = useState(false);

  // Update params when strategy changes
  const handleStrategyChange = (newStrategy: StrategyType) => {
    setStrategy(newStrategy);
    setParams(DEFAULT_PARAMS[newStrategy] || {});
  };

  // Handle param change
  const handleParamChange = (key: string, value: string) => {
    const numValue = parseFloat(value);
    if (!isNaN(numValue)) {
      setParams(prev => ({ ...prev, [key]: numValue }));
    }
  };

  // Submit form
  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    
    // Backend expects params as a JSON string
    const request: BacktestRequest = {
      strategy,
      symbol,
      timeframe,
      start_date: startDate,
      end_date: endDate,
      initial_capital: initialCapital,
      params: JSON.stringify(params),
    };
    
    onSubmit(request);
  };

  // Render strategy-specific parameters
  const renderStrategyParams = () => {
    const paramConfig: Record<string, { label: string; hint?: string; step?: number }> = {
      // Dual MA
      short_period: { label: 'Short Period', hint: 'Fast moving average period' },
      long_period: { label: 'Long Period', hint: 'Slow moving average period' },
      // RSI
      rsi_period: { label: 'RSI Period', hint: 'RSI calculation period' },
      oversold: { label: 'Oversold Level', hint: 'Buy when RSI below this' },
      overbought: { label: 'Overbought Level', hint: 'Sell when RSI above this' },
      // Bollinger
      period: { label: 'Period', hint: 'Bollinger bands period' },
      std_dev: { label: 'Std Deviation', hint: 'Number of standard deviations', step: 0.1 },
      // Grid
      upper_price: { label: 'Upper Price', hint: 'Grid upper boundary' },
      lower_price: { label: 'Lower Price', hint: 'Grid lower boundary' },
      grid_count: { label: 'Grid Count', hint: 'Number of grid levels' },
      order_size: { label: 'Order Size', hint: 'Size per order', step: 0.001 },
      // AI
      ai_weight: { label: 'AI Weight', hint: 'Weight of AI signals (0-1)', step: 0.1 },
      technical_weight: { label: 'Technical Weight', hint: 'Weight of technical signals (0-1)', step: 0.1 },
    };

    return Object.entries(params).map(([key, value]) => {
      const config = paramConfig[key] || { label: key };
      return (
        <Input
          key={key}
          label={config.label}
          hint={config.hint}
          type="number"
          step={config.step || 1}
          value={value}
          onChange={(e) => handleParamChange(key, e.target.value)}
        />
      );
    });
  };

  return (
    <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-[100] p-4">
      <Card className="w-full max-w-2xl max-h-[90vh] overflow-y-auto">
        <form onSubmit={handleSubmit}>
          {/* Header */}
          <div className="flex items-center justify-between p-4 border-b border-gray-800">
            <div className="flex items-center gap-3">
              <div className="p-2 bg-blue-500/20 rounded-lg">
                <Play className="w-5 h-5 text-blue-500" />
              </div>
              <div>
                <h2 className="text-lg font-semibold text-white">New Backtest</h2>
                <p className="text-sm text-gray-400">Configure and run a strategy backtest</p>
              </div>
            </div>
            <button
              type="button"
              onClick={onCancel}
              className="p-2 hover:bg-gray-800 rounded-lg transition-colors"
            >
              <X className="w-5 h-5 text-gray-400" />
            </button>
          </div>

          {/* Form Content */}
          <div className="p-4 space-y-6">
            {/* Strategy Selection */}
            <div className="space-y-4">
              <div className="flex items-center gap-2 text-sm font-medium text-gray-300">
                <Settings className="w-4 h-4" />
                Strategy Configuration
              </div>
              <div className="grid grid-cols-2 gap-4">
                <Select
                  label="Strategy"
                  options={STRATEGY_OPTIONS}
                  value={strategy}
                  onChange={(e) => handleStrategyChange(e.target.value as StrategyType)}
                />
                <Input
                  label="Symbol"
                  value={symbol}
                  onChange={(e) => setSymbol(e.target.value.toUpperCase())}
                  placeholder="BTCUSDT"
                />
              </div>
            </div>

            {/* Data Configuration */}
            <div className="space-y-4">
              <div className="flex items-center gap-2 text-sm font-medium text-gray-300">
                <Database className="w-4 h-4" />
                Data Configuration
              </div>
              <div className="grid grid-cols-3 gap-4">
                <Select
                  label="Timeframe"
                  options={TIMEFRAME_OPTIONS}
                  value={timeframe}
                  onChange={(e) => setTimeframe(e.target.value)}
                />
                <Input
                  label="Start Date"
                  type="date"
                  value={startDate}
                  onChange={(e) => setStartDate(e.target.value)}
                  leftIcon={<Calendar className="w-4 h-4" />}
                />
                <Input
                  label="End Date"
                  type="date"
                  value={endDate}
                  onChange={(e) => setEndDate(e.target.value)}
                  leftIcon={<Calendar className="w-4 h-4" />}
                />
              </div>
            </div>

            {/* Capital Configuration */}
            <div className="space-y-4">
              <div className="flex items-center gap-2 text-sm font-medium text-gray-300">
                <DollarSign className="w-4 h-4" />
                Capital Configuration
              </div>
              <Input
                label="Initial Capital (USDT)"
                type="number"
                value={initialCapital}
                onChange={(e) => setInitialCapital(parseFloat(e.target.value) || 10000)}
                leftIcon={<DollarSign className="w-4 h-4" />}
              />
            </div>

            {/* Advanced Parameters */}
            <div className="space-y-4">
              <button
                type="button"
                onClick={() => setShowAdvanced(!showAdvanced)}
                className="flex items-center gap-2 text-sm font-medium text-blue-500 hover:text-blue-400"
              >
                <Settings className="w-4 h-4" />
                {showAdvanced ? 'Hide' : 'Show'} Strategy Parameters
              </button>
              
              {showAdvanced && (
                <div className="p-4 bg-gray-800/50 rounded-lg space-y-4">
                  <div className="grid grid-cols-2 gap-4">
                    {renderStrategyParams()}
                  </div>
                </div>
              )}
            </div>
          </div>

          {/* Footer */}
          <div className="flex items-center justify-end gap-3 p-4 border-t border-gray-800">
            <Button type="button" variant="ghost" onClick={onCancel}>
              Cancel
            </Button>
            <Button 
              type="submit" 
              icon={<Play className="w-4 h-4" />}
              loading={isLoading}
            >
              Run Backtest
            </Button>
          </div>
        </form>
      </Card>
    </div>
  );
}
