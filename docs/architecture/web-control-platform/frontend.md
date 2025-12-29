# 前端架构设计

> Bun + React 现代前端架构

**版本**: v2.0.0
**状态**: 📋 设计阶段
**创建日期**: 2025-12-29

---

## 📋 概述

新前端使用 Bun 作为包管理器和运行时，React 作为 UI 框架，实现：
- 实时数据展示（WebSocket）
- 策略控制面板
- 回测中心
- 系统监控

---

## 🛠️ 技术栈

| 类别 | 选择 | 版本 | 理由 |
|------|------|------|------|
| 运行时 | Bun | 1.x | 快速、现代、TypeScript 原生支持 |
| 框架 | React | 18.x | 生态丰富、Hooks、Concurrent |
| 构建 | Vite | 5.x | 快速 HMR、ESM 原生 |
| 语言 | TypeScript | 5.x | 类型安全 |
| 状态管理 | Zustand | 4.x | 简单、TypeScript 友好 |
| 数据获取 | TanStack Query | 5.x | 缓存、重试、乐观更新 |
| 路由 | React Router | 6.x | 标准方案 |
| UI 组件 | shadcn/ui | - | 可定制、Tailwind 集成 |
| 样式 | Tailwind CSS | 3.x | 实用优先、快速开发 |
| 图表 | Recharts | 2.x | React 原生、响应式 |
| 金融图表 | Lightweight Charts | 4.x | TradingView 开源版 |
| HTTP | Axios | 1.x | 成熟稳定 |
| WebSocket | 原生 + 封装 | - | 轻量可控 |
| 表单 | React Hook Form | 7.x | 性能优秀 |
| 验证 | Zod | 3.x | TypeScript 集成 |

---

## 📁 项目结构

```
web/
├── package.json
├── bun.lockb
├── tsconfig.json
├── vite.config.ts
├── tailwind.config.js
├── postcss.config.js
├── index.html
│
├── public/
│   ├── favicon.ico
│   └── logo.svg
│
└── src/
    ├── main.tsx                 # 入口
    ├── App.tsx                  # 根组件
    ├── vite-env.d.ts
    │
    ├── api/                     # API 层
    │   ├── client.ts            # Axios 实例
    │   ├── websocket.ts         # WebSocket 客户端
    │   ├── types.ts             # API 类型定义
    │   └── hooks/               # TanStack Query hooks
    │       ├── useAuth.ts
    │       ├── useGrid.ts
    │       ├── useBacktest.ts
    │       ├── useStrategy.ts
    │       └── useSystem.ts
    │
    ├── stores/                  # Zustand 状态
    │   ├── authStore.ts
    │   ├── gridStore.ts
    │   ├── backtestStore.ts
    │   ├── strategyStore.ts
    │   └── systemStore.ts
    │
    ├── components/              # UI 组件
    │   ├── ui/                  # shadcn/ui 组件
    │   │   ├── button.tsx
    │   │   ├── card.tsx
    │   │   ├── dialog.tsx
    │   │   ├── input.tsx
    │   │   ├── select.tsx
    │   │   ├── table.tsx
    │   │   └── ...
    │   │
    │   ├── common/              # 通用组件
    │   │   ├── Header.tsx
    │   │   ├── Sidebar.tsx
    │   │   ├── StatusBadge.tsx
    │   │   ├── LoadingSpinner.tsx
    │   │   └── ErrorBoundary.tsx
    │   │
    │   ├── charts/              # 图表组件
    │   │   ├── PriceChart.tsx
    │   │   ├── EquityChart.tsx
    │   │   ├── PnLChart.tsx
    │   │   └── GridVisualizer.tsx
    │   │
    │   ├── grid/                # 网格交易组件
    │   │   ├── GridControl.tsx
    │   │   ├── GridConfigForm.tsx
    │   │   ├── GridStatus.tsx
    │   │   ├── GridOrders.tsx
    │   │   └── GridList.tsx
    │   │
    │   ├── backtest/            # 回测组件
    │   │   ├── BacktestRunner.tsx
    │   │   ├── BacktestConfig.tsx
    │   │   ├── BacktestProgress.tsx
    │   │   ├── BacktestResult.tsx
    │   │   └── BacktestHistory.tsx
    │   │
    │   ├── strategy/            # 策略组件
    │   │   ├── StrategyList.tsx
    │   │   ├── StrategyControl.tsx
    │   │   ├── StrategyParams.tsx
    │   │   └── SignalLog.tsx
    │   │
    │   └── system/              # 系统组件
    │       ├── SystemHealth.tsx
    │       ├── KillSwitch.tsx
    │       ├── LogViewer.tsx
    │       └── AlertList.tsx
    │
    ├── pages/                   # 页面组件
    │   ├── Login.tsx
    │   ├── Dashboard.tsx
    │   ├── GridTrading.tsx
    │   ├── Backtest.tsx
    │   ├── Strategies.tsx
    │   ├── Settings.tsx
    │   └── NotFound.tsx
    │
    ├── layouts/                 # 布局组件
    │   ├── MainLayout.tsx
    │   └── AuthLayout.tsx
    │
    ├── hooks/                   # 自定义 Hooks
    │   ├── useWebSocket.ts
    │   ├── useRealtime.ts
    │   └── useLocalStorage.ts
    │
    ├── lib/                     # 工具库
    │   ├── utils.ts
    │   ├── formatters.ts
    │   └── validators.ts
    │
    ├── types/                   # 类型定义
    │   ├── grid.ts
    │   ├── backtest.ts
    │   ├── strategy.ts
    │   └── system.ts
    │
    └── styles/                  # 样式
        ├── globals.css
        └── components.css
```

