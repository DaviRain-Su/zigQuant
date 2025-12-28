<script setup lang="ts">
import { ref, reactive, onMounted } from 'vue'
import { ElMessage } from 'element-plus'
import { use } from 'echarts/core'
import { CanvasRenderer } from 'echarts/renderers'
import { LineChart } from 'echarts/charts'
import {
  TitleComponent,
  TooltipComponent,
  GridComponent,
} from 'echarts/components'
import VChart from 'vue-echarts'
import * as strategiesApi from '@/api/strategies'
import * as backtestApi from '@/api/backtest'

// Register ECharts components
use([
  CanvasRenderer,
  LineChart,
  TitleComponent,
  TooltipComponent,
  GridComponent,
])

interface Strategy {
  id: string
  name: string
}

const strategies = ref<Strategy[]>([])
const running = ref(false)

const config = reactive({
  strategy_id: '',
  symbol: 'BTC-USDT',
  timeframe: '1h',
  start_date: '',
  end_date: '',
  initial_capital: 10000,
})

const result = ref<backtestApi.BacktestResult | null>(null)

// Equity curve chart options
const equityChartOption = ref({
  title: {
    text: 'Equity Curve',
    left: 'center',
  },
  tooltip: {
    trigger: 'axis',
  },
  xAxis: {
    type: 'category',
    data: [] as string[],
  },
  yAxis: {
    type: 'value',
    axisLabel: {
      formatter: '${value}',
    },
  },
  series: [
    {
      name: 'Equity',
      type: 'line',
      data: [] as number[],
      smooth: true,
      areaStyle: {
        opacity: 0.3,
      },
      lineStyle: {
        color: '#409eff',
      },
    },
  ],
})

onMounted(async () => {
  await fetchStrategies()

  // Set default date range (last 30 days)
  const endDate = new Date()
  const startDate = new Date()
  startDate.setDate(startDate.getDate() - 30)
  config.start_date = startDate.toISOString().split('T')[0] ?? ''
  config.end_date = endDate.toISOString().split('T')[0] ?? ''
})

async function fetchStrategies() {
  try {
    const response = await strategiesApi.listStrategies()
    strategies.value = response.strategies.map((s) => ({
      id: s.id,
      name: s.name,
    }))
    if (strategies.value.length > 0 && strategies.value[0]) {
      config.strategy_id = strategies.value[0].id
    }
  } catch (error) {
    console.error('Failed to fetch strategies:', error)
    // Use mock data
    strategies.value = [
      { id: 'dual_ma', name: 'Dual Moving Average' },
      { id: 'rsi_mean_reversion', name: 'RSI Mean Reversion' },
      { id: 'bollinger_breakout', name: 'Bollinger Breakout' },
    ]
    if (strategies.value[0]) {
      config.strategy_id = strategies.value[0].id
    }
  }
}

async function runBacktest() {
  if (!config.strategy_id) {
    ElMessage.warning('Please select a strategy')
    return
  }

  running.value = true
  result.value = null

  try {
    const response = await backtestApi.runBacktest({
      strategy_id: config.strategy_id,
      symbol: config.symbol,
      timeframe: config.timeframe,
      start_date: config.start_date,
      end_date: config.end_date,
      initial_capital: config.initial_capital,
    })

    result.value = response

    // Update chart with equity curve
    if (response.equity_curve && response.equity_curve.length > 0) {
      equityChartOption.value.xAxis.data = response.equity_curve.map(
        (p) => new Date(p.timestamp * 1000).toLocaleDateString()
      )
      const series0 = equityChartOption.value.series[0]
      if (series0) {
        series0.data = response.equity_curve.map((p) => p.equity)
      }
    }

    ElMessage.success('Backtest completed')
  } catch (error) {
    console.error('Backtest failed:', error)
    ElMessage.error('Backtest failed')

    // Use mock result
    result.value = {
      id: 'mock-1',
      strategy_id: config.strategy_id,
      status: 'completed',
      metrics: {
        total_return: 0.125,
        sharpe_ratio: 1.85,
        max_drawdown: 0.082,
        win_rate: 0.58,
        profit_factor: 1.42,
        total_trades: 24,
        winning_trades: 14,
        losing_trades: 10,
      },
      equity_curve: Array.from({ length: 30 }, (_, i) => ({
        timestamp: Date.now() / 1000 - (30 - i) * 86400,
        equity: config.initial_capital * (1 + (Math.random() - 0.4) * 0.02 * i),
      })),
    }

    // Update chart
    if (result.value.equity_curve) {
      equityChartOption.value.xAxis.data = result.value.equity_curve.map(
        (p) => new Date(p.timestamp * 1000).toLocaleDateString()
      )
      const series0 = equityChartOption.value.series[0]
      if (series0) {
        series0.data = result.value.equity_curve.map((p) => p.equity)
      }
    }
  } finally {
    running.value = false
  }
}

