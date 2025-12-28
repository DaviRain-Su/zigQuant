<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { use } from 'echarts/core'
import { CanvasRenderer } from 'echarts/renderers'
import { LineChart } from 'echarts/charts'
import {
  TitleComponent,
  TooltipComponent,
  GridComponent,
  LegendComponent,
} from 'echarts/components'
import VChart from 'vue-echarts'
import { Wallet, TrendCharts, List, Coin } from '@element-plus/icons-vue'
import api from '@/api'

// Register ECharts components
use([
  CanvasRenderer,
  LineChart,
  TitleComponent,
  TooltipComponent,
  GridComponent,
  LegendComponent,
])

interface MetricData {
  balance: number
  todayPnl: number
  activeStrategies: number
  positions: number
}

const metrics = ref<MetricData>({
  balance: 0,
  todayPnl: 0,
  activeStrategies: 0,
  positions: 0,
})

const loading = ref(true)

// PnL Chart options
const pnlChartOption = ref({
  title: {
    text: 'PnL Trend (7 Days)',
    left: 'center',
  },
  tooltip: {
    trigger: 'axis',
  },
  xAxis: {
    type: 'category',
    data: ['Day 1', 'Day 2', 'Day 3', 'Day 4', 'Day 5', 'Day 6', 'Day 7'],
  },
  yAxis: {
    type: 'value',
    axisLabel: {
      formatter: '${value}',
    },
  },
  series: [
    {
      name: 'PnL',
      type: 'line',
      data: [100, 150, 120, 200, 180, 250, 300],
      smooth: true,
      areaStyle: {
        opacity: 0.3,
      },
      lineStyle: {
        color: '#409eff',
      },
      itemStyle: {
        color: '#409eff',
      },
    },
  ],
})

// Recent trades data
const recentTrades = ref([
  { id: 1, symbol: 'BTC-USDT', side: 'buy', price: 43250.5, quantity: 0.1, pnl: 125.5 },
  { id: 2, symbol: 'ETH-USDT', side: 'sell', price: 2280.0, quantity: 1.5, pnl: -45.2 },
  { id: 3, symbol: 'BTC-USDT', side: 'buy', price: 43100.0, quantity: 0.05, pnl: 67.8 },
])

onMounted(async () => {
  try {
    // Fetch account balance
    const accountRes = await api.get('/account/balance')
    metrics.value.balance = accountRes.data.total_balance || 10000

    // Fetch strategies count
    const strategiesRes = await api.get('/strategies')
    metrics.value.activeStrategies = strategiesRes.data.strategies?.filter(
      (s: { status: string }) => s.status === 'running'
    ).length || 0

    // Fetch positions count
    const positionsRes = await api.get('/positions')
    metrics.value.positions = positionsRes.data.positions?.length || 0

    // Calculate today's PnL (mock)
    metrics.value.todayPnl = 1250.75
  } catch (error) {
    console.error('Failed to fetch dashboard data:', error)
    // Use mock data
    metrics.value = {
      balance: 10000,
      todayPnl: 1250.75,
      activeStrategies: 2,
      positions: 3,
    }
  } finally {
    loading.value = false
  }
})

function formatCurrency(value: number): string {
  return new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: 'USD',
  }).format(value)
}
</script>

<template>
  <div class="dashboard" v-loading="loading">
    <!-- Metrics Cards -->
    <el-row :gutter="20">
      <el-col :span="6">
        <el-card class="metric-card">
          <div class="metric-icon" style="background: #409eff">
            <el-icon :size="24"><Wallet /></el-icon>
          </div>
          <div class="metric-content">
            <div class="metric-value">{{ formatCurrency(metrics.balance) }}</div>
            <div class="metric-label">Account Balance</div>
          </div>
        </el-card>
      </el-col>

      <el-col :span="6">
        <el-card class="metric-card">
          <div class="metric-icon" :style="{ background: metrics.todayPnl >= 0 ? '#67c23a' : '#f56c6c' }">
            <el-icon :size="24"><TrendCharts /></el-icon>
          </div>
          <div class="metric-content">
            <div class="metric-value" :class="metrics.todayPnl >= 0 ? 'profit' : 'loss'">
              {{ metrics.todayPnl >= 0 ? '+' : '' }}{{ formatCurrency(metrics.todayPnl) }}
            </div>
            <div class="metric-label">Today's PnL</div>
          </div>
        </el-card>
      </el-col>

      <el-col :span="6">
        <el-card class="metric-card">
          <div class="metric-icon" style="background: #e6a23c">
            <el-icon :size="24"><List /></el-icon>
          </div>
          <div class="metric-content">
            <div class="metric-value">{{ metrics.activeStrategies }}</div>
            <div class="metric-label">Active Strategies</div>
          </div>
        </el-card>
      </el-col>

      <el-col :span="6">
        <el-card class="metric-card">
          <div class="metric-icon" style="background: #909399">
            <el-icon :size="24"><Coin /></el-icon>
          </div>
          <div class="metric-content">
            <div class="metric-value">{{ metrics.positions }}</div>
            <div class="metric-label">Open Positions</div>
          </div>
        </el-card>
      </el-col>
    </el-row>

    <!-- Charts Row -->
    <el-row :gutter="20" style="margin-top: 20px">
      <el-col :span="16">
        <el-card>
          <v-chart :option="pnlChartOption" style="height: 350px" />
        </el-card>
      </el-col>

      <el-col :span="8">
        <el-card>
          <template #header>
            <span>Recent Trades</span>
          </template>
          <el-table :data="recentTrades" size="small" stripe>
            <el-table-column prop="symbol" label="Symbol" width="100" />
            <el-table-column prop="side" label="Side" width="60">
              <template #default="{ row }">
                <el-tag :type="row.side === 'buy' ? 'success' : 'danger'" size="small">
                  {{ row.side.toUpperCase() }}
                </el-tag>
              </template>
            </el-table-column>
            <el-table-column prop="pnl" label="PnL">
              <template #default="{ row }">
                <span :class="row.pnl >= 0 ? 'profit' : 'loss'">
                  {{ row.pnl >= 0 ? '+' : '' }}{{ row.pnl.toFixed(2) }}
                </span>
              </template>
            </el-table-column>
          </el-table>
        </el-card>
      </el-col>
    </el-row>
  </div>
</template>

<style scoped lang="scss">
.dashboard {
  .metric-card {
    display: flex;
    align-items: center;
    padding: 20px;

    .metric-icon {
      width: 56px;
      height: 56px;
      border-radius: 8px;
      display: flex;
      align-items: center;
      justify-content: center;
      color: #fff;
      margin-right: 16px;
    }

    .metric-content {
      .metric-value {
        font-size: 24px;
        font-weight: bold;
        color: #303133;
      }

      .metric-label {
        font-size: 14px;
        color: #909399;
        margin-top: 4px;
      }
    }
  }

  .profit {
    color: #67c23a;
  }

  .loss {
    color: #f56c6c;
  }
}
</style>