---

## 🎨 页面设计

### 1. Dashboard 总览

```
┌─────────────────────────────────────────────────────────────────────┐
│  Header: Logo | Dashboard | Grid | Backtest | Strategies | Settings │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐ ┌─────────────┐   │
│  │ Total PnL   │ │ Running     │ │ Today's     │ │ System      │   │
│  │ $1,234.56   │ │ Strategies  │ │ Trades      │ │ Health      │   │
│  │ +12.3%      │ │ 5           │ │ 127         │ │ ● Healthy   │   │
│  └─────────────┘ └─────────────┘ └─────────────┘ └─────────────┘   │
│                                                                      │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │                     Equity Curve Chart                       │   │
│  │                     (Last 30 days)                          │   │
│  │  ╭───────────────────────────────╮                          │   │
│  │  │                            ╱  │                          │   │
│  │  │                        ╱╲╱   │                          │   │
│  │  │                    ╱╲╱       │                          │   │
│  │  │               ╱╲╱╲           │                          │   │
│  │  ╰───────────────────────────────╯                          │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                                                                      │
│  ┌───────────────────────────┐ ┌───────────────────────────────┐   │
│  │     Active Grids          │ │     Recent Trades             │   │
│  │ ┌───────────────────────┐ │ │ ┌───────────────────────────┐ │   │
│  │ │ BTC-USDC  ● Running   │ │ │ │ BTC BUY  0.001 @ 94000   │ │   │
│  │ │ PnL: +$45.67          │ │ │ │ ETH SELL 0.01  @ 3200    │ │   │
│  │ └───────────────────────┘ │ │ │ BTC SELL 0.001 @ 94500   │ │   │
│  │ ┌───────────────────────┐ │ │ └───────────────────────────┘ │   │
│  │ │ ETH-USDC  ● Running   │ │ │                               │   │
│  │ │ PnL: +$12.34          │ │ │                               │   │
│  │ └───────────────────────┘ │ │                               │   │
│  └───────────────────────────┘ └───────────────────────────────┘   │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### 2. Grid Trading 控制面板

```
┌─────────────────────────────────────────────────────────────────────┐
│  Grid Trading                                        [+ New Grid]   │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │                      Price Chart + Grid Levels                 │  │
│  │  100000 ┬─────────────────────────── Upper Bound              │  │
│  │         │     ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄ Sell Order                │  │
│  │   98000 │     ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄                            │  │
│  │         │  ╱╲                                                  │  │
│  │   96000 │ ╱  ╲    ← Current Price                             │  │
│  │         │╱    ╲                                                │  │
│  │   94000 ├───────────────────────── Buy Order (filled)         │  │
│  │         │     ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄ Buy Order                 │  │
│  │   92000 │     ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄                            │  │
│  │   90000 ┴─────────────────────────── Lower Bound              │  │
│  └───────────────────────────────────────────────────────────────┘  │
│                                                                      │
│  ┌─────────────────────────────┐ ┌─────────────────────────────┐   │
│  │        Grid Control         │ │        Grid Status          │   │
│  │                             │ │                             │   │
│  │  Status: ● Running          │ │  Current Price: $95,123     │   │
│  │                             │ │  Position: 0.003 BTC        │   │
│  │  [■ Stop]  [⟳ Restart]     │ │  Unrealized PnL: +$15.67    │   │
│  │                             │ │  Realized PnL: +$45.23      │   │
│  │  ─────────────────────────  │ │  Total Trades: 15           │   │
│  │                             │ │                             │   │
│  │  Take Profit: 0.5%          │ │  Buy Orders: 3 active       │   │
│  │  [Edit Parameters]          │ │  Sell Orders: 2 active      │   │
│  │                             │ │                             │   │
│  │  ─────────────────────────  │ │  Risk Checks: 45            │   │
│  │                             │ │  Orders Rejected: 2         │   │
│  │  Risk Management: ✓ On      │ │  Kill Switch: Off           │   │
│  │                             │ │                             │   │
│  └─────────────────────────────┘ └─────────────────────────────┘   │
│                                                                      │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │                         Order Book                             │  │
│  │  ┌─────────────────────────┬─────────────────────────────┐    │  │
│  │  │      Buy Orders         │       Sell Orders           │    │  │
│  │  ├─────────────────────────┼─────────────────────────────┤    │  │
│  │  │ Level 0: $90,000 pending│ Level 2: $94,470 active     │    │  │
│  │  │ Level 1: $92,000 pending│                              │    │  │
│  │  │ Level 2: $94,000 filled │                              │    │  │
│  │  └─────────────────────────┴─────────────────────────────┘    │  │
│  └───────────────────────────────────────────────────────────────┘  │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### 3. Backtest 中心

