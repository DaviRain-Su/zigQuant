# Docker 部署 - 测试文档

> 容器测试和验证

**最后更新**: 2025-12-28

---

## 测试概览

| 类别 | 测试数 | 状态 |
|------|--------|------|
| 构建测试 | TBD | 📋 待实现 |
| 运行测试 | TBD | 📋 待实现 |
| 集成测试 | TBD | 📋 待实现 |
| 性能测试 | TBD | 📋 待实现 |

---

## 构建测试

### 基本构建

```bash
#!/bin/bash
# test_docker_build.sh

set -e

echo "=== Docker Build Tests ==="

# 测试 1: 基本构建
echo "Test 1: Basic build..."
docker build -t zigquant:test . --quiet
if [ $? -eq 0 ]; then
    echo "  PASS: Build succeeded"
else
    echo "  FAIL: Build failed"
    exit 1
fi

# 测试 2: 无缓存构建
echo "Test 2: No-cache build..."
docker build --no-cache -t zigquant:test-nocache . --quiet
if [ $? -eq 0 ]; then
    echo "  PASS: No-cache build succeeded"
else
    echo "  FAIL: No-cache build failed"
    exit 1
fi

# 测试 3: 镜像体积检查
echo "Test 3: Image size check..."
SIZE=$(docker image inspect zigquant:test --format='{{.Size}}')
SIZE_MB=$((SIZE / 1024 / 1024))
if [ $SIZE_MB -lt 100 ]; then
    echo "  PASS: Image size is ${SIZE_MB}MB (< 100MB)"
else
    echo "  WARN: Image size is ${SIZE_MB}MB (> 100MB)"
fi

# 测试 4: 镜像层数检查
echo "Test 4: Layer count check..."
LAYERS=$(docker history zigquant:test --quiet | wc -l)
if [ $LAYERS -lt 20 ]; then
    echo "  PASS: Layer count is $LAYERS (< 20)"
else
    echo "  WARN: Layer count is $LAYERS (> 20)"
fi

echo "=== Build Tests Complete ==="
```

### 多平台构建

```bash
# 测试多架构构建
docker buildx build \
    --platform linux/amd64,linux/arm64 \
    -t zigquant:multiarch \
    --output type=image,push=false \
    .
```

---

## 运行测试

### 容器启动测试

```bash
#!/bin/bash
# test_container_run.sh

set -e

echo "=== Container Run Tests ==="

# 清理旧容器
docker rm -f zigquant-test 2>/dev/null || true

# 测试 1: 基本启动
echo "Test 1: Basic startup..."
docker run -d --name zigquant-test -p 8081:8080 zigquant:test
sleep 3

if docker ps | grep -q zigquant-test; then
    echo "  PASS: Container is running"
else
    echo "  FAIL: Container failed to start"
    docker logs zigquant-test
    exit 1
fi

# 测试 2: 健康检查
echo "Test 2: Health check..."
HEALTH=$(docker inspect --format='{{.State.Health.Status}}' zigquant-test)
if [ "$HEALTH" = "healthy" ] || [ "$HEALTH" = "starting" ]; then
    echo "  PASS: Health status is $HEALTH"
else
    echo "  FAIL: Health status is $HEALTH"
fi

# 测试 3: API 可访问性
echo "Test 3: API accessibility..."
response=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8081/health)
if [ "$response" = "200" ]; then
    echo "  PASS: API returns 200"
else
    echo "  FAIL: API returns $response"
fi

# 测试 4: 优雅关闭
echo "Test 4: Graceful shutdown..."
docker stop zigquant-test
EXIT_CODE=$(docker inspect zigquant-test --format='{{.State.ExitCode}}')
if [ "$EXIT_CODE" = "0" ]; then
    echo "  PASS: Container exited with code 0"
else
    echo "  WARN: Container exited with code $EXIT_CODE"
fi

# 清理
docker rm zigquant-test

echo "=== Run Tests Complete ==="
```

### 环境变量测试

