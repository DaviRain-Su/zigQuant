# ZigQuant 部署运维手册

> 生产环境部署、监控与故障恢复指南

---

## 📦 部署方式概览

```
┌─────────────────────────────────────────────────────────┐
│              Deployment Options                          │
├─────────────────────────────────────────────────────────┤
│                                                           │
│  1. Bare Metal          2. Docker          3. Kubernetes │
│  ┌──────────┐          ┌──────────┐       ┌──────────┐  │
│  │ systemd  │          │Container │       │   Pod    │  │
│  │ service  │          │  Engine  │       │ Cluster  │  │
│  └──────────┘          └──────────┘       └──────────┘  │
│                                                           │
│       简单                  推荐                高可用     │
│                                                           │
└─────────────────────────────────────────────────────────┘
```

---

## 1. 编译与打包

### 1.1 生产环境编译

```bash
# ReleaseSafe 模式 (推荐生产环境)
zig build -Doptimize=ReleaseSafe

# ReleaseFast 模式 (最高性能，牺牲部分安全检查)
zig build -Doptimize=ReleaseFast

# 交叉编译 (Linux x86_64)
zig build -Dtarget=x86_64-linux-gnu -Doptimize=ReleaseSafe

# 静态链接 (单一可执行文件，便于部署)
zig build -Doptimize=ReleaseSafe -Dtarget=x86_64-linux-musl
```

### 1.2 Build 配置

```zig
// build.zig

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // 主程序
    const exe = b.addExecutable(.{
        .name = "zigquant",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    // 启用 LTO (Link Time Optimization)
    if (optimize == .ReleaseFast or optimize == .ReleaseSafe) {
        exe.want_lto = true;
    }

    // 添加依赖
    const sqlite = b.dependency("sqlite", .{
        .target = target,
        .optimize = optimize,
    });
    exe.linkLibrary(sqlite.artifact("sqlite"));

    // 嵌入版本信息
    const version = b.option([]const u8, "version", "Version string") orelse "dev";
    exe.addOptions("build_options", .{
        .version = version,
        .commit = getGitCommit(),
        .build_time = std.time.timestamp(),
    });

    b.installArtifact(exe);
}

fn getGitCommit() []const u8 {
    const result = std.ChildProcess.exec(.{
        .allocator = std.heap.page_allocator,
        .argv = &[_][]const u8{ "git", "rev-parse", "--short", "HEAD" },
    }) catch return "unknown";

    return std.mem.trim(u8, result.stdout, &std.ascii.whitespace);
}
```

### 1.3 打包脚本

```bash
#!/bin/bash
# scripts/package.sh

set -e

VERSION=${1:-dev}
ARCH=${2:-x86_64}
OS=${3:-linux}

echo "Building ZigQuant v${VERSION} for ${OS}-${ARCH}"

# 清理旧构建
rm -rf dist/
mkdir -p dist/zigquant-${VERSION}/

# 编译
zig build -Doptimize=ReleaseSafe \
    -Dtarget=${ARCH}-${OS}-musl \
    --prefix dist/zigquant-${VERSION}/

# 复制配置文件和文档
cp -r config/ dist/zigquant-${VERSION}/
cp -r docs/ dist/zigquant-${VERSION}/
cp README.md LICENSE dist/zigquant-${VERSION}/

# 创建示例配置
cp config/config.example.json dist/zigquant-${VERSION}/config/config.json

# 创建压缩包
cd dist/
tar czf zigquant-${VERSION}-${OS}-${ARCH}.tar.gz zigquant-${VERSION}/
sha256sum zigquant-${VERSION}-${OS}-${ARCH}.tar.gz > zigquant-${VERSION}-${OS}-${ARCH}.tar.gz.sha256

echo "Package created: dist/zigquant-${VERSION}-${OS}-${ARCH}.tar.gz"
```

---

## 2. Docker 部署 (推荐)

### 2.1 多阶段 Dockerfile

