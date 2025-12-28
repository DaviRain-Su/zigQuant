# Web Dashboard - 实现细节

> 深入了解内部实现

**最后更新**: 2025-12-28

---

## 架构概述

```
┌─────────────────────────────────────────────────────────────┐
│                    Dashboard Architecture                    │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌─────────────────────────────────────────────────────┐    │
│  │                    Vue 3 App                         │    │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────────────────┐  │    │
│  │  │ Views   │  │ Stores  │  │    Components       │  │    │
│  │  │         │  │ (Pinia) │  │                     │  │    │
│  │  └────┬────┘  └────┬────┘  └─────────────────────┘  │    │
│  │       │            │                                 │    │
│  │       ▼            ▼                                 │    │
│  │  ┌─────────────────────────────────────────────┐    │    │
│  │  │              API Layer                       │    │    │
│  │  │    ┌──────────┐    ┌──────────────────┐     │    │    │
│  │  │    │  Axios   │    │    WebSocket     │     │    │    │
│  │  │    │  (REST)  │    │   (Real-time)    │     │    │    │
│  │  │    └────┬─────┘    └────────┬─────────┘     │    │    │
│  │  └─────────│───────────────────│───────────────┘    │    │
│  └────────────│───────────────────│────────────────────┘    │
│               │                   │                          │
│               ▼                   ▼                          │
│  ┌─────────────────────────────────────────────────────┐    │
│  │              zigQuant API Server                     │    │
│  │         http://localhost:8080/api/v1                 │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## 项目配置

### vite.config.ts

```typescript
import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import { resolve } from 'path'

export default defineConfig({
  plugins: [vue()],
  resolve: {
    alias: {
      '@': resolve(__dirname, 'src'),
    },
  },
  server: {
    port: 5173,
    proxy: {
      '/api': {
        target: 'http://localhost:8080',
        changeOrigin: true,
      },
      '/ws': {
        target: 'ws://localhost:8080',
        ws: true,
      },
    },
  },
  build: {
    outDir: 'dist',
    assetsDir: 'assets',
    sourcemap: false,
    minify: 'terser',
    rollupOptions: {
      output: {
        manualChunks: {
          'vendor': ['vue', 'vue-router', 'pinia'],
          'ui': ['element-plus'],
          'charts': ['echarts'],
        },
      },
    },
  },
})
```

### tsconfig.json

```json
{
  "compilerOptions": {
    "target": "ES2020",
    "useDefineForClassFields": true,
    "module": "ESNext",
    "lib": ["ES2020", "DOM", "DOM.Iterable"],
    "skipLibCheck": true,
    "moduleResolution": "bundler",
    "allowImportingTsExtensions": true,
    "resolveJsonModule": true,
    "isolatedModules": true,
    "noEmit": true,
    "jsx": "preserve",
    "strict": true,
    "noUnusedLocals": true,
    "noUnusedParameters": true,
    "noFallthroughCasesInSwitch": true,
    "paths": {
      "@/*": ["./src/*"]
    }
  },
  "include": ["src/**/*.ts", "src/**/*.tsx", "src/**/*.vue"],
  "references": [{ "path": "./tsconfig.node.json" }]
}
```

---

## 状态管理

### Auth Store

```typescript
// stores/auth.ts
import { defineStore } from 'pinia'
import { ref, computed } from 'vue'
import { login as apiLogin, logout as apiLogout, refreshToken } from '@/api/auth'

export const useAuthStore = defineStore('auth', () => {
  const token = ref<string | null>(localStorage.getItem('token'))
  const user = ref<User | null>(null)

  const isAuthenticated = computed(() => !!token.value)

  async function login(username: string, password: string) {
    const response = await apiLogin(username, password)
    token.value = response.token
    user.value = response.user
    localStorage.setItem('token', response.token)
  }

  async function logout() {
    await apiLogout()
    token.value = null
    user.value = null
    localStorage.removeItem('token')
  }

  async function refresh() {
    if (!token.value) return
    try {
      const response = await refreshToken()
      token.value = response.token
      localStorage.setItem('token', response.token)
    } catch {
      await logout()
    }
  }

  return { token, user, isAuthenticated, login, logout, refresh }
})