```
┌─────────────────────────────────────────────────────────────────────┐
│  Backtest Center                                    [+ New Backtest]│
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  ┌─────────────────────────────────┐ ┌─────────────────────────┐   │
│  │      Backtest Configuration     │ │    Running Backtests    │   │
│  │                                  │ │                         │   │
│  │  Strategy: [Dual MA        ▼]   │ │  ┌─────────────────────┐│   │
│  │                                  │ │  │ BT-001 Dual MA      ││   │
│  │  Parameters:                     │ │  │ ████████░░ 80%      ││   │
│  │    Fast Period: [10]             │ │  │ ETA: 30s            ││   │
│  │    Slow Period: [30]             │ │  └─────────────────────┘│   │
│  │                                  │ │                         │   │
│  │  Data:                           │ │  ┌─────────────────────┐│   │
│  │    Symbol: [BTCUSDT      ▼]     │ │  │ BT-002 Grid         ││   │
│  │    Timeframe: [1h        ▼]     │ │  │ ██████░░░░ 60%      ││   │
│  │    Start: [2024-01-01]           │ │  │ ETA: 45s            ││   │
│  │    End:   [2024-12-31]           │ │  └─────────────────────┘│   │
│  │                                  │ │                         │   │
│  │  Config:                         │ │                         │   │
│  │    Initial Capital: [10000]      │ │                         │   │
│  │    Commission: [0.05%]           │ │                         │   │
│  │                                  │ │                         │   │
│  │  [        Run Backtest        ]  │ │                         │   │
│  │                                  │ │                         │   │
│  └─────────────────────────────────┘ └─────────────────────────┘   │
│                                                                      │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │                      Backtest Results                          │  │
│  │ ┌─────────┬─────────┬─────────┬─────────┬─────────┬────────┐  │  │
│  │ │   ID    │Strategy │  Return │  Sharpe │Max DD   │ Status │  │  │
│  │ ├─────────┼─────────┼─────────┼─────────┼─────────┼────────┤  │  │
│  │ │ BT-003  │ Dual MA │ +25.3%  │  1.85   │ -12.1%  │ ✓ Done │  │  │
│  │ │ BT-004  │ RSI Rev │ +18.7%  │  1.42   │ -8.5%   │ ✓ Done │  │  │
│  │ │ BT-005  │ Grid    │ +32.1%  │  2.12   │ -6.3%   │ ✓ Done │  │  │
│  │ └─────────┴─────────┴─────────┴─────────┴─────────┴────────┘  │  │
│  └───────────────────────────────────────────────────────────────┘  │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 🔌 API 层设计

### HTTP 客户端

```typescript
// src/api/client.ts
import axios, { AxiosInstance } from 'axios';
import { useAuthStore } from '@/stores/authStore';