```dockerfile
# Dockerfile

# ============ 构建阶段 ============
FROM alpine:latest AS builder

# 安装 Zig
RUN apk add --no-cache \
    wget \
    xz \
    && wget https://ziglang.org/download/0.12.0/zig-linux-x86_64-0.12.0.tar.xz \
    && tar xf zig-linux-x86_64-0.12.0.tar.xz \
    && mv zig-linux-x86_64-0.12.0 /usr/local/zig \
    && ln -s /usr/local/zig/zig /usr/local/bin/zig

# 设置工作目录
WORKDIR /build

# 复制源代码
COPY . .

# 编译
RUN zig build -Doptimize=ReleaseSafe -Dtarget=x86_64-linux-musl

# ============ 运行阶段 ============
FROM alpine:latest

# 安装运行时依赖
RUN apk add --no-cache \
    ca-certificates \
    tzdata

# 创建非特权用户
RUN addgroup -g 1000 zigquant \
    && adduser -D -u 1000 -G zigquant zigquant

# 创建必要目录
RUN mkdir -p /app/config /app/data /app/logs \
    && chown -R zigquant:zigquant /app

# 切换到非特权用户
USER zigquant
WORKDIR /app

# 从构建阶段复制可执行文件
COPY --from=builder --chown=zigquant:zigquant /build/zig-out/bin/zigquant /app/

# 复制配置示例
COPY --chown=zigquant:zigquant config/config.example.json /app/config/

# 暴露端口
EXPOSE 8080

# 健康检查
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:8080/health || exit 1

# 启动命令
ENTRYPOINT ["/app/zigquant"]
CMD ["--config", "/app/config/config.json"]
```

### 2.2 Docker Compose

```yaml
# docker-compose.yml

version: '3.8'

services:
  zigquant:
    build: .
    image: zigquant:latest
    container_name: zigquant
    restart: unless-stopped

    # 资源限制
    deploy:
      resources:
        limits:
          cpus: '2.0'
          memory: 1G
        reservations:
          cpus: '1.0'
          memory: 512M

    # 环境变量
    environment:
      - TZ=Asia/Shanghai
      - LOG_LEVEL=info

    # 挂载配置和数据
    volumes:
      - ./config:/app/config:ro
      - ./data:/app/data
      - ./logs:/app/logs

    # 端口映射
    ports:
      - "8080:8080"

    # 网络
    networks:
      - zigquant-net

    # 日志配置
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  # Prometheus 监控
  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    restart: unless-stopped
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--storage.tsdb.retention.time=30d'
    volumes:
      - ./monitoring/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - prometheus-data:/prometheus
    ports:
      - "9090:9090"
    networks:
      - zigquant-net

  # Grafana 可视化
  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    restart: unless-stopped
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin
      - GF_INSTALL_PLUGINS=grafana-clock-panel
    volumes:
      - ./monitoring/grafana/dashboards:/etc/grafana/provisioning/dashboards:ro
      - ./monitoring/grafana/datasources:/etc/grafana/provisioning/datasources:ro
      - grafana-data:/var/lib/grafana
    ports:
      - "3000:3000"
    networks:
      - zigquant-net
    depends_on:
      - prometheus

networks:
  zigquant-net:
    driver: bridge

volumes:
  prometheus-data:
  grafana-data:
```

### 2.3 Docker 操作命令

```bash
# 构建镜像
docker build -t zigquant:latest .

# 运行容器
docker run -d \
  --name zigquant \
  --restart unless-stopped \
  -v $(pwd)/config:/app/config:ro \
  -v $(pwd)/data:/app/data \
  -v $(pwd)/logs:/app/logs \
  -p 8080:8080 \
  zigquant:latest

# 查看日志
docker logs -f zigquant

# 进入容器
docker exec -it zigquant sh

# 使用 docker-compose
docker-compose up -d
docker-compose logs -f
docker-compose down
```

---

## 3. Systemd 服务部署

### 3.1 Systemd Service 文件

```ini
# /etc/systemd/system/zigquant.service

[Unit]
Description=ZigQuant Trading Bot
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=zigquant
Group=zigquant

# 工作目录
WorkingDirectory=/opt/zigquant

# 执行命令
ExecStart=/opt/zigquant/bin/zigquant --config /opt/zigquant/config/config.json

# 重启策略
Restart=on-failure
RestartSec=10s
StartLimitInterval=5min
StartLimitBurst=3

# 资源限制
LimitNOFILE=65536
LimitNPROC=4096
MemoryLimit=1G
CPUQuota=200%

# 安全加固
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/opt/zigquant/data /opt/zigquant/logs

# 环境变量
Environment="LOG_LEVEL=info"
Environment="TZ=Asia/Shanghai"

# 日志
StandardOutput=journal
StandardError=journal
SyslogIdentifier=zigquant

[Install]
WantedBy=multi-user.target
```

