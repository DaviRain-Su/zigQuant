# Technical Indicators Library 变更历史

**模块**: Technical Indicators Library
**初始版本**: v0.3.0

---

## [0.3.0] - 2025-12-25（计划中）

### Added

#### 核心指标

- ✨ **SMA (Simple Moving Average)** - 简单移动平均
  - 标准 SMA 算法实现
  - 支持任意周期配置
  - O(n×period) 时间复杂度
  - 性能目标: < 500μs (1000 candles, period=20)

- ✨ **EMA (Exponential Moving Average)** - 指数移动平均
  - 标准 EMA 算法实现
  - α = 2 / (period + 1)
  - O(n) 时间复杂度
  - 性能目标: < 400μs (1000 candles, period=20)

- ✨ **RSI (Relative Strength Index)** - 相对强弱指标
  - Wilder's Smoothing 方法
  - 标准 14 周期配置
  - 超买/超卖阈值识别
  - 性能目标: < 600μs (1000 candles, period=14)

- ✨ **MACD (Moving Average Convergence Divergence)**
  - 标准 MACD 计算 (12, 26, 9)
  - 返回 MACD Line, Signal Line, Histogram
  - 基于 EMA 实现
  - 性能目标: < 800μs (1000 candles)

- ✨ **Bollinger Bands** - 布林带
  - 标准 BB 计算 (20, 2.0)
  - 返回 Upper, Middle, Lower
  - 基于 SMA 和标准差
  - 性能目标: < 700μs (1000 candles)

#### 指标管理

- ✨ **IIndicator 接口** - 统一指标接口
  - `calculate()` - 计算指标值
  - `getName()` - 获取指标名称
  - `getRequiredCandles()` - 获取所需蜡烛数

- ✨ **IndicatorManager** - 指标缓存管理
  - 自动缓存计算结果
  - 蜡烛数据变化检测
  - 参数哈希验证
  - 内存自动管理

#### 工具函数

- ✨ **统计函数**
  - `calculateStdDev()` - 计算标准差
  - `calculateVariance()` - 计算方差
  - `calculateMean()` - 计算平均值

- ✨ **辅助函数**
  - `hashCandles()` - 蜡烛数据哈希
  - `hashParameters()` - 参数哈希

### Documentation

- 📚 完整的指标库文档
  - README.md - 功能概述和快速开始
  - api.md - 完整 API 参考
  - implementation.md - 实现细节说明
  - testing.md - 测试策略和用例
  - bugs.md - Bug 追踪
  - changelog.md - 变更历史

### Tests

- ✅ SMA 单元测试
  - 基本计算测试
  - 边界条件测试（period=1, 数据不足等）
  - 精度验证（与 TA-Lib 对比）

- ✅ EMA 单元测试
  - 基本计算测试
  - α 系数验证
  - 精度验证

- ✅ RSI 单元测试
  - 标准测试数据验证
  - 超买/超卖边界测试
  - Wilder's Smoothing 验证

- ✅ MACD 单元测试
  - MACD Line 计算验证
  - Signal Line 计算验证
  - Histogram 计算验证
  - 交叉信号测试

- ✅ Bollinger Bands 单元测试
  - Upper/Middle/Lower Band 计算验证
  - 标准差计算验证
  - 带宽计算测试

- ✅ IndicatorManager 测试
  - 缓存功能测试
  - 缓存失效测试
  - 内存泄漏测试

- ✅ 性能基准测试
  - 各指标计算速度测试
  - 批量计算性能测试
  - 内存占用测试

### Performance

- ⚡ **计算速度** (1000 蜡烛):
  - SMA(20): < 500μs
  - EMA(20): < 400μs
  - RSI(14): < 600μs
  - MACD(12,26,9): < 800μs
  - BB(20,2.0): < 700μs

- ⚡ **内存占用**:
  - 单个指标: ~8KB (1000 candles)
  - MACD: ~24KB (3个数组)
  - BB: ~24KB (3个数组)

- ⚡ **精度**:
  - 与 TA-Lib 结果误差 < 0.01%

---

## 设计参考

- **TA-Lib**: [Technical Analysis Library](https://ta-lib.org/)
  - 指标计算算法参考
  - 测试数据来源
  - API 设计灵感

- **TradingView**: [Pine Script](https://www.tradingview.com/pine-script-docs/)
  - 指标应用场景参考
  - 参数默认值参考

---

## 版本规范

遵循 [语义化版本 2.0.0](https://semver.org/lang/zh-CN/)：

- **MAJOR** (x.0.0): 不兼容的 API 变更
- **MINOR** (0.x.0): 向后兼容的功能新增
- **PATCH** (0.0.x): 向后兼容的 Bug 修复

---

## 下一版本计划

### v0.4.0 - 扩展指标库（计划中）

#### 波动性指标

- [ ] **ATR (Average True Range)** - 平均真实波幅
  - 衡量市场波动性
  - 用于止损位计算
  - 标准周期: 14

- [ ] **Standard Deviation** - 标准差
  - 价格波动度量
  - 布林带的基础

#### 震荡指标

- [ ] **Stochastic Oscillator** - 随机振荡器
  - %K 和 %D 线
  - 超买/超卖识别
  - 标准参数: (14, 3, 3)

- [ ] **CCI (Commodity Channel Index)** - 商品通道指标
  - 识别超买超卖
  - 趋势强度判断

#### 趋势指标

- [ ] **ADX (Average Directional Index)** - 平均趋向指标
  - 趋势强度判断
  - +DI 和 -DI 方向指标
  - 标准周期: 14

- [ ] **Parabolic SAR** - 抛物线转向
  - 追踪止损
  - 趋势反转识别

#### 成交量指标

- [ ] **OBV (On Balance Volume)** - 能量潮
  - 成交量累积指标
  - 价量背离分析

- [ ] **VWAP (Volume Weighted Average Price)** - 成交量加权平均价
  - 日内交易参考价
  - 机构交易基准

#### 高级功能

- [ ] **指标组合器** - 组合多个指标
- [ ] **自定义指标框架** - 用户自定义指标
- [ ] **SIMD 优化** - 向量化计算加速
- [ ] **增量计算** - 仅计算新增蜡烛的指标值

### v0.5.0 - 机器学习指标（未来）

- [ ] **特征工程** - 从指标生成 ML 特征
- [ ] **降维指标** - PCA 等降维方法
- [ ] **聚类指标** - K-means 等聚类方法

---

## API 兼容性承诺

- v0.3.x 系列: API 稳定，仅 bug 修复
- v0.4.0: 可能有少量 breaking changes（会在文档中标注）
- v1.0.0: API 冻结，保证向后兼容

---

**当前版本**: v0.3.0 (设计阶段)
**更新时间**: 2025-12-25
**参考**: TA-Lib, TradingView
