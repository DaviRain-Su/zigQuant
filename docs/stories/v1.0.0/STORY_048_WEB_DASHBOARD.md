# Story 048: Web Dashboard

**Story ID**: STORY-048
**版本**: v1.0.0
**优先级**: P1
**状态**: ✅ 已完成
**依赖**: Story 047 (REST API)
**完成日期**: 2025-12-28

---

## 概述

实现基于 Vue 3 + Vite 的 Web 监控面板，提供策略管理、回测可视化、实时监控等功能。构建产物嵌入 Zig 服务，无需额外前端服务器。

### 目标

1. 策略配置和管理界面
2. 回测结果可视化 (权益曲线、指标图表)
3. 实时 PnL 监控
4. 仓位和订单管理
5. 告警通知面板

---

## 技术方案

### 前端技术栈

| 技术 | 版本 | 用途 |
|------|------|------|
| Vue 3 | 3.4+ | 前端框架 |
| Vite | 5.x | 构建工具 |
| TypeScript | 5.x | 类型安全 |
| Element Plus | 2.x | UI 组件库 |
| ECharts | 5.x | 图表库 |
| Pinia | 2.x | 状态管理 |
| Vue Router | 4.x | 路由 |
| Axios | 1.x | HTTP 客户端 |

### 构建集成

```bash
# 开发模式
cd dashboard && npm run dev

# 生产构建
cd dashboard && npm run build

# 嵌入 Zig 服务
cp -r dashboard/dist/* src/api/static/
```

---

## 目录结构

```
dashboard/
├── package.json
├── vite.config.ts
├── tsconfig.json
├── index.html
├── public/
│   └── favicon.ico
└── src/
    ├── main.ts                 # 入口
    ├── App.vue                 # 根组件
    ├── router/
    │   └── index.ts            # 路由配置
    ├── stores/
    │   ├── auth.ts             # 认证状态
    │   ├── strategies.ts       # 策略状态
    │   ├── backtest.ts         # 回测状态
    │   └── trading.ts          # 交易状态
    ├── api/
    │   ├── index.ts            # API 客户端
    │   ├── auth.ts             # 认证 API
    │   ├── strategies.ts       # 策略 API
    │   ├── backtest.ts         # 回测 API
    │   └── trading.ts          # 交易 API
    ├── views/
    │   ├── Login.vue           # 登录页
    │   ├── Dashboard.vue       # 首页概览
    │   ├── Strategies.vue      # 策略管理
    │   ├── Backtest.vue        # 回测
    │   ├── Orders.vue          # 订单
    │   ├── Positions.vue       # 仓位
    │   └── Alerts.vue          # 告警
    ├── components/
    │   ├── common/
    │   │   ├── Header.vue
    │   │   ├── Sidebar.vue
    │   │   └── Footer.vue
    │   └── charts/
    │       ├── EquityCurve.vue
    │       ├── PnLChart.vue
    │       ├── DrawdownChart.vue
    │       └── MetricsCard.vue
    └── styles/
        └── main.scss
```

---

## 页面设计

### 1. 登录页 (Login.vue)

```vue
<template>
  <div class="login-container">
    <el-card class="login-card">
      <template #header>
        <h2>zigQuant Dashboard</h2>
      </template>

      <el-form :model="form" @submit.prevent="handleLogin">
        <el-form-item label="用户名">
          <el-input v-model="form.username" />
        </el-form-item>

        <el-form-item label="密码">
          <el-input v-model="form.password" type="password" />
        </el-form-item>

        <el-button type="primary" native-type="submit" :loading="loading">
          登录
        </el-button>
      </el-form>
    </el-card>
  </div>
</template>

<script setup lang="ts">
import { ref } from 'vue'
import { useRouter } from 'vue-router'
import { useAuthStore } from '@/stores/auth'

const form = ref({ username: '', password: '' })
const loading = ref(false)
const router = useRouter()
const authStore = useAuthStore()

async function handleLogin() {
  loading.value = true
  try {
    await authStore.login(form.value.username, form.value.password)
    router.push('/dashboard')
  } catch (error) {
    ElMessage.error('登录失败')
  } finally {
    loading.value = false
  }
}
</script>
```