interface User {
  id: string
  username: string
  role: string
}
```

### Trading Store

```typescript
// stores/trading.ts
import { defineStore } from 'pinia'
import { ref, computed } from 'vue'
import * as api from '@/api/trading'

export const useTradingStore = defineStore('trading', () => {
  // State
  const positions = ref<Position[]>([])
  const orders = ref<Order[]>([])
  const balance = ref<Balance | null>(null)

  // Computed
  const totalPnL = computed(() =>
    positions.value.reduce((sum, p) => sum + p.unrealizedPnL, 0)
  )

  const openOrdersCount = computed(() =>
    orders.value.filter(o => o.status === 'open').length
  )

  // Actions
  async function fetchPositions() {
    positions.value = await api.getPositions()
  }

  async function fetchOrders() {
    orders.value = await api.getOrders()
  }

  async function fetchBalance() {
    balance.value = await api.getBalance()
  }

  async function createOrder(order: OrderRequest) {
    const newOrder = await api.createOrder(order)
    orders.value.unshift(newOrder)
    return newOrder
  }

  async function cancelOrder(orderId: string) {
    await api.cancelOrder(orderId)
    const index = orders.value.findIndex(o => o.id === orderId)
    if (index !== -1) {
      orders.value[index].status = 'cancelled'
    }
  }

  // WebSocket updates
  function updatePosition(position: Position) {
    const index = positions.value.findIndex(p => p.symbol === position.symbol)
    if (index !== -1) {
      positions.value[index] = position
    } else {
      positions.value.push(position)
    }
  }

  function updateOrder(order: Order) {
    const index = orders.value.findIndex(o => o.id === order.id)
    if (index !== -1) {
      orders.value[index] = order
    } else {
      orders.value.unshift(order)
    }
  }

  return {
    positions,
    orders,
    balance,
    totalPnL,
    openOrdersCount,
    fetchPositions,
    fetchOrders,
    fetchBalance,
    createOrder,
    cancelOrder,
    updatePosition,
    updateOrder,
  }
})
```

---

## 路由配置

```typescript
// router/index.ts
import { createRouter, createWebHistory } from 'vue-router'
import { useAuthStore } from '@/stores/auth'

const routes = [
  {
    path: '/login',
    name: 'Login',
    component: () => import('@/views/Login.vue'),
    meta: { public: true },
  },
  {
    path: '/',
    component: () => import('@/layouts/MainLayout.vue'),
    children: [
      {
        path: '',
        name: 'Dashboard',
        component: () => import('@/views/Dashboard.vue'),
      },
      {
        path: 'strategies',
        name: 'Strategies',
        component: () => import('@/views/Strategies.vue'),
      },
      {
        path: 'backtest',
        name: 'Backtest',
        component: () => import('@/views/Backtest.vue'),
      },
      {
        path: 'orders',
        name: 'Orders',
        component: () => import('@/views/Orders.vue'),
      },
      {
        path: 'positions',
        name: 'Positions',
        component: () => import('@/views/Positions.vue'),
      },
      {
        path: 'alerts',
        name: 'Alerts',
        component: () => import('@/views/Alerts.vue'),
      },
    ],
  },
]

const router = createRouter({
  history: createWebHistory(),
  routes,
})

// 路由守卫
router.beforeEach((to, from, next) => {
  const auth = useAuthStore()

  if (to.meta.public) {
    next()
  } else if (!auth.isAuthenticated) {
    next('/login')
  } else {
    next()
  }
})

export default router
```

---

## API 客户端

### HTTP 客户端

```typescript
// api/client.ts
import axios, { AxiosError } from 'axios'
import { useAuthStore } from '@/stores/auth'
import router from '@/router'

const client = axios.create({
  baseURL: '/api/v1',
  timeout: 10000,
  headers: {
    'Content-Type': 'application/json',
  },
})

// 请求拦截器
client.interceptors.request.use((config) => {
  const auth = useAuthStore()
  if (auth.token) {
    config.headers.Authorization = `Bearer ${auth.token}`
  }
  return config
})

// 响应拦截器
client.interceptors.response.use(
  (response) => response,
  async (error: AxiosError) => {
    if (error.response?.status === 401) {
      const auth = useAuthStore()
      await auth.logout()
      router.push('/login')
    }
    return Promise.reject(error)
  }
)

