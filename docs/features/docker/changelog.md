# Docker 部署 - 变更日志

> 版本历史记录

**最后更新**: 2025-12-28

---

## [未发布]

### 计划中 (v1.0.0)

#### 新增
- 多阶段 Dockerfile
- docker-compose.yml 完整编排
- Prometheus 监控集成
- Grafana 仪表板集成
- 健康检查端点
- 非 root 用户运行
- 数据卷持久化
- 环境变量配置

#### 包含服务
- zigQuant API 服务
- Prometheus 指标收集
- Grafana 可视化

---

## 计划版本

### v1.1.0 (规划中)

#### 新增
- 多架构支持 (amd64, arm64)
- GitHub Actions 自动构建
- DockerHub 自动推送
- 镜像签名验证

#### 变更
- 优化镜像体积 (< 30MB)
- 使用 distroless 基础镜像

### v1.2.0 (规划中)

#### 新增
- Kubernetes Helm Chart
- Traefik 反向代理配置
- 自动备份 sidecar
- Loki 日志集成

---

## 版本规范

本项目遵循 [语义化版本](https://semver.org/lang/zh-CN/) 规范。

### 版本格式

```
MAJOR.MINOR.PATCH

- MAJOR: 不兼容的配置变更
- MINOR: 向后兼容的新功能
- PATCH: 向后兼容的 bug 修复
```

### 变更类型

- **新增**: 新功能、新配置
- **变更**: 现有配置的变更
- **弃用**: 即将移除的配置
- **移除**: 已移除的配置
- **修复**: bug 修复
- **安全**: 安全相关修复

---

*Last updated: 2025-12-28*
