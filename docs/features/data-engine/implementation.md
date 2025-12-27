# DataEngine - 实现细节

**版本**: v0.5.0
**状态**: 计划中
**最后更新**: 2025-12-27

---

## 架构设计

### 整体架构

```
┌─────────────────────────────────────────────────────────────┐
│                       DataEngine                             │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌────────────────────────────────────────────────────────┐ │
│  │                   Data Sources                          │ │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐             │ │
│  │  │   CSV    │  │WebSocket │  │  Custom  │             │ │
│  │  │  Source  │  │  Source  │  │  Source  │             │ │
│  │  └──────────┘  └──────────┘  └──────────┘             │ │
│  └────────────────────────────────────────────────────────┘ │
│                            │                                 │
│                            ▼                                 │
│  ┌────────────────────────────────────────────────────────┐ │
│  │                  Data Aggregator                        │ │
│  │  - 时间对齐                                              │ │
│  │  - 事件排序                                              │ │
│  │  - 数据标准化                                            │ │
│  └────────────────────────────────────────────────────────┘ │
│                            │                                 │
│                            ▼                                 │
│  ┌────────────────────────────────────────────────────────┐ │
│  │                   Event Publisher                        │ │
│  │           发布到 MessageBus                              │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Code Parity 设计

```
                    统一接口
                       │
        ┌──────────────┴──────────────┐
        ▼                              ▼
┌──────────────┐              ┌──────────────┐
│   回测模式    │              │   实盘模式    │
│              │              │              │
│  CSV Reader  │              │  WebSocket   │
│      │       │              │      │       │
│      ▼       │              │      ▼       │
│  Event Loop  │              │  Event Loop  │
│      │       │              │      │       │
│      ▼       │              │      ▼       │
│  MessageBus  │              │  MessageBus  │
└──────────────┘              └──────────────┘
        │                              │
        └──────────────┬──────────────┘
                       ▼
              相同的策略代码
```

---

## 核心数据结构

### DataEngine 结构

```zig
pub const DataEngine = struct {
    allocator: Allocator,
    message_bus: *MessageBus,
    cache: *Cache,
    config: DataEngineConfig,

    // 数据源
    sources: std.ArrayList(DataSource),

    // 状态
    mode: DataMode,
    current_timestamp: i64,
    is_running: bool,
    is_paused: bool,

    // 回测专用
    event_queue: std.PriorityQueue(TimestampedEvent, void, compareEvents),

    // 数据缓冲
    bar_buffers: std.StringHashMap(BarBuffer),
    orderbook_cache: std.StringHashMap(Orderbook),
};

const TimestampedEvent = struct {
    timestamp: i64,
    event: Event,
};

fn compareEvents(context: void, a: TimestampedEvent, b: TimestampedEvent) std.math.Order {
    _ = context;
    return std.math.order(a.timestamp, b.timestamp);
}
```

### BarBuffer

用于构建 K 线：

```zig
pub const BarBuffer = struct {
    instrument_id: []const u8,
    timeframe: Timeframe,

    // 当前正在构建的 K 线
    current_bar: ?Bar,
    bar_start_time: i64,

    // 历史 K 线
    history: RingBuffer(Bar),

    pub fn update(self: *BarBuffer, trade: Trade) ?Bar {
        const bar_time = alignToTimeframe(trade.timestamp, self.timeframe);

        if (self.current_bar) |*bar| {
            if (bar_time != self.bar_start_time) {
                // 新 K 线，返回完成的旧 K 线
                const completed = bar.*;
                self.startNewBar(trade, bar_time);
                self.history.push(completed);
                return completed;
            }
            // 更新当前 K 线
            bar.high = @max(bar.high, trade.price);
            bar.low = @min(bar.low, trade.price);
            bar.close = trade.price;
            bar.volume += trade.quantity;
        } else {
            self.startNewBar(trade, bar_time);
        }
        return null;
    }
};
```

---

## 回测模式实现

### CSV 数据加载

```zig
pub const CsvDataSource = struct {
    path: []const u8,
    instrument_id: []const u8,
    timeframe: Timeframe,

    reader: ?std.fs.File.Reader,
    buffer: []u8,

    pub fn init(allocator: Allocator, config: CsvConfig) !CsvDataSource {
        const file = try std.fs.cwd().openFile(config.path, .{});
        return CsvDataSource{
            .path = config.path,
            .instrument_id = config.instrument_id,
            .reader = file.reader(),
            .buffer = try allocator.alloc(u8, 4096),
        };
    }

    pub fn nextEvent(self: *CsvDataSource) !?Event {
        const line = try self.reader.?.readUntilDelimiterOrEof(self.buffer, '\n');
        if (line == null) return null;

        // 解析 CSV 行
        const bar = try parseCsvLine(line.?, self.instrument_id);
        return Event{ .candle = bar };
    }
};
```

### 事件回放

```zig
pub fn runBacktest(self: *DataEngine) !void {
    self.is_running = true;

    // 预加载所有事件到优先队列
    for (self.sources.items) |*source| {
        while (try source.nextEvent()) |event| {
            try self.event_queue.add(.{
                .timestamp = event.getTimestamp(),
                .event = event,
            });
        }
    }

    // 按时间顺序处理事件
    while (self.event_queue.removeOrNull()) |timestamped| {
        if (!self.is_running) break;

        self.current_timestamp = timestamped.timestamp;

        // 发布事件
        try self.publishEvent(timestamped.event);

        // 发布 tick 事件
        try self.message_bus.publish("system.tick", .{
            .tick = .{ .timestamp = self.current_timestamp },
        });
    }

    // 发布结束事件
    try self.message_bus.publish("system.shutdown", .{
        .shutdown = .{ .reason = .backtest_complete },
    });
}
```

---

## 实盘模式实现

### WebSocket 数据源

```zig
pub const WebSocketDataSource = struct {
    url: []const u8,
    instrument_id: []const u8,

    connection: ?*WebSocket,
    subscriptions: std.ArrayList([]const u8),

    pub fn connect(self: *WebSocketDataSource) !void {
        self.connection = try WebSocket.connect(self.url);

        // 发送订阅消息
        for (self.subscriptions.items) |sub| {
            try self.connection.?.send(sub);
        }
    }

    pub fn onMessage(self: *WebSocketDataSource, data: []const u8) !?Event {
        // 解析 WebSocket 消息
        const parsed = try std.json.parseFromSlice(
            WsMessage,
            self.allocator,
            data,
            .{},
        );
        defer parsed.deinit();

        return switch (parsed.value.type) {
            .trade => Event{ .trade = parseTrade(parsed.value) },
            .orderbook => Event{ .orderbook_update = parseOrderbook(parsed.value) },
            .ticker => Event{ .market_data = parseTicker(parsed.value) },
        };
    }
};
```

### 实盘事件循环

```zig
pub fn runLive(self: *DataEngine, loop: *xev.Loop) !void {
    self.is_running = true;

    // 连接所有 WebSocket 数据源
    for (self.sources.items) |*source| {
        switch (source.*) {
            .websocket => |*ws| {
                try ws.connect();
                try loop.add(ws.connection.?.fd, self, onWebSocketData);
            },
            else => {},
        }
    }

    // 运行事件循环
    while (self.is_running) {
        try loop.run(.once);
    }
}