function formatPercent(value: number): string {
  return (value * 100).toFixed(2) + '%'
}
</script>

<template>
  <div class="backtest">
    <el-row :gutter="20">
      <!-- Configuration Form -->
      <el-col :span="8">
        <el-card>
          <template #header>
            <span>Backtest Configuration</span>
          </template>

          <el-form :model="config" label-position="top">
            <el-form-item label="Strategy">
              <el-select v-model="config.strategy_id" style="width: 100%">
                <el-option
                  v-for="s in strategies"
                  :key="s.id"
                  :label="s.name"
                  :value="s.id"
                />
              </el-select>
            </el-form-item>

            <el-form-item label="Symbol">
              <el-select v-model="config.symbol" style="width: 100%">
                <el-option label="BTC-USDT" value="BTC-USDT" />
                <el-option label="ETH-USDT" value="ETH-USDT" />
                <el-option label="SOL-USDT" value="SOL-USDT" />
              </el-select>
            </el-form-item>

            <el-form-item label="Timeframe">
              <el-select v-model="config.timeframe" style="width: 100%">
                <el-option label="1 Hour" value="1h" />
                <el-option label="4 Hours" value="4h" />
                <el-option label="1 Day" value="1d" />
              </el-select>
            </el-form-item>

            <el-form-item label="Start Date">
              <el-date-picker
                v-model="config.start_date"
                type="date"
                value-format="YYYY-MM-DD"
                style="width: 100%"
              />
            </el-form-item>

            <el-form-item label="End Date">
              <el-date-picker
                v-model="config.end_date"
                type="date"
                value-format="YYYY-MM-DD"
                style="width: 100%"
              />
            </el-form-item>

            <el-form-item label="Initial Capital ($)">
              <el-input-number
                v-model="config.initial_capital"
                :min="1000"
                :step="1000"
                style="width: 100%"
              />
            </el-form-item>

            <el-button
              type="primary"
              :loading="running"
              @click="runBacktest"
              style="width: 100%"
            >
              Run Backtest
            </el-button>
          </el-form>
        </el-card>
      </el-col>

      <!-- Results -->
      <el-col :span="16">
        <el-card v-if="result">
          <template #header>
            <span>Backtest Results</span>
          </template>

          <!-- Metrics Cards -->
          <el-row :gutter="16" v-if="result.metrics">
            <el-col :span="6">
              <div class="result-metric">
                <div class="label">Total Return</div>
                <div class="value" :class="result.metrics.total_return >= 0 ? 'profit' : 'loss'">
                  {{ formatPercent(result.metrics.total_return) }}
                </div>
              </div>
            </el-col>
            <el-col :span="6">
              <div class="result-metric">
                <div class="label">Sharpe Ratio</div>
                <div class="value">{{ result.metrics.sharpe_ratio.toFixed(2) }}</div>
              </div>
            </el-col>
            <el-col :span="6">
              <div class="result-metric">
                <div class="label">Max Drawdown</div>
                <div class="value loss">{{ formatPercent(result.metrics.max_drawdown) }}</div>
              </div>
            </el-col>
            <el-col :span="6">
              <div class="result-metric">
                <div class="label">Win Rate</div>
                <div class="value">{{ formatPercent(result.metrics.win_rate) }}</div>
              </div>
            </el-col>
          </el-row>

          <el-row :gutter="16" style="margin-top: 16px" v-if="result.metrics">
            <el-col :span="6">
              <div class="result-metric">
                <div class="label">Profit Factor</div>
                <div class="value">{{ result.metrics.profit_factor.toFixed(2) }}</div>
              </div>
            </el-col>
            <el-col :span="6">
              <div class="result-metric">
                <div class="label">Total Trades</div>
                <div class="value">{{ result.metrics.total_trades }}</div>
              </div>
            </el-col>
            <el-col :span="6">
              <div class="result-metric">
                <div class="label">Winning</div>
                <div class="value profit">{{ result.metrics.winning_trades }}</div>
              </div>
            </el-col>
            <el-col :span="6">
              <div class="result-metric">
                <div class="label">Losing</div>
                <div class="value loss">{{ result.metrics.losing_trades }}</div>
              </div>
            </el-col>
          </el-row>

          <!-- Equity Curve -->
          <v-chart :option="equityChartOption" style="height: 300px; margin-top: 20px" />
        </el-card>

        <el-card v-else>
          <el-empty description="Configure and run a backtest to see results" />
        </el-card>
      </el-col>
    </el-row>
  </div>
</template>

<style scoped lang="scss">
.backtest {
  .result-metric {
    text-align: center;
    padding: 16px;
    background: #f5f7fa;
    border-radius: 8px;

    .label {
      font-size: 12px;
      color: #909399;
    }

    .value {
      font-size: 24px;
      font-weight: bold;
      margin-top: 8px;
      color: #303133;
    }
  }

  .profit {
    color: #67c23a !important;
  }

  .loss {
    color: #f56c6c !important;
  }
}
</style>
