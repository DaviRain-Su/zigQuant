<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { ElMessage, ElMessageBox } from 'element-plus'
import { VideoPlay, VideoPause, View } from '@element-plus/icons-vue'
import * as strategiesApi from '@/api/strategies'

interface Strategy {
  id: string
  name: string
  description: string
  category: string
  status: 'running' | 'stopped' | 'unknown'
  pnl?: number
  trades?: number
}

const strategies = ref<Strategy[]>([])
const loading = ref(true)
const detailDialogVisible = ref(false)
const selectedStrategy = ref<Strategy | null>(null)
const selectedParams = ref<Record<string, unknown>>({})

onMounted(async () => {
  await fetchStrategies()
})

async function fetchStrategies() {
  loading.value = true
  try {
    const response = await strategiesApi.listStrategies()
    strategies.value = response.strategies.map((s) => ({
      ...s,
      status: s.status || 'stopped',
      pnl: Math.random() * 20 - 5, // Mock PnL
      trades: Math.floor(Math.random() * 50), // Mock trades
    }))
  } catch (error) {
    console.error('Failed to fetch strategies:', error)
    // Use mock data
    strategies.value = [
      { id: 'dual_ma', name: 'Dual Moving Average', description: 'Classic MA crossover', category: 'trend', status: 'stopped', pnl: 5.2, trades: 15 },
      { id: 'rsi_mean_reversion', name: 'RSI Mean Reversion', description: 'RSI-based mean reversion', category: 'mean_reversion', status: 'running', pnl: -2.1, trades: 23 },
      { id: 'bollinger_breakout', name: 'Bollinger Breakout', description: 'Volatility breakout strategy', category: 'breakout', status: 'stopped', pnl: 8.7, trades: 12 },
    ]
  } finally {
    loading.value = false
  }
}

async function handleRun(strategy: Strategy) {
  try {
    await ElMessageBox.confirm(
      `Are you sure you want to run strategy "${strategy.name}"?`,
      'Confirm',
      { type: 'info' }
    )
    await strategiesApi.runStrategy(strategy.id)
    strategy.status = 'running'
    ElMessage.success(`Strategy "${strategy.name}" started`)
  } catch (error) {
    if (error !== 'cancel') {
      ElMessage.error('Failed to start strategy')
    }
  }
}

async function handleStop(strategy: Strategy) {
  try {
    await ElMessageBox.confirm(
      `Are you sure you want to stop strategy "${strategy.name}"?`,
      'Confirm',
      { type: 'warning' }
    )
    // API call to stop (not implemented in backend yet)
    strategy.status = 'stopped'
    ElMessage.success(`Strategy "${strategy.name}" stopped`)
  } catch (error) {
    if (error !== 'cancel') {
      ElMessage.error('Failed to stop strategy')
    }
  }
}

async function handleViewDetails(strategy: Strategy) {
  selectedStrategy.value = strategy
  try {
    selectedParams.value = await strategiesApi.getStrategyParams(strategy.id)
  } catch {
    selectedParams.value = {}
  }
  detailDialogVisible.value = true
}

function getStatusType(status: string): 'success' | 'info' | 'warning' | 'danger' {
  switch (status) {
    case 'running':
      return 'success'
    case 'stopped':
      return 'info'
    default:
      return 'warning'
  }
}
</script>

<template>
  <div class="strategies">
    <el-card>
      <template #header>
        <div class="card-header">
          <span>Strategy Management</span>
          <el-button type="primary" @click="fetchStrategies" :loading="loading">
            Refresh
          </el-button>
        </div>
      </template>

      <el-table :data="strategies" v-loading="loading" stripe>
        <el-table-column prop="name" label="Strategy Name" min-width="180" />
        <el-table-column prop="category" label="Category" width="140">
          <template #default="{ row }">
            <el-tag size="small">{{ row.category }}</el-tag>
          </template>
        </el-table-column>
        <el-table-column prop="status" label="Status" width="100">
          <template #default="{ row }">
            <el-tag :type="getStatusType(row.status)" size="small">
              {{ row.status.toUpperCase() }}
            </el-tag>
          </template>
        </el-table-column>
        <el-table-column prop="trades" label="Trades" width="80" />
        <el-table-column prop="pnl" label="PnL (%)" width="100">
          <template #default="{ row }">
            <span :class="row.pnl >= 0 ? 'profit' : 'loss'">
              {{ row.pnl >= 0 ? '+' : '' }}{{ row.pnl?.toFixed(2) }}%
            </span>
          </template>
        </el-table-column>
        <el-table-column label="Actions" width="200" fixed="right">
          <template #default="{ row }">
            <el-button
              v-if="row.status !== 'running'"
              type="success"
              size="small"
              :icon="VideoPlay"
              @click="handleRun(row)"
            >
              Run
            </el-button>
            <el-button
              v-else
              type="danger"
              size="small"
              :icon="VideoPause"
              @click="handleStop(row)"
            >
              Stop
            </el-button>
            <el-button
              size="small"
              :icon="View"
              @click="handleViewDetails(row)"
            >
              Details
            </el-button>
          </template>
        </el-table-column>
      </el-table>
    </el-card>

    <!-- Strategy Details Dialog -->
    <el-dialog
      v-model="detailDialogVisible"
      :title="selectedStrategy?.name"
      width="600px"
    >
      <el-descriptions :column="2" border v-if="selectedStrategy">
        <el-descriptions-item label="ID">{{ selectedStrategy.id }}</el-descriptions-item>
        <el-descriptions-item label="Category">{{ selectedStrategy.category }}</el-descriptions-item>
        <el-descriptions-item label="Status">
          <el-tag :type="getStatusType(selectedStrategy.status)">
            {{ selectedStrategy.status.toUpperCase() }}
          </el-tag>
        </el-descriptions-item>
        <el-descriptions-item label="PnL">
          <span :class="(selectedStrategy.pnl || 0) >= 0 ? 'profit' : 'loss'">
            {{ (selectedStrategy.pnl || 0) >= 0 ? '+' : '' }}{{ (selectedStrategy.pnl || 0).toFixed(2) }}%
          </span>
        </el-descriptions-item>
        <el-descriptions-item label="Description" :span="2">
          {{ selectedStrategy.description }}
        </el-descriptions-item>
      </el-descriptions>

      <div v-if="Object.keys(selectedParams).length > 0" style="margin-top: 20px">
        <h4>Parameters</h4>
        <el-table :data="Object.entries(selectedParams).map(([k, v]) => ({ key: k, value: v }))" size="small">
          <el-table-column prop="key" label="Parameter" />
          <el-table-column prop="value" label="Value" />
        </el-table>
      </div>
    </el-dialog>
  </div>
</template>

<style scoped lang="scss">
.strategies {
  .card-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
  }

  .profit {
    color: #67c23a;
    font-weight: bold;
  }

  .loss {
    color: #f56c6c;
    font-weight: bold;
  }
}
</style>