### 3.2 部署脚本

```bash
#!/bin/bash
# scripts/deploy.sh

set -e

USER=zigquant
GROUP=zigquant
INSTALL_DIR=/opt/zigquant

echo "Deploying ZigQuant to ${INSTALL_DIR}"

# 创建用户和组
if ! id -u $USER > /dev/null 2>&1; then
    sudo useradd -r -s /bin/false -d $INSTALL_DIR $USER
fi

# 创建目录
sudo mkdir -p $INSTALL_DIR/{bin,config,data,logs}

# 复制文件
sudo cp zig-out/bin/zigquant $INSTALL_DIR/bin/
sudo cp config/config.example.json $INSTALL_DIR/config/config.json
sudo cp -r docs/ $INSTALL_DIR/

# 设置权限
sudo chown -R $USER:$GROUP $INSTALL_DIR
sudo chmod 755 $INSTALL_DIR/bin/zigquant
sudo chmod 600 $INSTALL_DIR/config/config.json

# 安装 systemd 服务
sudo cp scripts/zigquant.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable zigquant

echo "Deployment complete!"
echo "Edit config: sudo nano $INSTALL_DIR/config/config.json"
echo "Start service: sudo systemctl start zigquant"
echo "View logs: sudo journalctl -u zigquant -f"
```

### 3.3 Systemd 操作命令

```bash
# 启动服务
sudo systemctl start zigquant

# 停止服务
sudo systemctl stop zigquant

# 重启服务
sudo systemctl restart zigquant

# 查看状态
sudo systemctl status zigquant

# 查看日志
sudo journalctl -u zigquant -f

# 查看最近 100 条日志
sudo journalctl -u zigquant -n 100

# 查看特定时间范围的日志
sudo journalctl -u zigquant --since "2025-01-01" --until "2025-01-02"

# 启用开机自启
sudo systemctl enable zigquant

# 禁用开机自启
sudo systemctl disable zigquant
```

---

## 4. Kubernetes 部署 (高可用)

### 4.1 Deployment 配置

```yaml
# k8s/deployment.yaml

apiVersion: apps/v1
kind: Deployment
metadata:
  name: zigquant
  namespace: trading
  labels:
    app: zigquant
spec:
  replicas: 1  # 交易机器人通常不需要多副本
  strategy:
    type: Recreate  # 避免多实例同时交易
  selector:
    matchLabels:
      app: zigquant
  template:
    metadata:
      labels:
        app: zigquant
    spec:
      serviceAccountName: zigquant
      containers:
      - name: zigquant
        image: zigquant:latest
        imagePullPolicy: IfNotPresent

        ports:
        - name: http
          containerPort: 8080
          protocol: TCP

        env:
        - name: LOG_LEVEL
          value: "info"
        - name: TZ
          value: "Asia/Shanghai"

        # 资源限制
        resources:
          requests:
            memory: "512Mi"
            cpu: "500m"
          limits:
            memory: "1Gi"
            cpu: "2000m"

        # 健康检查
        livenessProbe:
          httpGet:
            path: /health
            port: http
          initialDelaySeconds: 30
          periodSeconds: 30
          timeoutSeconds: 10
          failureThreshold: 3

        readinessProbe:
          httpGet:
            path: /ready
            port: http
          initialDelaySeconds: 10
          periodSeconds: 10
          timeoutSeconds: 5

        # 挂载
        volumeMounts:
        - name: config
          mountPath: /app/config
          readOnly: true
        - name: data
          mountPath: /app/data
        - name: logs
          mountPath: /app/logs

      volumes:
      - name: config
        configMap:
          name: zigquant-config
      - name: data
        persistentVolumeClaim:
          claimName: zigquant-data
      - name: logs
        emptyDir: {}

      # 节点亲和性
      affinity:
        nodeAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 1
            preference:
              matchExpressions:
              - key: workload
                operator: In
                values:
                - trading

---
apiVersion: v1
kind: Service
metadata:
  name: zigquant
  namespace: trading
spec:
  selector:
    app: zigquant
  ports:
  - name: http
    port: 80
    targetPort: 8080
  type: ClusterIP

---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: zigquant-data
  namespace: trading
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
  storageClassName: fast-ssd
```

### 4.2 ConfigMap

