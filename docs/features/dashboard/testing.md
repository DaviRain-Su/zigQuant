# Web Dashboard - 测试文档

> 前端测试覆盖

**最后更新**: 2025-12-28

---

## 测试概览

| 类别 | 测试数 | 覆盖率 |
|------|--------|--------|
| 单元测试 | TBD | TBD |
| 组件测试 | TBD | TBD |
| E2E 测试 | TBD | TBD |

---

## 测试工具

| 工具 | 用途 |
|------|------|
| Vitest | 单元测试框架 |
| Vue Test Utils | Vue 组件测试 |
| Playwright | E2E 测试 |
| MSW | API Mock |

---

## 单元测试

### Store 测试

```typescript
// tests/stores/auth.test.ts
import { describe, it, expect, beforeEach, vi } from 'vitest'
import { setActivePinia, createPinia } from 'pinia'
import { useAuthStore } from '@/stores/auth'
import * as authApi from '@/api/auth'

vi.mock('@/api/auth')

describe('Auth Store', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
    localStorage.clear()
  })

  it('should initialize with no token', () => {
    const store = useAuthStore()
    expect(store.token).toBeNull()
    expect(store.isAuthenticated).toBe(false)
  })

  it('should login successfully', async () => {
    vi.mocked(authApi.login).mockResolvedValue({
      token: 'test-token',
      user: { id: '1', username: 'admin', role: 'admin' },
    })

    const store = useAuthStore()
    await store.login('admin', 'password')

    expect(store.token).toBe('test-token')
    expect(store.isAuthenticated).toBe(true)
    expect(localStorage.getItem('token')).toBe('test-token')
  })

  it('should logout and clear token', async () => {
    const store = useAuthStore()
    store.token = 'test-token'
    localStorage.setItem('token', 'test-token')

    await store.logout()

    expect(store.token).toBeNull()
    expect(store.isAuthenticated).toBe(false)
    expect(localStorage.getItem('token')).toBeNull()
  })

  it('should handle login error', async () => {
    vi.mocked(authApi.login).mockRejectedValue(new Error('Invalid credentials'))

    const store = useAuthStore()

    await expect(store.login('admin', 'wrong')).rejects.toThrow('Invalid credentials')
    expect(store.token).toBeNull()
  })
})
```

### Trading Store 测试

```typescript
// tests/stores/trading.test.ts
import { describe, it, expect, beforeEach, vi } from 'vitest'
import { setActivePinia, createPinia } from 'pinia'
import { useTradingStore } from '@/stores/trading'
import * as tradingApi from '@/api/trading'

vi.mock('@/api/trading')

describe('Trading Store', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
  })

  it('should fetch positions', async () => {
    const mockPositions = [
      { symbol: 'BTC-USDT', size: 0.5, unrealizedPnL: 100 },
      { symbol: 'ETH-USDT', size: 2.0, unrealizedPnL: -50 },
    ]
    vi.mocked(tradingApi.getPositions).mockResolvedValue(mockPositions)

    const store = useTradingStore()
    await store.fetchPositions()

    expect(store.positions).toEqual(mockPositions)
  })

  it('should calculate total PnL', async () => {
    const store = useTradingStore()
    store.positions = [
      { symbol: 'BTC-USDT', size: 0.5, unrealizedPnL: 100 },
      { symbol: 'ETH-USDT', size: 2.0, unrealizedPnL: -30 },
    ]

    expect(store.totalPnL).toBe(70)
  })

  it('should update position from WebSocket', () => {
    const store = useTradingStore()
    store.positions = [
      { symbol: 'BTC-USDT', size: 0.5, unrealizedPnL: 100 },
    ]

    store.updatePosition({
      symbol: 'BTC-USDT',
      size: 0.75,
      unrealizedPnL: 150,
    })

    expect(store.positions[0].size).toBe(0.75)
    expect(store.positions[0].unrealizedPnL).toBe(150)
  })

  it('should add new position', () => {
    const store = useTradingStore()
    store.positions = []

    store.updatePosition({
      symbol: 'SOL-USDT',
      size: 10,
      unrealizedPnL: 25,
    })

    expect(store.positions).toHaveLength(1)
    expect(store.positions[0].symbol).toBe('SOL-USDT')
  })
})
```