export default client
```

### WebSocket 管理

```typescript
// api/websocket.ts
import { ref, onMounted, onUnmounted } from 'vue'
import { useAuthStore } from '@/stores/auth'
import { useTradingStore } from '@/stores/trading'

class WebSocketManager {
  private ws: WebSocket | null = null
  private reconnectTimer: number | null = null
  private reconnectAttempts = 0
  private maxReconnectAttempts = 5

  connected = ref(false)

  connect() {
    const auth = useAuthStore()
    if (!auth.token) return

    const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:'
    const host = window.location.host
    this.ws = new WebSocket(`${protocol}//${host}/ws?token=${auth.token}`)

    this.ws.onopen = () => {
      console.log('WebSocket connected')
      this.connected.value = true
      this.reconnectAttempts = 0
    }

    this.ws.onmessage = (event) => {
      this.handleMessage(JSON.parse(event.data))
    }

    this.ws.onclose = () => {
      console.log('WebSocket disconnected')
      this.connected.value = false
      this.scheduleReconnect()
    }

    this.ws.onerror = (error) => {
      console.error('WebSocket error:', error)
    }
  }

  private handleMessage(message: WebSocketMessage) {
    const trading = useTradingStore()

    switch (message.type) {
      case 'position_update':
        trading.updatePosition(message.data)
        break
      case 'order_update':
        trading.updateOrder(message.data)
        break
      case 'alert':
        // 处理告警
        break
    }
  }

  private scheduleReconnect() {
    if (this.reconnectAttempts >= this.maxReconnectAttempts) {
      console.error('Max reconnect attempts reached')
      return
    }

    const delay = Math.min(1000 * Math.pow(2, this.reconnectAttempts), 30000)
    this.reconnectTimer = window.setTimeout(() => {
      this.reconnectAttempts++
      this.connect()
    }, delay)
  }

  disconnect() {
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer)
    }
    if (this.ws) {
      this.ws.close()
      this.ws = null
    }
  }

  send(message: object) {
    if (this.ws?.readyState === WebSocket.OPEN) {
      this.ws.send(JSON.stringify(message))
    }
  }
}

export const wsManager = new WebSocketManager()

interface WebSocketMessage {
  type: string
  data: any
}
```

---

## 核心组件

### 权益曲线图表

```vue
<!-- components/charts/EquityCurve.vue -->
<template>
  <div ref="chartRef" class="equity-chart"></div>
</template>

<script setup lang="ts">
import { ref, onMounted, onUnmounted, watch } from 'vue'
import * as echarts from 'echarts'

interface Props {
  data: { time: string; equity: number }[]
}

const props = defineProps<Props>()
const chartRef = ref<HTMLElement>()
let chart: echarts.ECharts | null = null

const option: echarts.EChartsOption = {
  tooltip: {
    trigger: 'axis',
    formatter: (params: any) => {
      const data = params[0]
      return `${data.axisValue}<br/>Equity: $${data.value.toLocaleString()}`
    },
  },
  xAxis: {
    type: 'category',
    data: [],
    axisLabel: { rotate: 45 },
  },
  yAxis: {
    type: 'value',
    axisLabel: {
      formatter: (value: number) => `$${(value / 1000).toFixed(0)}k`,
    },
  },
  series: [
    {
      type: 'line',
      data: [],
      smooth: true,
      areaStyle: {
        opacity: 0.3,
      },
      lineStyle: {
        width: 2,
      },
      itemStyle: {
        color: '#409eff',
      },
    },
  ],
  grid: {
    left: '10%',
    right: '5%',
    bottom: '15%',
  },
}

function updateChart() {
  if (!chart) return
  chart.setOption({
    xAxis: {
      data: props.data.map((d) => d.time),
    },
    series: [
      {
        data: props.data.map((d) => d.equity),
      },
    ],
  })
}

onMounted(() => {
  if (chartRef.value) {
    chart = echarts.init(chartRef.value)
    chart.setOption(option)
    updateChart()

    window.addEventListener('resize', () => chart?.resize())
  }
})

