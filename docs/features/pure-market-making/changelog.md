# Pure Market Making - 变更日志

> 版本历史和更新记录

**最后更新**: 2025-12-27

---

## [Unreleased]

### Planned
- [ ] PureMMConfig 配置结构
- [ ] PureMarketMaking 策略实现
- [ ] IClockStrategy 接口实现
- [ ] 多层级报价支持
- [ ] 仓位限制和方向控制
- [ ] 成交回报处理
- [ ] 统计信息收集
- [ ] Paper Trading 集成测试

---

## [0.7.0] - 待发布

### Added
- PureMMConfig 策略配置
  - spread_bps 价差配置
  - order_levels 多层级支持
  - max_position 仓位限制
  - min_refresh_bps 刷新阈值
- PureMarketMaking 策略主体
  - getMidPrice 中间价计算
  - shouldRefreshQuotes 刷新判断
  - placeQuotes 多层级报价
  - cancelAllOrders 批量取消
- IClockStrategy 接口实现
  - onTick 定期报价更新
  - onStart 策略启动
  - onStop 策略停止 (取消订单)
- OrderInfo 和 MMStats 数据结构

### Features
- 双边做市报价
- 价格变动自动刷新
- 仓位方向智能调整
- 实时统计监控

---

## 版本规范

遵循 [语义化版本](https://semver.org/lang/zh-CN/)：

- **MAJOR**: 不兼容的 API 变更
- **MINOR**: 向后兼容的功能新增
- **PATCH**: 向后兼容的 Bug 修复

---

## 路线图

### v0.7.x
- 基础做市策略
- Paper Trading 验证

### v0.8.x (未来)
- 与 Inventory Management 集成
- 动态价差调整
- 策略参数热更新

### v1.0.x (未来)
- 多交易对并行
- 机器学习优化

---

*Last updated: 2025-12-27*