const API_BASE_URL = import.meta.env.VITE_API_URL || 'http://localhost:8080';

export const apiClient: AxiosInstance = axios.create({
  baseURL: `${API_BASE_URL}/api/v2`,
  timeout: 30000,
  headers: {
    'Content-Type': 'application/json',
  },
});

// 请求拦截器 - 添加 Token
apiClient.interceptors.request.use((config) => {
  const token = useAuthStore.getState().token;
  if (token) {
    config.headers.Authorization = `Bearer ${token}`;
  }
  return config;
});

// 响应拦截器 - 处理错误
apiClient.interceptors.response.use(
  (response) => response,
  async (error) => {
    if (error.response?.status === 401) {
      useAuthStore.getState().logout();
      window.location.href = '/login';
    }
    return Promise.reject(error);
  }
);
```

### WebSocket 客户端

```typescript
// src/api/websocket.ts
import { useAuthStore } from '@/stores/authStore';

type MessageHandler = (data: any) => void;

class ZigQuantWebSocket {
  private ws: WebSocket | null = null;
  private url: string;
  private reconnectAttempts = 0;
  private maxReconnectAttempts = 10;
  private subscriptions = new Set<string>();
  private handlers = new Map<string, Set<MessageHandler>>();
  private commandCallbacks = new Map<string, (res: any) => void>();

  constructor() {
    this.url = import.meta.env.VITE_WS_URL || 'ws://localhost:8080/ws';
  }

  connect(): Promise<void> {
    return new Promise((resolve, reject) => {
      const token = useAuthStore.getState().token;
      this.ws = new WebSocket(`${this.url}?token=${token}`);

      this.ws.onopen = () => {
        this.reconnectAttempts = 0;
        this.resubscribe();
        resolve();
      };

      this.ws.onmessage = (event) => {
        const msg = JSON.parse(event.data);
        this.handleMessage(msg);
      };

      this.ws.onclose = () => {
        this.reconnect();
      };

      this.ws.onerror = (error) => {
        reject(error);
      };
    });
  }

  subscribe(channels: string[]): void {
    channels.forEach(ch => this.subscriptions.add(ch));
    if (this.isConnected()) {
      this.send({ type: 'subscribe', channels });
    }
  }

  unsubscribe(channels: string[]): void {
    channels.forEach(ch => this.subscriptions.delete(ch));
    if (this.isConnected()) {
      this.send({ type: 'unsubscribe', channels });
    }
  }

  on(pattern: string, handler: MessageHandler): () => void {
    if (!this.handlers.has(pattern)) {
      this.handlers.set(pattern, new Set());
    }
    this.handlers.get(pattern)!.add(handler);

    // 返回取消订阅函数
    return () => {
      this.handlers.get(pattern)?.delete(handler);
    };
  }

