# 迁移指南

> 从 CLI 工具到 Web 控制平台的迁移步骤

**版本**: v2.0.0
**状态**: 📋 设计阶段
**创建日期**: 2025-12-29

---

## 📋 概述

本文档描述如何将现有 CLI 功能迁移到 Web 控制平台，同时保持 CLI 功能可用。

---

## 🎯 迁移目标

| 功能 | CLI 命令 | Web 控制 |
|------|----------|----------|
| 网格交易 | `zigquant grid ...` | Dashboard 控制面板 |
| 回测 | `zigquant backtest ...` | Backtest Center |
| 策略运行 | `zigquant run-strategy ...` | Strategy Manager |
| Paper Trading | `zigquant paper ...` | Paper Trading Mode |
| Kill Switch | `zigquant kill-switch` | System Controls |

---

## 📅 迁移计划

### Phase 1: 后端基础设施 (Week 1-2)

#### 1.1 Engine Manager 实现

创建统一的引擎管理器，管理所有运行中的策略/网格/回测。

**新文件**: `src/engine/manager.zig`

```zig
//! Engine Manager - 统一引擎管理
//!
//! 管理所有运行中的:
//! - Grid Trading 实例
//! - Strategy 实例
//! - Backtest 任务
//! - Paper Trading 会话

pub const EngineManager = struct {
    allocator: Allocator,
    
    // 运行中的实例
    grids: std.StringHashMap(*GridRunner),
    strategies: std.StringHashMap(*StrategyRunner),
    backtests: std.StringHashMap(*BacktestRunner),
    
    // 消息总线 (用于事件发布)
    message_bus: *MessageBus,
    
    // 状态持久化
    data_store: *DataStore,
    
    // Kill Switch 状态
    kill_switch_active: bool,
    
    pub fn init(allocator: Allocator) !*EngineManager;
    pub fn deinit(self: *EngineManager) void;
    
    // 网格管理
    pub fn startGrid(self: *EngineManager, config: GridConfig) ![]const u8;
    pub fn stopGrid(self: *EngineManager, id: []const u8) !void;
    pub fn updateGridParams(self: *EngineManager, id: []const u8, params: GridParams) !void;
    pub fn getGridStatus(self: *EngineManager, id: []const u8) ?GridStatus;
    pub fn listGrids(self: *EngineManager) []GridSummary;
    
    // 策略管理
    pub fn startStrategy(self: *EngineManager, config: StrategyConfig) ![]const u8;
    pub fn stopStrategy(self: *EngineManager, id: []const u8) !void;
    
    // 回测管理
    pub fn runBacktest(self: *EngineManager, config: BacktestConfig) ![]const u8;
    pub fn cancelBacktest(self: *EngineManager, id: []const u8) !void;
    
    // 系统控制
    pub fn activateKillSwitch(self: *EngineManager, reason: []const u8) !KillSwitchResult;
    pub fn deactivateKillSwitch(self: *EngineManager) !void;
    
    // 状态恢复
    pub fn loadState(self: *EngineManager) !void;
    pub fn saveState(self: *EngineManager) !void;
};
```

#### 1.2 GridRunner 包装器

将现有 GridBot 包装成可管理的 Runner。

**新文件**: `src/engine/runners/grid_runner.zig`

```zig
//! GridRunner - 网格交易运行器
//!
//! 包装 GridBot，提供:
//! - 生命周期管理
//! - 事件发布
//! - 状态查询

pub const GridRunner = struct {
    id: []const u8,
    config: GridConfig,
    status: GridStatus,
    
    // 内部组件
    bot: *GridBot,
    thread: ?std.Thread,
    running: std.atomic.Value(bool),
    
    // 事件发布
    message_bus: *MessageBus,
    
    pub fn start(self: *GridRunner) !void;
    pub fn stop(self: *GridRunner) !void;
    pub fn updateParams(self: *GridRunner, params: GridParams) !void;
    pub fn getStatus(self: *GridRunner) GridStatus;
    
    // 事件回调 (用于发布到 MessageBus)
    fn onOrderPlaced(self: *GridRunner, order: Order) void;
    fn onOrderFilled(self: *GridRunner, fill: Fill) void;
    fn onStatusUpdate(self: *GridRunner) void;
};
```