fn onWebSocketData(
    self: *DataEngine,
    completion: *xev.Completion,
    result: xev.Result,
) void {
    const data = result.value orelse return;

    if (self.parseWebSocketMessage(data)) |event| {
        self.current_timestamp = std.time.milliTimestamp();
        self.publishEvent(event) catch {};
    }
}
```

---

## 数据标准化

### 交易所数据适配

```zig
pub const DataNormalizer = struct {
    pub fn normalizeTrade(
        exchange: Exchange,
        raw_data: anytype,
    ) Trade {
        return switch (exchange) {
            .hyperliquid => normalizeHyperliquidTrade(raw_data),
            .binance => normalizeBinanceTrade(raw_data),
            // ... 其他交易所
        };
    }

    fn normalizeHyperliquidTrade(data: HyperliquidTrade) Trade {
        return Trade{
            .instrument_id = data.coin,
            .timestamp = data.time,
            .price = parseDecimal(data.px),
            .quantity = parseDecimal(data.sz),
            .side = if (data.side == "B") .buy else .sell,
            .trade_id = data.tid,
        };
    }
};
```

---

## 事件发布

### 发布流程

```zig
fn publishEvent(self: *DataEngine, event: Event) !void {
    const topic = switch (event) {
        .market_data => |d| try std.fmt.allocPrint(
            self.allocator,
            "market_data.{s}",
            .{d.instrument_id},
        ),
        .trade => |t| try std.fmt.allocPrint(
            self.allocator,
            "trade.{s}",
            .{t.instrument_id},
        ),
        .orderbook_update => |o| try std.fmt.allocPrint(
            self.allocator,
            "orderbook.{s}",
            .{o.instrument_id},
        ),
        .candle => |c| try std.fmt.allocPrint(
            self.allocator,
            "candle.{s}.{s}",
            .{ c.instrument_id, @tagName(c.timeframe) },
        ),
        else => return,
    };
    defer self.allocator.free(topic);

    try self.message_bus.publish(topic, event);
}
```

---

## 性能优化

### 1. 数据预加载

```zig
pub fn preloadData(self: *DataEngine) !void {
    for (self.sources.items) |*source| {
        switch (source.*) {
            .csv => |*csv| {
                // 预加载 CSV 到内存
                const data = try csv.loadAll(self.allocator);
                csv.preloaded_data = data;
            },
            else => {},
        }
    }
}
```

### 2. 环形缓冲区

```zig
pub fn RingBuffer(comptime T: type) type {
    return struct {
        buffer: []T,
        head: usize,
        len: usize,

        pub fn push(self: *@This(), item: T) void {
            self.buffer[self.head] = item;
            self.head = (self.head + 1) % self.buffer.len;
            if (self.len < self.buffer.len) {
                self.len += 1;
            }
        }

        pub fn getRecent(self: *@This(), count: usize) []const T {
            const actual_count = @min(count, self.len);
            // 返回最近 N 个元素
            // ...
        }
    };
}
```

### 3. 零拷贝事件传递

```zig
// 事件通过引用传递
pub fn publish(self: *MessageBus, topic: []const u8, event: *const Event) !void {
    // event 不被复制，只传递指针
}
```

---

## 文件结构

```
src/data/
├── engine.zig               # DataEngine 实现
├── sources/
│   ├── csv_source.zig       # CSV 数据源
│   ├── websocket_source.zig # WebSocket 数据源
│   └── source.zig           # 数据源接口
├── normalizer.zig           # 数据标准化
├── bar_builder.zig          # K 线构建
└── types.zig                # 数据类型
```

---

## 相关文档

- [功能概览](./README.md)
- [API 参考](./api.md)
- [测试文档](./testing.md)

---

**版本**: v0.5.0
**状态**: 计划中