  async command<T>(action: string, params: any): Promise<T> {
    return new Promise((resolve, reject) => {
      const id = `cmd_${Date.now()}_${Math.random().toString(36).slice(2)}`;

      this.commandCallbacks.set(id, (res) => {
        this.commandCallbacks.delete(id);
        if (res.success) {
          resolve(res.data);
        } else {
          reject(res.error);
        }
      });

      this.send({ type: 'command', id, action, params, timestamp: Date.now() });

      // 超时处理
      setTimeout(() => {
        if (this.commandCallbacks.has(id)) {
          this.commandCallbacks.delete(id);
          reject({ code: 'TIMEOUT', message: 'Command timeout' });
        }
      }, 30000);
    });
  }

  private handleMessage(msg: any): void {
    switch (msg.type) {
      case 'event':
        this.dispatchEvent(msg.channel, msg.data);
        break;
      case 'response':
        const callback = this.commandCallbacks.get(msg.id);
        if (callback) callback(msg);
        break;
      case 'ping':
        this.send({ type: 'pong', timestamp: Date.now() });
        break;
    }
  }

  private dispatchEvent(channel: string, data: any): void {
    this.handlers.forEach((handlers, pattern) => {
      if (this.matchPattern(pattern, channel)) {
        handlers.forEach(handler => handler(data));
      }
    });
  }

  private matchPattern(pattern: string, channel: string): boolean {
    if (pattern === '*') return true;
    const regex = pattern.replace(/\./g, '\\.').replace(/\*/g, '[^.]+');
    return new RegExp(`^${regex}$`).test(channel);
  }

  private reconnect(): void {
    if (this.reconnectAttempts >= this.maxReconnectAttempts) {
      console.error('WebSocket: Max reconnect attempts reached');
      return;
    }

    const delay = Math.min(1000 * Math.pow(2, this.reconnectAttempts), 30000);
    setTimeout(() => {
      this.reconnectAttempts++;
      this.connect().catch(() => this.reconnect());
    }, delay);
  }

  private resubscribe(): void {
    if (this.subscriptions.size > 0) {
      this.send({ type: 'subscribe', channels: Array.from(this.subscriptions) });
    }
  }

  private send(msg: any): void {
    if (this.isConnected()) {
      this.ws!.send(JSON.stringify(msg));
    }
  }

  private isConnected(): boolean {
    return this.ws?.readyState === WebSocket.OPEN;
  }

  disconnect(): void {
    this.ws?.close();
    this.ws = null;
  }
}

export const wsClient = new ZigQuantWebSocket();
```

### TanStack Query Hooks

```typescript
// src/api/hooks/useGrid.ts
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { apiClient } from '../client';
import { wsClient } from '../websocket';
import { useEffect } from 'react';
import type { GridConfig, GridStatus, GridList } from '@/types/grid';

// 获取网格列表
export function useGridList() {
  return useQuery({
    queryKey: ['grids'],
    queryFn: async (): Promise<GridList> => {
      const { data } = await apiClient.get('/grid');
      return data.data;
    },
    refetchInterval: 30000, // 30秒刷新一次作为备份
  });
}

// 获取网格状态 + WebSocket 实时更新
export function useGridStatus(gridId: string) {
  const queryClient = useQueryClient();

  // REST 查询
  const query = useQuery({
    queryKey: ['grid', gridId, 'status'],
    queryFn: async (): Promise<GridStatus> => {
      const { data } = await apiClient.get(`/grid/${gridId}/status`);
      return data.data;
    },
    enabled: !!gridId,
  });

  // WebSocket 实时更新
  useEffect(() => {
    if (!gridId) return;

    wsClient.subscribe([`grid.${gridId}.status`]);

    const unsubscribe = wsClient.on(`grid.${gridId}.status`, (data) => {
      queryClient.setQueryData(['grid', gridId, 'status'], data);
    });

    return () => {
      wsClient.unsubscribe([`grid.${gridId}.status`]);
      unsubscribe();
    };
  }, [gridId, queryClient]);

  return query;
}