```yaml
# k8s/configmap.yaml

apiVersion: v1
kind: ConfigMap
metadata:
  name: zigquant-config
  namespace: trading
data:
  config.json: |
    {
      "exchanges": [
        {
          "name": "binance",
          "type": "binance",
          "testnet": false
        }
      ],
      "strategies": [
        {
          "name": "dual_ma",
          "enabled": true,
          "params": {
            "pair": "BTC/USDT",
            "fast_period": 10,
            "slow_period": 20
          }
        }
      ],
      "risk": {
        "max_daily_loss": "100",
        "max_position_size": "1.0"
      }
    }
```

### 4.3 Secret (API 密钥)

```yaml
# k8s/secret.yaml

apiVersion: v1
kind: Secret
metadata:
  name: zigquant-secrets
  namespace: trading
type: Opaque
stringData:
  binance-api-key: "your-api-key"
  binance-api-secret: "your-api-secret"
```

```bash
# 创建 secret
kubectl create secret generic zigquant-secrets \
  --from-literal=binance-api-key=YOUR_KEY \
  --from-literal=binance-api-secret=YOUR_SECRET \
  -n trading
```

---

## 5. 监控配置

### 5.1 Prometheus 配置

```yaml
# monitoring/prometheus.yml

global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'zigquant'
    static_configs:
      - targets: ['zigquant:8080']
    metrics_path: '/metrics'

  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
```

### 5.2 Grafana Dashboard

```json
{
  "dashboard": {
    "title": "ZigQuant Trading Dashboard",
    "panels": [
      {
        "title": "Total PnL",
        "type": "graph",
        "targets": [
          {
            "expr": "zigquant_total_pnl"
          }
        ]
      },
      {
        "title": "Active Orders",
        "type": "stat",
        "targets": [
          {
            "expr": "zigquant_active_orders_count"
          }
        ]
      },
      {
        "title": "Order Latency (P99)",
        "type": "graph",
        "targets": [
          {
            "expr": "histogram_quantile(0.99, zigquant_order_latency_seconds_bucket)"
          }
        ]
      },
      {
        "title": "WebSocket Connections",
        "type": "graph",
        "targets": [
          {
            "expr": "zigquant_websocket_connections"
          }
        ]
      }
    ]
  }
}
```

### 5.3 告警规则

```yaml
# monitoring/alerts.yml

groups:
  - name: zigquant
    interval: 30s
    rules:
      - alert: HighLatency
        expr: histogram_quantile(0.99, zigquant_order_latency_seconds_bucket) > 0.1
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High order latency detected"
          description: "P99 latency is {{ $value }}s"

      - alert: DailyLossLimitReached
        expr: zigquant_daily_pnl < -100
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Daily loss limit reached"
          description: "Current loss: {{ $value }}"

      - alert: WebSocketDisconnected
        expr: zigquant_websocket_connections == 0
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "WebSocket connection lost"

      - alert: HighMemoryUsage
        expr: process_resident_memory_bytes > 1e9
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High memory usage"
          description: "Memory usage: {{ $value }} bytes"
```

---

## 6. 日志管理

### 6.1 结构化日志格式

```zig
// src/utils/logger.zig

pub const Logger = struct {
    pub fn init(allocator: std.mem.Allocator, level: LogLevel) !Logger {
        // ...
    }

    pub fn log(
        self: *Logger,
        level: LogLevel,
        message: []const u8,
        context: ?std.json.Value,
    ) void {
        const log_entry = .{
            .timestamp = std.time.timestamp(),
            .level = @tagName(level),
            .message = message,
            .context = context,
            .host = std.os.hostname(),
            .version = build_options.version,
        };

        const json = std.json.stringifyAlloc(
            self.allocator,
            log_entry,
            .{}
        ) catch return;
        defer self.allocator.free(json);

        std.debug.print("{s}\n", .{json});
    }
};
```

### 6.2 日志轮转

```bash
# /etc/logrotate.d/zigquant

/opt/zigquant/logs/*.log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
    create 0644 zigquant zigquant
    postrotate
        systemctl reload zigquant > /dev/null 2>&1 || true
    endscript
}
```

---

## 7. 备份与恢复

### 7.1 备份脚本