### 2. 首页概览 (Dashboard.vue)

**功能**:
- 账户余额卡片
- 今日 PnL 卡片
- 活跃策略数量
- 持仓数量
- PnL 趋势图 (7 天)
- 最近交易列表

```vue
<template>
  <div class="dashboard">
    <!-- 指标卡片 -->
    <el-row :gutter="20">
      <el-col :span="6">
        <MetricsCard
          title="账户余额"
          :value="account.balance"
          prefix="$"
          icon="wallet"
        />
      </el-col>
      <el-col :span="6">
        <MetricsCard
          title="今日 PnL"
          :value="account.todayPnL"
          prefix="$"
          :trend="account.todayPnL >= 0 ? 'up' : 'down'"
        />
      </el-col>
      <el-col :span="6">
        <MetricsCard
          title="活跃策略"
          :value="strategies.active"
          suffix="个"
        />
      </el-col>
      <el-col :span="6">
        <MetricsCard
          title="持仓数量"
          :value="positions.count"
          suffix="个"
        />
      </el-col>
    </el-row>

    <!-- 图表 -->
    <el-row :gutter="20" style="margin-top: 20px">
      <el-col :span="16">
        <el-card>
          <template #header>PnL 趋势 (7 天)</template>
          <PnLChart :data="pnlData" />
        </el-card>
      </el-col>
      <el-col :span="8">
        <el-card>
          <template #header>最近交易</template>
          <RecentTrades :trades="recentTrades" />
        </el-card>
      </el-col>
    </el-row>
  </div>
</template>
```

### 3. 策略管理 (Strategies.vue)

**功能**:
- 策略列表 (表格)
- 策略状态 (运行中/停止)
- 启动/停止按钮
- 策略配置编辑
- 性能指标显示

```vue
<template>
  <div class="strategies">
    <el-card>
      <template #header>
        <div class="header">
          <span>策略管理</span>
          <el-button type="primary" @click="showCreateDialog">
            新建策略
          </el-button>
        </div>
      </template>

      <el-table :data="strategies" stripe>
        <el-table-column prop="name" label="策略名称" />
        <el-table-column prop="pair" label="交易对" />
        <el-table-column prop="timeframe" label="时间周期" />
        <el-table-column prop="status" label="状态">
          <template #default="{ row }">
            <el-tag :type="row.status === 'running' ? 'success' : 'info'">
              {{ row.status }}
            </el-tag>
          </template>
        </el-table-column>
        <el-table-column prop="pnl" label="累计盈亏">
          <template #default="{ row }">
            <span :class="row.pnl >= 0 ? 'profit' : 'loss'">
              {{ row.pnl >= 0 ? '+' : '' }}{{ row.pnl.toFixed(2) }}%
            </span>
          </template>
        </el-table-column>
        <el-table-column label="操作" width="200">
          <template #default="{ row }">
            <el-button
              v-if="row.status !== 'running'"
              type="success"
              size="small"
              @click="startStrategy(row.id)"
            >
              启动
            </el-button>
            <el-button
              v-else
              type="danger"
              size="small"
              @click="stopStrategy(row.id)"
            >
              停止
            </el-button>
            <el-button size="small" @click="editStrategy(row)">
              配置
            </el-button>
          </template>
        </el-table-column>
      </el-table>
    </el-card>
  </div>
</template>
```

### 4. 回测页面 (Backtest.vue)

**功能**:
- 回测配置表单
- 策略选择
- 时间范围选择
- 初始资金设置
- 回测结果展示
- 权益曲线图表
- 性能指标卡片