// 启动网格
export function useStartGrid() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async (config: GridConfig) => {
      const { data } = await apiClient.post('/grid/start', config);
      return data.data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['grids'] });
    },
  });
}

// 停止网格
export function useStopGrid() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async ({ gridId, cancelOrders = true }: { gridId: string; cancelOrders?: boolean }) => {
      const { data } = await apiClient.post(`/grid/${gridId}/stop`, { cancel_orders: cancelOrders });
      return data.data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['grids'] });
    },
  });
}

// 更新网格参数
export function useUpdateGridParams() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async ({ gridId, params }: { gridId: string; params: Partial<GridConfig> }) => {
      const { data } = await apiClient.put(`/grid/${gridId}/params`, params);
      return data.data;
    },
    onSuccess: (_, { gridId }) => {
      queryClient.invalidateQueries({ queryKey: ['grid', gridId] });
    },
  });
}
```

---

## 📦 状态管理

### Zustand Store 示例

```typescript
// src/stores/gridStore.ts
import { create } from 'zustand';
import { devtools, persist } from 'zustand/middleware';
import type { GridStatus } from '@/types/grid';

interface GridState {
  // 状态
  activeGrids: Map<string, GridStatus>;
  selectedGridId: string | null;

  // Actions
  setGridStatus: (gridId: string, status: GridStatus) => void;
  removeGrid: (gridId: string) => void;
  selectGrid: (gridId: string | null) => void;
}

export const useGridStore = create<GridState>()(
  devtools(
    persist(
      (set) => ({
        activeGrids: new Map(),
        selectedGridId: null,

        setGridStatus: (gridId, status) =>
          set((state) => {
            const newMap = new Map(state.activeGrids);
            newMap.set(gridId, status);
            return { activeGrids: newMap };
          }),

        removeGrid: (gridId) =>
          set((state) => {
            const newMap = new Map(state.activeGrids);
            newMap.delete(gridId);
            return { activeGrids: newMap };
          }),

        selectGrid: (gridId) => set({ selectedGridId: gridId }),
      }),
      {
        name: 'grid-storage',
        partialize: (state) => ({ selectedGridId: state.selectedGridId }),
      }
    )
  )
);
```

---

## 🚀 开发和构建

### 初始化项目

```bash
# 创建项目
mkdir web && cd web
bun init

# 安装依赖
bun add react react-dom
bun add -d @types/react @types/react-dom
bun add vite @vitejs/plugin-react -d
bun add typescript -d

# UI 和样式
bun add tailwindcss postcss autoprefixer -d
bunx tailwindcss init -p

# 状态管理和数据获取
bun add zustand @tanstack/react-query axios

# 路由
bun add react-router-dom

# UI 组件 (shadcn/ui 需要手动添加)
bunx shadcn-ui@latest init

# 图表
bun add recharts lightweight-charts

# 表单和验证
bun add react-hook-form @hookform/resolvers zod
```

### 开发命令

```bash
# 开发服务器
bun run dev

# 类型检查
bun run typecheck

# 构建
bun run build

# 预览
bun run preview

# 代码检查
bun run lint
```

### Vite 配置

```typescript
// vite.config.ts
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import path from 'path';

export default defineConfig({
  plugins: [react()],
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src'),
    },
  },
  server: {
    port: 3000,
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
});
```

---

## 📱 响应式设计

使用 Tailwind 断点：

```css
/* 移动优先设计 */
sm: 640px   /* 小屏幕 */
md: 768px   /* 平板 */
lg: 1024px  /* 小桌面 */
xl: 1280px  /* 桌面 */
2xl: 1536px /* 大桌面 */
```

Dashboard 在移动端使用抽屉式导航，卡片垂直堆叠。

---

*创建时间: 2025-12-29*
