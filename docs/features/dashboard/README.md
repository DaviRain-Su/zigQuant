# Web Dashboard - 可视化仪表板

> 交易系统 Web 管理界面

**状态**: 📋 待开始
**版本**: v1.0.0
**Story**: [Story 048: Web Dashboard](../../stories/v1.0.0/STORY_048_WEB_DASHBOARD.md)
**最后更新**: 2025-12-28

---

## 概述

zigQuant Web Dashboard 提供直观的 Web 界面，用于监控交易系统状态、管理策略、查看回测结果和接收告警通知。

### 为什么需要 Dashboard？

- **实时监控**: 可视化交易状态和性能指标
- **策略管理**: 图形化策略配置和运行控制
- **回测分析**: 交互式回测结果可视化
- **告警管理**: 统一的告警查看和配置

### 核心特性

- **Vue 3 + Vite**: 现代前端技术栈
- **实时更新**: WebSocket 数据推送
- **响应式设计**: 适配桌面和移动端
- **深色模式**: 内置主题切换
- **静态嵌入**: 构建产物嵌入 Zig 服务

---

## 快速开始

### 访问 Dashboard

```bash
# 启动 zigQuant 服务
zigquant serve --config config.json

# 访问 Dashboard
open http://localhost:8080/
```

### 默认登录

```
用户名: admin
密码: admin
```

**注意**: 首次登录后请立即修改密码

---

## 相关文档

- [实现细节](./implementation.md) - 前端架构和构建流程
- [组件说明](./components.md) - UI 组件文档
- [测试文档](./testing.md) - 前端测试
- [Bug 追踪](./bugs.md) - 已知问题
- [变更日志](./changelog.md) - 版本历史

---

## 页面概览

### 1. 首页 (Dashboard)

概览页面，展示核心交易指标。

**功能**:
- 账户余额和总盈亏
- 今日交易统计
- 实时持仓概览
- 最近告警列表
- 核心指标卡片 (胜率、夏普比率、回撤)

**截图**:
```
┌─────────────────────────────────────────────────────────────┐
│  zigQuant Dashboard                        [Admin] [Logout] │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌───────────┐ ┌───────────┐ ┌───────────┐ ┌───────────┐   │
│  │ Balance   │ │ Today PnL │ │ Win Rate  │ │ Drawdown  │   │
│  │ $125,432  │ │ +$1,234   │ │   65.3%   │ │  -12.5%   │   │
│  └───────────┘ └───────────┘ └───────────┘ └───────────┘   │
│                                                              │
│  ┌────────────────────────────────┐ ┌────────────────────┐  │
│  │      Equity Curve              │ │  Open Positions    │  │
│  │  ╱╲    ╱╲                      │ │  BTC-USDT  +2.5%   │  │
│  │ ╱  ╲  ╱  ╲    ╱                │ │  ETH-USDT  -1.2%   │  │
│  │╱    ╲╱    ╲  ╱                 │ │  SOL-USDT  +0.8%   │  │
│  └────────────────────────────────┘ └────────────────────┘  │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 2. 策略页面 (Strategies)

策略管理和监控。

**功能**:
- 策略列表和状态
- 策略配置编辑
- 运行/停止控制
- 策略性能图表
- 参数优化入口

### 3. 回测页面 (Backtest)

回测配置和结果分析。

**功能**:
- 回测配置表单
- 实时回测进度
- 权益曲线图表
- 交易列表
- 性能指标表格

### 4. 订单页面 (Orders)

订单管理。

**功能**:
- 活跃订单列表
- 历史订单查询
- 订单详情查看
- 手动下单入口
- 批量取消功能

### 5. 仓位页面 (Positions)

持仓管理。

**功能**:
- 当前持仓列表
- 盈亏分析图表
- 仓位风险指标
- 平仓操作
- 历史仓位记录

### 6. 告警页面 (Alerts)

告警和通知管理。

**功能**:
- 告警历史列表
- 告警规则配置
- 通知渠道设置
- 告警确认操作
- 统计分析

---

## 技术栈

| 技术 | 版本 | 用途 |
|------|------|------|
| Vue 3 | 3.4.x | 前端框架 |
| Vite | 5.x | 构建工具 |
| Pinia | 2.x | 状态管理 |
| Vue Router | 4.x | 路由管理 |
| Element Plus | 2.x | UI 组件库 |
| ECharts | 5.x | 图表库 |
| Axios | 1.x | HTTP 客户端 |

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
    ├── main.ts              # 入口
    ├── App.vue              # 根组件
    ├── router/
    │   └── index.ts         # 路由配置
    ├── stores/
    │   ├── auth.ts          # 认证状态
    │   ├── trading.ts       # 交易状态
    │   └── alerts.ts        # 告警状态
    ├── views/
    │   ├── Dashboard.vue    # 首页
    │   ├── Strategies.vue   # 策略页
    │   ├── Backtest.vue     # 回测页
    │   ├── Orders.vue       # 订单页
    │   ├── Positions.vue    # 仓位页
    │   └── Alerts.vue       # 告警页
    ├── components/
    │   ├── charts/
    │   │   ├── EquityCurve.vue
    │   │   ├── PnLChart.vue
    │   │   └── DrawdownChart.vue
    │   ├── common/
    │   │   ├── Navbar.vue
    │   │   ├── Sidebar.vue
    │   │   └── StatsCard.vue
    │   └── trading/
    │       ├── OrderForm.vue
    │       ├── PositionCard.vue
    │       └── TradeList.vue
    ├── api/
    │   ├── client.ts        # API 客户端
    │   ├── auth.ts          # 认证 API
    │   ├── strategies.ts    # 策略 API
    │   └── trading.ts       # 交易 API
    ├── composables/
    │   ├── useWebSocket.ts  # WebSocket Hook
    │   └── useAuth.ts       # 认证 Hook
    └── styles/
        ├── variables.scss
        └── main.scss
```