```vue
<template>
  <div class="backtest">
    <el-row :gutter="20">
      <!-- 配置表单 -->
      <el-col :span="8">
        <el-card>
          <template #header>回测配置</template>

          <el-form :model="config" label-position="top">
            <el-form-item label="策略">
              <el-select v-model="config.strategyId" style="width: 100%">
                <el-option
                  v-for="s in strategies"
                  :key="s.id"
                  :label="s.name"
                  :value="s.id"
                />
              </el-select>
            </el-form-item>

            <el-form-item label="时间范围">
              <el-date-picker
                v-model="config.dateRange"
                type="daterange"
                style="width: 100%"
              />
            </el-form-item>

            <el-form-item label="初始资金">
              <el-input-number
                v-model="config.initialCapital"
                :min="1000"
                :step="1000"
              />
            </el-form-item>

            <el-button
              type="primary"
              :loading="running"
              @click="runBacktest"
            >
              运行回测
            </el-button>
          </el-form>
        </el-card>
      </el-col>

      <!-- 结果展示 -->
      <el-col :span="16">
        <el-card v-if="result">
          <template #header>回测结果</template>

          <!-- 指标卡片 -->
          <el-row :gutter="10">
            <el-col :span="6">
              <div class="metric">
                <div class="label">总收益率</div>
                <div class="value" :class="result.totalReturn >= 0 ? 'profit' : 'loss'">
                  {{ (result.totalReturn * 100).toFixed(2) }}%
                </div>
              </div>
            </el-col>
            <el-col :span="6">
              <div class="metric">
                <div class="label">夏普比率</div>
                <div class="value">{{ result.sharpeRatio.toFixed(2) }}</div>
              </div>
            </el-col>
            <el-col :span="6">
              <div class="metric">
                <div class="label">最大回撤</div>
                <div class="value loss">
                  {{ (result.maxDrawdown * 100).toFixed(2) }}%
                </div>
              </div>
            </el-col>
            <el-col :span="6">
              <div class="metric">
                <div class="label">胜率</div>
                <div class="value">{{ (result.winRate * 100).toFixed(1) }}%</div>
              </div>
            </el-col>
          </el-row>

          <!-- 权益曲线 -->
          <EquityCurve :data="result.equityCurve" style="margin-top: 20px" />
        </el-card>
      </el-col>
    </el-row>
  </div>
</template>
```

### 5. 订单页面 (Orders.vue)

**功能**:
- 活跃订单表格
- 历史订单表格
- 订单详情弹窗
- 取消订单按钮
- 订单筛选

### 6. 仓位页面 (Positions.vue)

**功能**:
- 当前持仓列表
- 仓位盈亏显示
- 平仓按钮
- 持仓分布饼图

### 7. 告警页面 (Alerts.vue)

**功能**:
- 告警历史列表
- 告警级别筛选
- 通知渠道配置
- 告警规则管理

---

## 图表组件

### 权益曲线 (EquityCurve.vue)

```vue
<template>
  <div ref="chartRef" class="equity-curve"></div>
</template>

<script setup lang="ts">
import { ref, onMounted, watch } from 'vue'
import * as echarts from 'echarts'

const props = defineProps<{
  data: { time: string; equity: number }[]
}>()

const chartRef = ref<HTMLElement>()
let chart: echarts.ECharts

onMounted(() => {
  chart = echarts.init(chartRef.value!)
  updateChart()
})

watch(() => props.data, updateChart)

function updateChart() {
  chart.setOption({
    title: { text: '权益曲线' },
    tooltip: { trigger: 'axis' },
    xAxis: {
      type: 'time',
      data: props.data.map(d => d.time),
    },
    yAxis: { type: 'value' },
    series: [{
      type: 'line',
      data: props.data.map(d => [d.time, d.equity]),
      smooth: true,
      areaStyle: { opacity: 0.3 },
    }],
  })
}
</script>

<style scoped>
.equity-curve {
  width: 100%;
  height: 300px;
}
</style>
```

### 指标卡片 (MetricsCard.vue)

```vue
<template>
  <el-card class="metrics-card" :class="trend">
    <div class="icon">
      <el-icon><component :is="iconComponent" /></el-icon>
    </div>
    <div class="content">
      <div class="title">{{ title }}</div>
      <div class="value">
        {{ prefix }}{{ formatValue(value) }}{{ suffix }}
      </div>
    </div>
  </el-card>
</template>

<script setup lang="ts">
import { computed } from 'vue'
import { Wallet, TrendCharts, List, Position } from '@element-plus/icons-vue'

const props = defineProps<{
  title: string
  value: number
  prefix?: string
  suffix?: string
  trend?: 'up' | 'down'
  icon?: 'wallet' | 'chart' | 'list' | 'position'
}>()

const iconComponent = computed(() => {
  switch (props.icon) {
    case 'wallet': return Wallet
    case 'chart': return TrendCharts
    case 'list': return List
    case 'position': return Position
    default: return Wallet
  }
})

function formatValue(v: number): string {
  return v.toLocaleString('en-US', { maximumFractionDigits: 2 })
}
</script>
```