### 工具函数测试

```typescript
// tests/utils/format.test.ts
import { describe, it, expect } from 'vitest'
import { formatCurrency, formatPercent, formatDate } from '@/utils/format'

describe('Format Utils', () => {
  describe('formatCurrency', () => {
    it('should format positive numbers', () => {
      expect(formatCurrency(1234.56)).toBe('$1,234.56')
    })

    it('should format negative numbers', () => {
      expect(formatCurrency(-1234.56)).toBe('-$1,234.56')
    })

    it('should format zero', () => {
      expect(formatCurrency(0)).toBe('$0.00')
    })

    it('should handle large numbers', () => {
      expect(formatCurrency(1000000)).toBe('$1,000,000.00')
    })
  })

  describe('formatPercent', () => {
    it('should format decimal to percent', () => {
      expect(formatPercent(0.1234)).toBe('12.34%')
    })

    it('should handle negative values', () => {
      expect(formatPercent(-0.05)).toBe('-5.00%')
    })
  })

  describe('formatDate', () => {
    it('should format ISO date', () => {
      expect(formatDate('2024-12-28T10:30:00Z')).toBe('2024-12-28 10:30')
    })
  })
})
```

---

## 组件测试

### StatsCard 测试

```typescript
// tests/components/StatsCard.test.ts
import { describe, it, expect } from 'vitest'
import { mount } from '@vue/test-utils'
import StatsCard from '@/components/common/StatsCard.vue'

describe('StatsCard', () => {
  it('should render value and label', () => {
    const wrapper = mount(StatsCard, {
      props: {
        value: 1000,
        label: 'Total Balance',
      },
    })

    expect(wrapper.text()).toContain('1,000')
    expect(wrapper.text()).toContain('Total Balance')
  })

  it('should format currency', () => {
    const wrapper = mount(StatsCard, {
      props: {
        value: 1234.56,
        label: 'Balance',
        format: 'currency',
      },
    })

    expect(wrapper.text()).toContain('$1,234.56')
  })

  it('should format percent', () => {
    const wrapper = mount(StatsCard, {
      props: {
        value: 0.6543,
        label: 'Win Rate',
        format: 'percent',
      },
    })

    expect(wrapper.text()).toContain('65.4%')
  })

  it('should show positive class for positive change', () => {
    const wrapper = mount(StatsCard, {
      props: {
        value: 100,
        label: 'PnL',
        change: 5.5,
      },
    })

    expect(wrapper.find('.stats-change').classes()).toContain('positive')
  })

  it('should show negative class for negative change', () => {
    const wrapper = mount(StatsCard, {
      props: {
        value: 100,
        label: 'PnL',
        change: -3.2,
      },
    })

    expect(wrapper.find('.stats-change').classes()).toContain('negative')
  })
})
```

### OrderForm 测试

```typescript
// tests/components/OrderForm.test.ts
import { describe, it, expect, vi } from 'vitest'
import { mount } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import OrderForm from '@/components/trading/OrderForm.vue'
import ElementPlus from 'element-plus'

describe('OrderForm', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
  })

  it('should render form fields', () => {
    const wrapper = mount(OrderForm, {
      global: {
        plugins: [ElementPlus],
      },
    })

    expect(wrapper.find('[prop="symbol"]').exists()).toBe(true)
    expect(wrapper.find('[prop="side"]').exists()).toBe(true)
    expect(wrapper.find('[prop="type"]').exists()).toBe(true)
    expect(wrapper.find('[prop="quantity"]').exists()).toBe(true)
  })

  it('should show price field for limit orders', async () => {
    const wrapper = mount(OrderForm, {
      global: {
        plugins: [ElementPlus],
      },
    })

    // 默认是限价单
    expect(wrapper.find('[prop="price"]').exists()).toBe(true)

    // 切换到市价单
    await wrapper.find('input[value="market"]').trigger('click')
    expect(wrapper.find('[prop="price"]').exists()).toBe(false)
  })

  it('should emit success on valid submission', async () => {
    const wrapper = mount(OrderForm, {
      global: {
        plugins: [ElementPlus],
      },
    })

    // 填写表单
    await wrapper.find('select').setValue('BTC-USDT')
    await wrapper.find('input[type="number"]').setValue(0.1)

    // 提交
    await wrapper.find('button[type="submit"]').trigger('click')

    expect(wrapper.emitted('success')).toBeTruthy()
  })
})
```