onUnmounted(() => {
  chart?.dispose()
  window.removeEventListener('resize', () => chart?.resize())
})

watch(() => props.data, updateChart, { deep: true })
</script>

<style scoped>
.equity-chart {
  width: 100%;
  height: 300px;
}
</style>
```

### 统计卡片

```vue
<!-- components/common/StatsCard.vue -->
<template>
  <el-card class="stats-card" :class="{ positive: isPositive, negative: isNegative }">
    <div class="stats-content">
      <div class="stats-value">
        <span v-if="prefix">{{ prefix }}</span>
        <span>{{ formattedValue }}</span>
        <span v-if="suffix">{{ suffix }}</span>
      </div>
      <div class="stats-label">{{ label }}</div>
      <div v-if="change !== undefined" class="stats-change" :class="changeClass">
        <el-icon v-if="change > 0"><ArrowUp /></el-icon>
        <el-icon v-else-if="change < 0"><ArrowDown /></el-icon>
        <span>{{ Math.abs(change).toFixed(2) }}%</span>
      </div>
    </div>
  </el-card>
</template>

<script setup lang="ts">
import { computed } from 'vue'
import { ArrowUp, ArrowDown } from '@element-plus/icons-vue'

interface Props {
  value: number
  label: string
  prefix?: string
  suffix?: string
  change?: number
  format?: 'number' | 'currency' | 'percent'
}

const props = withDefaults(defineProps<Props>(), {
  format: 'number',
})

const formattedValue = computed(() => {
  switch (props.format) {
    case 'currency':
      return props.value.toLocaleString('en-US', {
        style: 'currency',
        currency: 'USD',
        minimumFractionDigits: 0,
      })
    case 'percent':
      return `${(props.value * 100).toFixed(1)}%`
    default:
      return props.value.toLocaleString()
  }
})

const isPositive = computed(() => props.value > 0 && props.format !== 'currency')
const isNegative = computed(() => props.value < 0)
const changeClass = computed(() => ({
  positive: props.change && props.change > 0,
  negative: props.change && props.change < 0,
}))
</script>

<style scoped lang="scss">
.stats-card {
  text-align: center;
  transition: transform 0.2s;

  &:hover {
    transform: translateY(-2px);
  }

  &.positive .stats-value {
    color: var(--color-success);
  }

  &.negative .stats-value {
    color: var(--color-danger);
  }
}

.stats-value {
  font-size: 24px;
  font-weight: bold;
  margin-bottom: 8px;
}

.stats-label {
  font-size: 14px;
  color: var(--el-text-color-secondary);
}

.stats-change {
  margin-top: 8px;
  font-size: 12px;

  &.positive {
    color: var(--color-success);
  }

  &.negative {
    color: var(--color-danger);
  }
}
</style>
```

### 订单表单

```vue
<!-- components/trading/OrderForm.vue -->
<template>
  <el-form :model="form" :rules="rules" ref="formRef" label-width="100px">
    <el-form-item label="交易对" prop="symbol">
      <el-select v-model="form.symbol" placeholder="选择交易对">
        <el-option
          v-for="symbol in symbols"
          :key="symbol"
          :label="symbol"
          :value="symbol"
        />
      </el-select>
    </el-form-item>

    <el-form-item label="方向" prop="side">
      <el-radio-group v-model="form.side">
        <el-radio-button value="buy">买入</el-radio-button>
        <el-radio-button value="sell">卖出</el-radio-button>
      </el-radio-group>
    </el-form-item>

    <el-form-item label="订单类型" prop="type">
      <el-radio-group v-model="form.type">
        <el-radio-button value="market">市价</el-radio-button>
        <el-radio-button value="limit">限价</el-radio-button>
      </el-radio-group>
    </el-form-item>

    <el-form-item v-if="form.type === 'limit'" label="价格" prop="price">
      <el-input-number v-model="form.price" :min="0" :precision="2" />
    </el-form-item>

    <el-form-item label="数量" prop="quantity">
      <el-input-number v-model="form.quantity" :min="0" :precision="4" />
    </el-form-item>

    <el-form-item>
      <el-button type="primary" @click="submitOrder" :loading="loading">
        提交订单
      </el-button>
    </el-form-item>
  </el-form>