```bash
#!/bin/bash
# scripts/backup.sh

BACKUP_DIR=/backup/zigquant
DATE=$(date +%Y%m%d_%H%M%S)
DATA_DIR=/opt/zigquant/data

mkdir -p $BACKUP_DIR

# 备份数据库
sqlite3 $DATA_DIR/zigquant.db ".backup $BACKUP_DIR/zigquant_$DATE.db"

# 备份配置
tar czf $BACKUP_DIR/config_$DATE.tar.gz /opt/zigquant/config/

# 备份日志
tar czf $BACKUP_DIR/logs_$DATE.tar.gz /opt/zigquant/logs/

# 删除30天前的备份
find $BACKUP_DIR -name "*.db" -mtime +30 -delete
find $BACKUP_DIR -name "*.tar.gz" -mtime +30 -delete

echo "Backup completed: $BACKUP_DIR"
```

### 7.2 定时备份

```bash
# crontab -e

# 每天凌晨2点备份
0 2 * * * /opt/zigquant/scripts/backup.sh

# 每周日凌晨3点上传到云端
0 3 * * 0 rclone sync /backup/zigquant remote:zigquant-backup
```

### 7.3 恢复脚本

```bash
#!/bin/bash
# scripts/restore.sh

BACKUP_FILE=$1

if [ -z "$BACKUP_FILE" ]; then
    echo "Usage: $0 <backup_file>"
    exit 1
fi

# 停止服务
sudo systemctl stop zigquant

# 恢复数据库
sqlite3 /opt/zigquant/data/zigquant.db ".restore $BACKUP_FILE"

# 重启服务
sudo systemctl start zigquant

echo "Restore completed"
```

---

## 8. 升级策略

### 8.1 零停机升级 (Docker)

```bash
# scripts/upgrade.sh

#!/bin/bash

NEW_VERSION=$1

# 拉取新镜像
docker pull zigquant:$NEW_VERSION

# 创建新容器
docker run -d \
  --name zigquant-new \
  --network container:zigquant \
  -v $(pwd)/config:/app/config:ro \
  -v $(pwd)/data:/app/data \
  zigquant:$NEW_VERSION

# 等待新容器启动
sleep 10

# 健康检查
if docker exec zigquant-new wget -q -O- http://localhost:8080/health; then
    # 停止旧容器
    docker stop zigquant
    docker rm zigquant

    # 重命名新容器
    docker rename zigquant-new zigquant

    echo "Upgrade successful"
else
    # 回滚
    docker stop zigquant-new
    docker rm zigquant-new
    echo "Upgrade failed, rolled back"
    exit 1
fi
```

### 8.2 配置版本管理

```bash
# 使用 Git 管理配置
cd /opt/zigquant/config
git init
git add config.json
git commit -m "Initial config"

# 升级前保存配置
git commit -am "Pre-upgrade config v1.2.0"

# 升级后验证
git diff HEAD~1
```

---

## 9. 故障排查

### 9.1 常见问题

```bash
# 问题1: 服务无法启动
sudo journalctl -u zigquant -n 50
# 检查配置文件
zigquant --validate-config

# 问题2: 内存占用过高
ps aux | grep zigquant
# 查看内存使用详情
pmap -x $(pidof zigquant)

# 问题3: WebSocket 连接断开
# 检查网络
curl -I https://stream.binance.com

# 问题4: 数据库锁定
# 检查是否有其他进程访问数据库
lsof /opt/zigquant/data/zigquant.db
```

### 9.2 紧急恢复

```bash
# Kill Switch 手动触发
curl -X POST http://localhost:8080/api/v1/killswitch

# 取消所有订单
curl -X DELETE http://localhost:8080/api/v1/orders/all

# 强制停止
sudo systemctl stop zigquant
# 或
docker stop zigquant
```

---

## 10. 安全加固

### 10.1 文件权限

```bash
# 设置正确的权限
chmod 700 /opt/zigquant/data
chmod 600 /opt/zigquant/config/config.json
chmod 600 /opt/zigquant/config/keys.enc
```

### 10.2 防火墙配置

```bash
# UFW 规则
sudo ufw allow 22/tcp    # SSH
sudo ufw allow 8080/tcp  # API (仅内网)
sudo ufw enable
```

### 10.3 SELinux 配置

```bash
# 设置 SELinux 上下文
sudo semanage fcontext -a -t bin_t "/opt/zigquant/bin/zigquant"
sudo restorecon -v /opt/zigquant/bin/zigquant
```

---

*Last updated: 2025-01*