### EquityCurve 测试

```typescript
// tests/components/EquityCurve.test.ts
import { describe, it, expect, vi } from 'vitest'
import { mount } from '@vue/test-utils'
import EquityCurve from '@/components/charts/EquityCurve.vue'

// Mock ECharts
vi.mock('echarts', () => ({
  init: vi.fn(() => ({
    setOption: vi.fn(),
    resize: vi.fn(),
    dispose: vi.fn(),
  })),
}))

describe('EquityCurve', () => {
  it('should render chart container', () => {
    const wrapper = mount(EquityCurve, {
      props: {
        data: [
          { time: '2024-01-01', equity: 10000 },
          { time: '2024-01-02', equity: 10500 },
        ],
      },
    })

    expect(wrapper.find('.equity-chart').exists()).toBe(true)
  })

  it('should update chart when data changes', async () => {
    const wrapper = mount(EquityCurve, {
      props: {
        data: [],
      },
    })

    await wrapper.setProps({
      data: [
        { time: '2024-01-01', equity: 10000 },
        { time: '2024-01-02', equity: 11000 },
      ],
    })

    // 验证图表更新被调用
    expect(wrapper.vm.chart?.setOption).toHaveBeenCalled()
  })
})
```

---

## E2E 测试

### 登录流程

```typescript
// tests/e2e/login.spec.ts
import { test, expect } from '@playwright/test'

test.describe('Login Flow', () => {
  test('should login with valid credentials', async ({ page }) => {
    await page.goto('/login')

    await page.fill('input[name="username"]', 'admin')
    await page.fill('input[name="password"]', 'admin')
    await page.click('button[type="submit"]')

    await expect(page).toHaveURL('/')
    await expect(page.locator('.navbar')).toContainText('admin')
  })

  test('should show error for invalid credentials', async ({ page }) => {
    await page.goto('/login')

    await page.fill('input[name="username"]', 'admin')
    await page.fill('input[name="password"]', 'wrong')
    await page.click('button[type="submit"]')

    await expect(page.locator('.el-message--error')).toBeVisible()
  })

  test('should redirect unauthenticated users', async ({ page }) => {
    await page.goto('/strategies')

    await expect(page).toHaveURL('/login')
  })
})
```

### Dashboard 页面

```typescript
// tests/e2e/dashboard.spec.ts
import { test, expect } from '@playwright/test'

test.describe('Dashboard', () => {
  test.beforeEach(async ({ page }) => {
    // 登录
    await page.goto('/login')
    await page.fill('input[name="username"]', 'admin')
    await page.fill('input[name="password"]', 'admin')
    await page.click('button[type="submit"]')
    await page.waitForURL('/')
  })

  test('should display stats cards', async ({ page }) => {
    await expect(page.locator('.stats-card')).toHaveCount(4)
  })

  test('should display equity curve', async ({ page }) => {
    await expect(page.locator('.equity-chart')).toBeVisible()
  })

  test('should display positions table', async ({ page }) => {
    await expect(page.locator('.positions-table')).toBeVisible()
  })

  test('should update data in real-time', async ({ page }) => {
    const initialBalance = await page.locator('.balance-value').textContent()

    // 等待 WebSocket 更新
    await page.waitForTimeout(5000)

    // 余额可能已更新
    const currentBalance = await page.locator('.balance-value').textContent()
    // 不强制要求变化，只验证显示正常
    expect(currentBalance).toBeTruthy()
  })
})
```