</template>

<script setup lang="ts">
import { ref, reactive } from 'vue'
import type { FormInstance, FormRules } from 'element-plus'
import { useTradingStore } from '@/stores/trading'
import { ElMessage } from 'element-plus'

const emit = defineEmits(['success'])

const trading = useTradingStore()
const formRef = ref<FormInstance>()
const loading = ref(false)

const symbols = ['BTC-USDT', 'ETH-USDT', 'SOL-USDT', 'DOGE-USDT']

const form = reactive({
  symbol: '',
  side: 'buy' as 'buy' | 'sell',
  type: 'limit' as 'market' | 'limit',
  price: 0,
  quantity: 0,
})

const rules: FormRules = {
  symbol: [{ required: true, message: '请选择交易对' }],
  quantity: [
    { required: true, message: '请输入数量' },
    { type: 'number', min: 0.0001, message: '数量必须大于 0' },
  ],
  price: [
    {
      required: true,
      validator: (rule, value, callback) => {
        if (form.type === 'limit' && (!value || value <= 0)) {
          callback(new Error('限价单必须设置价格'))
        } else {
          callback()
        }
      },
    },
  ],
}

async function submitOrder() {
  if (!formRef.value) return

  await formRef.value.validate()
  loading.value = true

  try {
    await trading.createOrder({
      symbol: form.symbol,
      side: form.side,
      type: form.type,
      price: form.type === 'limit' ? form.price : undefined,
      quantity: form.quantity,
    })

    ElMessage.success('订单提交成功')
    emit('success')
    formRef.value.resetFields()
  } catch (error) {
    ElMessage.error('订单提交失败')
  } finally {
    loading.value = false
  }
}
</script>
```

---

## 构建优化

### 代码分割

```typescript
// 路由懒加载
const Backtest = () => import('@/views/Backtest.vue')

// 组件懒加载
const HeavyChart = defineAsyncComponent(() =>
  import('@/components/charts/HeavyChart.vue')
)
```

### Tree Shaking

```typescript
// 按需导入 Element Plus
import { ElButton, ElInput, ElTable } from 'element-plus'

// 按需导入 ECharts
import { use } from 'echarts/core'
import { LineChart, BarChart } from 'echarts/charts'
import { GridComponent, TooltipComponent } from 'echarts/components'
import { CanvasRenderer } from 'echarts/renderers'

use([LineChart, BarChart, GridComponent, TooltipComponent, CanvasRenderer])
```

### 生产构建

```bash
# 构建
npm run build

# 分析包体积
npm run build -- --report

# 预览构建结果
npm run preview
```

---

## 静态文件嵌入

### Zig 嵌入方案

```zig
// src/api/static.zig
const std = @import("std");

// 嵌入构建产物
const index_html = @embedFile("static/index.html");
const app_js = @embedFile("static/assets/app.js");
const app_css = @embedFile("static/assets/app.css");
const vendor_js = @embedFile("static/assets/vendor.js");

pub const StaticFiles = struct {
    files: std.StringHashMap([]const u8),

    pub fn init(allocator: std.mem.Allocator) StaticFiles {
        var files = std.StringHashMap([]const u8).init(allocator);
        files.put("/", index_html) catch {};
        files.put("/index.html", index_html) catch {};
        files.put("/assets/app.js", app_js) catch {};
        files.put("/assets/app.css", app_css) catch {};
        files.put("/assets/vendor.js", vendor_js) catch {};
        return .{ .files = files };
    }

    pub fn get(self: *StaticFiles, path: []const u8) ?[]const u8 {
        return self.files.get(path);
    }
};

fn getMimeType(path: []const u8) []const u8 {
    if (std.mem.endsWith(u8, path, ".html")) return "text/html";
    if (std.mem.endsWith(u8, path, ".js")) return "application/javascript";
    if (std.mem.endsWith(u8, path, ".css")) return "text/css";
    if (std.mem.endsWith(u8, path, ".json")) return "application/json";
    if (std.mem.endsWith(u8, path, ".png")) return "image/png";
    if (std.mem.endsWith(u8, path, ".svg")) return "image/svg+xml";
    return "application/octet-stream";
}
```

---

*Last updated: 2025-12-28*