```bash
#!/bin/bash
# test_env_vars.sh

echo "=== Environment Variable Tests ==="

# 测试日志级别
docker run --rm \
    -e ZIGQUANT_LOG_LEVEL=debug \
    zigquant:test \
    zigquant --version 2>&1 | grep -q "debug" && \
    echo "PASS: Log level configured" || \
    echo "FAIL: Log level not applied"

# 测试端口配置
docker run -d --name env-test \
    -e ZIGQUANT_API_PORT=9000 \
    -p 9000:9000 \
    zigquant:test
sleep 2

curl -s http://localhost:9000/health > /dev/null && \
    echo "PASS: Custom port working" || \
    echo "FAIL: Custom port not working"

docker rm -f env-test

echo "=== Env Tests Complete ==="
```

---

## 集成测试

### docker-compose 测试

```bash
#!/bin/bash
# test_compose.sh

set -e

echo "=== Docker Compose Tests ==="

# 启动服务
echo "Starting services..."
docker-compose up -d

# 等待服务就绪
echo "Waiting for services..."
sleep 10

# 测试 1: 所有服务运行
echo "Test 1: All services running..."
RUNNING=$(docker-compose ps --status running -q | wc -l)
EXPECTED=3  # zigquant, prometheus, grafana
if [ "$RUNNING" -eq "$EXPECTED" ]; then
    echo "  PASS: $RUNNING services running"
else
    echo "  FAIL: Expected $EXPECTED, got $RUNNING services"
    docker-compose ps
fi

# 测试 2: zigQuant API
echo "Test 2: zigQuant API..."
if curl -s http://localhost:8080/health | grep -q "healthy"; then
    echo "  PASS: zigQuant healthy"
else
    echo "  FAIL: zigQuant not healthy"
fi

# 测试 3: Prometheus
echo "Test 3: Prometheus..."
if curl -s http://localhost:9090/-/ready | grep -q "ready"; then
    echo "  PASS: Prometheus ready"
else
    echo "  FAIL: Prometheus not ready"
fi

# 测试 4: Grafana
echo "Test 4: Grafana..."
if curl -s http://localhost:3000/api/health | grep -q "ok"; then
    echo "  PASS: Grafana healthy"
else
    echo "  FAIL: Grafana not healthy"
fi

# 测试 5: Prometheus 抓取
echo "Test 5: Prometheus scraping..."
sleep 15  # 等待抓取
TARGETS=$(curl -s "http://localhost:9090/api/v1/targets" | grep -c '"health":"up"')
if [ "$TARGETS" -ge 1 ]; then
    echo "  PASS: $TARGETS targets up"
else
    echo "  FAIL: No healthy targets"
fi

# 测试 6: 服务通信
echo "Test 6: Service communication..."
docker-compose exec -T zigquant wget -q -O - http://prometheus:9090/-/ready > /dev/null && \
    echo "  PASS: zigquant can reach prometheus" || \
    echo "  FAIL: zigquant cannot reach prometheus"

# 清理
echo "Cleaning up..."
docker-compose down

echo "=== Compose Tests Complete ==="
```

### 网络测试

```bash
#!/bin/bash
# test_network.sh

echo "=== Network Tests ==="

docker-compose up -d

# 测试服务间 DNS 解析
docker-compose exec -T zigquant nslookup prometheus
docker-compose exec -T zigquant nslookup grafana

# 测试端口连通性
docker-compose exec -T zigquant nc -zv prometheus 9090
docker-compose exec -T grafana nc -zv prometheus 9090

docker-compose down

echo "=== Network Tests Complete ==="
```

---

## 卷和持久化测试

```bash
#!/bin/bash
# test_volumes.sh

echo "=== Volume Tests ==="

# 启动服务
docker-compose up -d
sleep 5

# 写入数据
curl -X POST http://localhost:8080/api/v1/test-data

# 重启服务
docker-compose restart zigquant
sleep 5

# 验证数据持久
curl http://localhost:8080/api/v1/test-data | grep -q "exists" && \
    echo "PASS: Data persisted" || \
    echo "FAIL: Data lost"

# 清理
docker-compose down

echo "=== Volume Tests Complete ==="
```

---

## 性能测试

### 启动时间测试