#### 1.3 WebSocket 服务端

在现有 HTTP 服务器基础上添加 WebSocket 支持。

**新文件**: `src/api/v2/websocket.zig`

```zig
//! WebSocket Server
//!
//! 处理:
//! - 连接升级
//! - 订阅管理
//! - 消息广播
//! - 命令接收

pub const WebSocketServer = struct {
    allocator: Allocator,
    connections: std.ArrayList(*Connection),
    subscriptions: std.StringHashMap(std.ArrayList(*Connection)),
    engine_manager: *EngineManager,
    
    pub fn handleUpgrade(self: *WebSocketServer, request: *Request) !void;
    pub fn broadcast(self: *WebSocketServer, channel: []const u8, event: Event) void;
    pub fn handleMessage(self: *WebSocketServer, conn: *Connection, msg: Message) !void;
};
```

#### 1.4 V2 API Handlers

实现真正的控制 handlers（不再是 placeholder）。

**新文件**: `src/api/v2/handlers/grid.zig`

```zig
pub fn handleStartGrid(
    ctx: *Context,
    engine: *EngineManager,
) !void {
    const body = try ctx.parseJson(GridStartRequest);
    
    // 验证配置
    try body.config.validate();
    
    // 启动网格
    const grid_id = try engine.startGrid(body.config);
    
    // 返回结果
    try ctx.json(.{
        .success = true,
        .data = .{
            .id = grid_id,
            .status = "starting",
        },
    });
}

pub fn handleStopGrid(
    ctx: *Context,
    engine: *EngineManager,
) !void {
    const grid_id = ctx.params.get("id") orelse return error.MissingId;
    
    try engine.stopGrid(grid_id);
    
    try ctx.json(.{
        .success = true,
        .data = .{
            .id = grid_id,
            .status = "stopped",
        },
    });
}
```

### Phase 2: 前端开发 (Week 3-4)

#### 2.1 项目初始化

```bash
cd zigQuant
mkdir web
cd web

# 使用 Bun 初始化
bun create vite . --template react-ts

# 安装依赖
bun add zustand @tanstack/react-query axios react-router-dom
bun add -d tailwindcss postcss autoprefixer
bun add recharts lightweight-charts
bun add react-hook-form @hookform/resolvers zod

# 初始化 Tailwind
bunx tailwindcss init -p

# 添加 shadcn/ui
bunx shadcn-ui@latest init
```

#### 2.2 核心组件开发

1. **WebSocket Provider**: 全局 WebSocket 连接管理
2. **GridControl**: 网格交易控制面板
3. **BacktestRunner**: 回测配置和执行
4. **SystemHealth**: 系统状态监控

#### 2.3 页面开发

| 页面 | 路由 | 功能 |
|------|------|------|
| Dashboard | `/` | 总览、快速操作 |
| Grid Trading | `/grid` | 网格控制、状态监控 |
| Backtest | `/backtest` | 回测配置、结果查看 |
| Strategies | `/strategies` | 策略管理 |
| Settings | `/settings` | 系统设置 |

### Phase 3: 集成测试 (Week 5)

#### 3.1 端到端测试

```typescript
// tests/e2e/grid.spec.ts
import { test, expect } from '@playwright/test';

test('start and stop grid trading', async ({ page }) => {
  await page.goto('/grid');
  
  // 填写配置
  await page.fill('[name="pair"]', 'BTC-USDC');
  await page.fill('[name="upper_price"]', '100000');
  await page.fill('[name="lower_price"]', '90000');
  await page.fill('[name="grid_count"]', '10');
  
  // 启动
  await page.click('button:has-text("Start Grid")');
  
  // 验证状态
  await expect(page.locator('.grid-status')).toContainText('Running');
  
  // 停止
  await page.click('button:has-text("Stop")');
  await expect(page.locator('.grid-status')).toContainText('Stopped');
});
```

#### 3.2 API 测试

```typescript
// tests/api/grid.test.ts
describe('Grid API', () => {
  test('POST /api/v2/grid/start', async () => {
    const response = await fetch('/api/v2/grid/start', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        pair: 'BTC-USDC',
        upper_price: 100000,
        lower_price: 90000,
        grid_count: 10,
        mode: 'paper',
      }),
    });
    
    expect(response.ok).toBe(true);
    const data = await response.json();
    expect(data.success).toBe(true);
    expect(data.data.id).toBeDefined();
  });
});
```