---

## 构建和部署

### 开发模式

```bash
cd dashboard

# 安装依赖
npm install

# 启动开发服务器
npm run dev
# → http://localhost:5173

# 代理 API 请求到 zigQuant
# vite.config.ts 中已配置 proxy
```

### 生产构建

```bash
# 构建
npm run build

# 构建产物在 dist/ 目录
ls dist/
# → index.html  assets/

# 复制到 Zig 静态目录
cp -r dist/* ../src/api/static/
```

### 嵌入 Zig 服务

```zig
// src/api/server.zig
const static_dir = @embedFile("static/");

fn serveStatic(req: *Request, res: *Response) !void {
    const path = req.path;
    if (static_files.get(path)) |content| {
        res.body = content;
        res.content_type = getMimeType(path);
    } else {
        // SPA fallback
        res.body = static_files.get("/index.html").?;
        res.content_type = "text/html";
    }
}
```

---

## API 集成

### 认证流程

```typescript
// api/auth.ts
import axios from 'axios'

const api = axios.create({
  baseURL: '/api/v1',
})

// 请求拦截器添加 Token
api.interceptors.request.use((config) => {
  const token = localStorage.getItem('token')
  if (token) {
    config.headers.Authorization = `Bearer ${token}`
  }
  return config
})

export async function login(username: string, password: string) {
  const { data } = await api.post('/auth/login', { username, password })
  localStorage.setItem('token', data.token)
  return data
}

export async function logout() {
  localStorage.removeItem('token')
}
```

### WebSocket 实时更新

```typescript
// composables/useWebSocket.ts
import { ref, onMounted, onUnmounted } from 'vue'

export function useWebSocket(path: string) {
  const data = ref(null)
  const connected = ref(false)
  let ws: WebSocket | null = null

  function connect() {
    const token = localStorage.getItem('token')
    ws = new WebSocket(`ws://localhost:8080${path}?token=${token}`)

    ws.onopen = () => {
      connected.value = true
    }

    ws.onmessage = (event) => {
      data.value = JSON.parse(event.data)
    }

    ws.onclose = () => {
      connected.value = false
      setTimeout(connect, 3000) // 自动重连
    }
  }

  onMounted(connect)
  onUnmounted(() => ws?.close())

  return { data, connected }
}
```

---

## 主题配置

### 深色模式

```typescript
// stores/theme.ts
import { defineStore } from 'pinia'

export const useThemeStore = defineStore('theme', {
  state: () => ({
    dark: localStorage.getItem('theme') === 'dark',
  }),
  actions: {
    toggle() {
      this.dark = !this.dark
      localStorage.setItem('theme', this.dark ? 'dark' : 'light')
      document.documentElement.classList.toggle('dark', this.dark)
    },
  },
})
```

### 自定义颜色

```scss
// styles/variables.scss
:root {
  --color-primary: #409eff;
  --color-success: #67c23a;
  --color-warning: #e6a23c;
  --color-danger: #f56c6c;

  --color-profit: #67c23a;
  --color-loss: #f56c6c;
}

.dark {
  --color-bg: #1a1a1a;
  --color-text: #ffffff;
}
```

---

## 性能优化

### 代码分割

```typescript
// router/index.ts
const routes = [
  {
    path: '/backtest',
    component: () => import('@/views/Backtest.vue'), // 懒加载
  },
]
```

### 虚拟列表

```vue
<!-- 大量数据使用虚拟列表 -->
<template>
  <el-table-v2
    :columns="columns"
    :data="orders"
    :height="400"
    :row-height="50"
  />
</template>
```

---

## 未来改进

- [ ] PWA 支持 (离线访问)
- [ ] 国际化 (i18n)
- [ ] 键盘快捷键
- [ ] 自定义布局
- [ ] 移动端 App

---

*Last updated: 2025-12-28*