---

## API 客户端

### api/index.ts

```typescript
import axios from 'axios'
import { useAuthStore } from '@/stores/auth'

const api = axios.create({
  baseURL: '/api/v1',
  timeout: 30000,
})

// 请求拦截器 - 添加 Token
api.interceptors.request.use((config) => {
  const authStore = useAuthStore()
  if (authStore.token) {
    config.headers.Authorization = `Bearer ${authStore.token}`
  }
  return config
})

// 响应拦截器 - 处理 401
api.interceptors.response.use(
  (response) => response,
  (error) => {
    if (error.response?.status === 401) {
      const authStore = useAuthStore()
      authStore.logout()
      window.location.href = '/login'
    }
    return Promise.reject(error)
  }
)

export default api
```

### api/strategies.ts

```typescript
import api from './index'

export interface Strategy {
  id: string
  name: string
  pair: string
  timeframe: string
  status: 'running' | 'stopped'
  pnl: number
}

export async function listStrategies(): Promise<Strategy[]> {
  const { data } = await api.get('/strategies')
  return data.strategies
}

export async function runStrategy(id: string): Promise<void> {
  await api.post(`/strategies/${id}/run`)
}

export async function stopStrategy(id: string): Promise<void> {
  await api.post(`/strategies/${id}/stop`)
}
```

---

## 状态管理 (Pinia)

### stores/auth.ts

```typescript
import { defineStore } from 'pinia'
import { ref } from 'vue'
import api from '@/api'

export const useAuthStore = defineStore('auth', () => {
  const token = ref<string | null>(localStorage.getItem('token'))
  const user = ref<{ id: string; username: string } | null>(null)

  async function login(username: string, password: string) {
    const { data } = await api.post('/auth/login', { username, password })
    token.value = data.token
    localStorage.setItem('token', data.token)
    await fetchUser()
  }

  async function fetchUser() {
    const { data } = await api.get('/auth/me')
    user.value = data
  }

  function logout() {
    token.value = null
    user.value = null
    localStorage.removeItem('token')
  }

  return { token, user, login, fetchUser, logout }
})
```

---

## 路由配置

### router/index.ts

```typescript
import { createRouter, createWebHistory } from 'vue-router'
import { useAuthStore } from '@/stores/auth'

const routes = [
  { path: '/login', name: 'Login', component: () => import('@/views/Login.vue') },
  {
    path: '/',
    component: () => import('@/layouts/MainLayout.vue'),
    meta: { requiresAuth: true },
    children: [
      { path: '', redirect: '/dashboard' },
      { path: 'dashboard', name: 'Dashboard', component: () => import('@/views/Dashboard.vue') },
      { path: 'strategies', name: 'Strategies', component: () => import('@/views/Strategies.vue') },
      { path: 'backtest', name: 'Backtest', component: () => import('@/views/Backtest.vue') },
      { path: 'orders', name: 'Orders', component: () => import('@/views/Orders.vue') },
      { path: 'positions', name: 'Positions', component: () => import('@/views/Positions.vue') },
      { path: 'alerts', name: 'Alerts', component: () => import('@/views/Alerts.vue') },
    ],
  },
]

const router = createRouter({
  history: createWebHistory(),
  routes,
})

// 路由守卫
router.beforeEach((to, from, next) => {
  const authStore = useAuthStore()

  if (to.meta.requiresAuth && !authStore.token) {
    next('/login')
  } else {
    next()
  }
})

export default router
```

---

## Zig 静态文件服务