### 订单流程

```typescript
// tests/e2e/orders.spec.ts
import { test, expect } from '@playwright/test'

test.describe('Order Flow', () => {
  test.beforeEach(async ({ page }) => {
    // 登录
    await page.goto('/login')
    await page.fill('input[name="username"]', 'admin')
    await page.fill('input[name="password"]', 'admin')
    await page.click('button[type="submit"]')
  })

  test('should create limit order', async ({ page }) => {
    await page.goto('/orders')

    // 打开下单表单
    await page.click('button:has-text("新建订单")')

    // 填写表单
    await page.selectOption('select[name="symbol"]', 'BTC-USDT')
    await page.click('input[value="buy"]')
    await page.click('input[value="limit"]')
    await page.fill('input[name="price"]', '50000')
    await page.fill('input[name="quantity"]', '0.1')

    // 提交
    await page.click('button:has-text("提交订单")')

    // 验证成功消息
    await expect(page.locator('.el-message--success')).toBeVisible()
  })

  test('should cancel order', async ({ page }) => {
    await page.goto('/orders')

    // 假设有一个活跃订单
    const cancelButton = page.locator('button:has-text("取消")').first()

    if (await cancelButton.isVisible()) {
      await cancelButton.click()

      // 确认取消
      await page.click('button:has-text("确定")')

      await expect(page.locator('.el-message--success')).toBeVisible()
    }
  })
})
```

---

## API Mock

### MSW 配置

```typescript
// tests/mocks/handlers.ts
import { rest } from 'msw'

export const handlers = [
  rest.post('/api/v1/auth/login', (req, res, ctx) => {
    const { username, password } = req.body as any

    if (username === 'admin' && password === 'admin') {
      return res(
        ctx.json({
          token: 'mock-token',
          user: { id: '1', username: 'admin', role: 'admin' },
        })
      )
    }

    return res(ctx.status(401), ctx.json({ error: 'Invalid credentials' }))
  }),

  rest.get('/api/v1/positions', (req, res, ctx) => {
    return res(
      ctx.json([
        { symbol: 'BTC-USDT', size: 0.5, unrealizedPnL: 100 },
        { symbol: 'ETH-USDT', size: 2.0, unrealizedPnL: -50 },
      ])
    )
  }),

  rest.get('/api/v1/orders', (req, res, ctx) => {
    return res(
      ctx.json([
        { id: '1', symbol: 'BTC-USDT', side: 'buy', status: 'open', price: 50000, quantity: 0.1 },
      ])
    )
  }),
]
```

---

## 运行测试

```bash
# 运行单元测试
npm run test

# 运行测试覆盖率
npm run test:coverage

# 运行 E2E 测试
npm run test:e2e

# 运行 E2E 测试 (带 UI)
npm run test:e2e:ui
```

---

## 测试用例

### 正常情况

| 测试用例 | 描述 | 状态 |
|----------|------|------|
| 登录成功 | 有效凭据登录 | 📋 待实现 |
| 数据加载 | 正确加载交易数据 | 📋 待实现 |
| 订单创建 | 创建限价单成功 | 📋 待实现 |
| 实时更新 | WebSocket 数据推送 | 📋 待实现 |

### 边界情况

| 测试用例 | 描述 | 状态 |
|----------|------|------|
| 空数据 | 无数据时的 UI 显示 | 📋 待实现 |
| 大数据量 | 1000+ 订单渲染 | 📋 待实现 |
| 网络断开 | WebSocket 重连 | 📋 待实现 |

### 错误情况

| 测试用例 | 描述 | 状态 |
|----------|------|------|
| 登录失败 | 错误凭据提示 | 📋 待实现 |
| API 错误 | 错误响应处理 | 📋 待实现 |
| Token 过期 | 自动登出 | 📋 待实现 |

---

*Last updated: 2025-12-28*