### Phase 4: 部署和文档 (Week 6)

#### 4.1 Docker 部署

```dockerfile
# Dockerfile.web
FROM oven/bun:1 AS builder

WORKDIR /app
COPY web/package.json web/bun.lockb ./
RUN bun install --frozen-lockfile

COPY web/ .
RUN bun run build

FROM nginx:alpine
COPY --from=builder /app/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/nginx.conf
EXPOSE 80
```

```yaml
# docker-compose.yml
version: '3.8'
services:
  api:
    build: .
    ports:
      - "8080:8080"
    volumes:
      - ./config.json:/app/config.json
      - ./data:/app/data
  
  web:
    build:
      context: .
      dockerfile: Dockerfile.web
    ports:
      - "80:80"
    depends_on:
      - api
```

#### 4.2 更新文档

- [ ] 更新 README.md
- [ ] 更新 QUICK_START.md
- [ ] 添加 Web 控制平台用户指南
- [ ] 添加 API V2 文档到 docs/

---

## 📝 代码修改清单

### 后端修改

| 文件 | 修改类型 | 说明 |
|------|----------|------|
| `src/engine/mod.zig` | 新增 | 引擎模块入口 |
| `src/engine/manager.zig` | 新增 | 引擎管理器 |
| `src/engine/registry.zig` | 新增 | 策略注册表 |
| `src/engine/state.zig` | 新增 | 状态持久化 |
| `src/engine/runners/grid_runner.zig` | 新增 | 网格运行器 |
| `src/engine/runners/backtest_runner.zig` | 新增 | 回测运行器 |
| `src/api/v2/mod.zig` | 新增 | V2 API 入口 |
| `src/api/v2/server.zig` | 新增 | 增强版服务器 |
| `src/api/v2/websocket.zig` | 新增 | WebSocket 服务 |
| `src/api/v2/handlers/grid.zig` | 新增 | 网格 API 处理器 |
| `src/api/v2/handlers/backtest.zig` | 新增 | 回测 API 处理器 |
| `src/api/v2/handlers/system.zig` | 新增 | 系统 API 处理器 |
| `src/cli/commands/grid.zig` | 修改 | 使用 EngineManager |
| `src/root.zig` | 修改 | 导出新模块 |
| `src/main.zig` | 修改 | 启动 EngineManager |

### 前端新增

| 文件/目录 | 说明 |
|-----------|------|
| `web/` | 新前端项目根目录 |
| `web/src/api/` | API 客户端层 |
| `web/src/stores/` | Zustand 状态管理 |
| `web/src/components/` | UI 组件 |
| `web/src/pages/` | 页面组件 |

---

## 🔄 兼容性考虑

### CLI 保持可用

迁移后，CLI 命令仍然可用：

```bash
# 直接运行（不经过 API）
zigquant grid --pair BTC-USDC --upper 100000 --lower 90000 --paper

# 通过 API 运行
zigquant api-grid start --pair BTC-USDC --upper 100000 --lower 90000
```

### 现有 Dashboard 兼容

旧的 Vue Dashboard 仍可使用（V1 API），新 React 前端使用 V2 API。

```
/api/v1/* -> 现有 API (保留)
/api/v2/* -> 新 API (带 WebSocket)
```

---

## ⚠️ 风险和缓解

| 风险 | 影响 | 缓解措施 |
|------|------|----------|
| WebSocket 不稳定 | 实时更新丢失 | REST 轮询作为备份 |
| 状态不同步 | 显示错误 | 定期全量同步 |
| 性能问题 | 卡顿 | 增量更新、虚拟列表 |
| 认证过期 | 操作失败 | 自动刷新 Token |

---

## 📊 成功指标

| 指标 | 目标 |
|------|------|
| WebSocket 延迟 | < 50ms |
| 前端首屏加载 | < 2s |
| API 响应时间 | < 100ms |
| 控制操作延迟 | < 200ms |
| 错误率 | < 0.1% |

---

*创建时间: 2025-12-29*