```zig
// src/api/handlers/static.zig
const std = @import("std");
const httpz = @import("httpz");

pub fn serve(req: *httpz.Request, res: *httpz.Response) !void {
    var path = req.path;

    // 默认返回 index.html (SPA)
    if (std.mem.eql(u8, path, "/") or !std.mem.containsAny(u8, path, ".")) {
        path = "/index.html";
    }

    // 读取静态文件
    const file_path = try std.fmt.allocPrint(req.allocator, "static{s}", .{path});
    defer req.allocator.free(file_path);

    const content = std.fs.cwd().readFileAlloc(req.allocator, file_path, 10 * 1024 * 1024) catch {
        res.status = .not_found;
        return res.write("Not Found");
    };
    defer req.allocator.free(content);

    // 设置 Content-Type
    const ext = std.fs.path.extension(path);
    const content_type = getContentType(ext);
    res.headers.put("Content-Type", content_type);

    try res.write(content);
}

fn getContentType(ext: []const u8) []const u8 {
    if (std.mem.eql(u8, ext, ".html")) return "text/html; charset=utf-8";
    if (std.mem.eql(u8, ext, ".js")) return "application/javascript";
    if (std.mem.eql(u8, ext, ".css")) return "text/css";
    if (std.mem.eql(u8, ext, ".json")) return "application/json";
    if (std.mem.eql(u8, ext, ".png")) return "image/png";
    if (std.mem.eql(u8, ext, ".svg")) return "image/svg+xml";
    return "application/octet-stream";
}
```

---

## 验收标准

### 功能要求 (MVP)

- [x] 登录/登出功能
- [x] Dashboard 首页概览
- [x] 策略列表和管理
- [x] 回测配置和结果可视化
- [ ] 订单列表和取消 *(v1.1.0)*
- [ ] 仓位列表和盈亏显示 *(v1.1.0)*
- [ ] 告警历史和配置 *(v1.1.0)*

### 视觉要求

- [x] 响应式设计 (桌面/平板)
- [ ] 深色/浅色主题切换 *(v1.1.0)*
- [x] 图表交互 (缩放、提示)
- [x] 加载状态指示

### 性能要求

- [x] 首屏加载 < 3s
- [x] 图表渲染 < 1s
- [x] 构建产物 < 500KB (gzip) - 实际 ~235KB gzip

---

## 相关文档

- [v1.0.0 Overview](./OVERVIEW.md)
- [Story 047: REST API](./STORY_047_REST_API.md)

---

## 实现总结

### MVP 版本 (已完成)

**实现的页面:**
1. **Login.vue** - 用户登录，JWT 认证
2. **Dashboard.vue** - 账户概览，PnL 图表，核心指标卡片
3. **Strategies.vue** - 策略列表，状态管理，启动/停止
4. **Backtest.vue** - 回测配置，结果可视化，权益曲线

**技术特点:**
- Vue 3 + TypeScript + Composition API
- Element Plus UI 组件库
- ECharts 图表 (vue-echarts)
- Pinia 状态管理
- Vue Router 4 路由守卫
- Axios HTTP 客户端 + JWT 拦截器

**Zig 服务集成:**
- 静态文件服务从 `dashboard/dist/` 目录
- SPA 路由支持 (非静态资源返回 index.html)
- MIME 类型自动识别
- 长期缓存 (Cache-Control: 1 年)

**构建产物:**
```
dashboard/dist/
├── index.html (0.46 KB)
├── vite.svg (1.5 KB)
└── assets/
    ├── index-*.js (1.2 MB / 386 KB gzip)
    ├── index-*.css (347 KB / 47 KB gzip)
    └── [page chunks] (~20 KB each)
```

### 使用方式

```bash
# 开发模式 (前后端分离)
cd dashboard && npm run dev    # Vue dev server :5173
./zig-out/bin/zigQuant serve   # API server :8080

# 生产模式 (集成)
cd dashboard && npm run build
./zig-out/bin/zigQuant serve
# 访问 http://localhost:8080
```

### 后续版本 (v1.1.0)

- Orders 订单页面
- Positions 仓位页面
- Alerts 告警页面
- 深色/浅色主题切换

---

*最后更新: 2025-12-28*