```bash
#!/bin/bash
# test_startup_time.sh

echo "=== Startup Time Test ==="

for i in {1..5}; do
    START=$(date +%s%N)

    docker run -d --name startup-test-$i zigquant:test

    # 等待健康检查通过
    while true; do
        STATUS=$(docker inspect --format='{{.State.Health.Status}}' startup-test-$i 2>/dev/null)
        if [ "$STATUS" = "healthy" ]; then
            break
        fi
        sleep 0.1
    done

    END=$(date +%s%N)
    ELAPSED=$(( (END - START) / 1000000 ))

    echo "Run $i: ${ELAPSED}ms"

    docker rm -f startup-test-$i
done

echo "=== Startup Time Complete ==="
```

### 资源使用测试

```bash
#!/bin/bash
# test_resources.sh

echo "=== Resource Usage Test ==="

docker run -d --name resource-test zigquant:test
sleep 10

# 获取资源统计
docker stats resource-test --no-stream --format \
    "CPU: {{.CPUPerc}}, Memory: {{.MemUsage}}"

# 压力测试
echo "Running load test..."
wrk -t4 -c100 -d30s http://localhost:8080/health

# 再次检查资源
docker stats resource-test --no-stream --format \
    "CPU: {{.CPUPerc}}, Memory: {{.MemUsage}}"

docker rm -f resource-test

echo "=== Resource Tests Complete ==="
```

### 负载测试

```bash
#!/bin/bash
# test_load.sh

docker-compose up -d
sleep 10

echo "=== Load Test ==="

# 使用 wrk 进行负载测试
wrk -t12 -c400 -d60s http://localhost:8080/health

# 检查服务稳定性
docker-compose ps
docker-compose logs --tail=50 zigquant

docker-compose down

echo "=== Load Test Complete ==="
```

---

## 安全测试

```bash
#!/bin/bash
# test_security.sh

echo "=== Security Tests ==="

# 测试 1: 非 root 用户
echo "Test 1: Non-root user..."
USER=$(docker run --rm zigquant:test id -u)
if [ "$USER" != "0" ]; then
    echo "  PASS: Running as non-root (UID: $USER)"
else
    echo "  FAIL: Running as root"
fi

# 测试 2: 只读文件系统
echo "Test 2: Read-only filesystem..."
docker run --rm --read-only zigquant:test ls /tmp > /dev/null 2>&1 && \
    echo "  PASS: Read-only compatible" || \
    echo "  FAIL: Requires write access"

# 测试 3: 无敏感信息
echo "Test 3: No secrets in image..."
docker history zigquant:test --no-trunc | grep -i "password\|secret\|key" && \
    echo "  FAIL: Found secrets in layers" || \
    echo "  PASS: No secrets found"

# 测试 4: Trivy 扫描
echo "Test 4: Vulnerability scan..."
if command -v trivy &> /dev/null; then
    trivy image zigquant:test --severity HIGH,CRITICAL
else
    echo "  SKIP: trivy not installed"
fi

echo "=== Security Tests Complete ==="
```

---

## 测试用例

### 正常情况

| 测试用例 | 描述 | 状态 |
|----------|------|------|
| 构建成功 | 镜像构建无错误 | 📋 待实现 |
| 启动成功 | 容器正常启动 | 📋 待实现 |
| 健康检查通过 | /health 返回 200 | 📋 待实现 |
| 服务编排 | docker-compose 正常运行 | 📋 待实现 |
| 数据持久化 | 重启后数据保留 | 📋 待实现 |

### 边界情况

| 测试用例 | 描述 | 状态 |
|----------|------|------|
| 资源限制 | 内存限制下正常运行 | 📋 待实现 |
| 网络隔离 | 正确的网络隔离 | 📋 待实现 |
| 配置缺失 | 无配置文件时的行为 | 📋 待实现 |

### 错误情况

| 测试用例 | 描述 | 状态 |
|----------|------|------|
| 端口冲突 | 处理端口已占用 | 📋 待实现 |
| OOM Kill | 内存耗尽处理 | 📋 待实现 |
| 网络断开 | 网络故障恢复 | 📋 待实现 |

---

## 运行测试

```bash
# 运行所有 Docker 测试
./scripts/test_docker.sh

# 运行构建测试
./scripts/test_docker_build.sh

# 运行集成测试
./scripts/test_compose.sh

# 运行安全测试
./scripts/test_security.sh
```

---

*Last updated: 2025-12-28*
