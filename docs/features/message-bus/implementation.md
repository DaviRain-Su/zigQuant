# MessageBus - 实现细节

**版本**: v0.5.0
**状态**: 计划中
**最后更新**: 2025-12-27

---

## 架构设计

### 整体架构

```
┌─────────────────────────────────────────────────────────────┐
│                      MessageBus                             │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │               Subscriber Registry                     │   │
│  │  HashMap<Topic, ArrayList<Handler>>                  │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │               Endpoint Registry                       │   │
│  │  HashMap<Endpoint, RequestHandler>                   │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │               Wildcard Matcher                        │   │
│  │  支持 "*" 通配符匹配                                   │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 设计原则

1. **单线程执行**: 避免锁和线程切换开销
2. **同步分发**: 事件立即分发给所有订阅者
3. **类型安全**: 编译时类型检查
4. **零拷贝**: 事件通过引用传递

---

## 核心数据结构

### Subscriber Registry

使用 HashMap 存储主题到处理器列表的映射：

```zig
subscribers: StringHashMap(ArrayList(Handler))
```

**设计考量**:
- 使用 ArrayList 允许同一主题多个订阅者
- StringHashMap 提供 O(1) 查找
- 支持动态添加/删除订阅

### Endpoint Registry

使用 HashMap 存储端点到处理器的映射：

```zig
endpoints: StringHashMap(RequestHandler)
```

**设计考量**:
- 每个端点只能有一个处理器
- O(1) 查找性能

---

## 通配符匹配

### 匹配规则

- `*` 匹配任意字符序列
- 通配符只能在末尾使用
- 示例: `market_data.*` 匹配 `market_data.BTC-USDT`

### 实现算法

```zig
fn matchWildcard(pattern: []const u8, topic: []const u8) bool {
    // 检查是否以 * 结尾
    if (pattern.len > 0 and pattern[pattern.len - 1] == '*') {
        const prefix = pattern[0..pattern.len - 1];
        return std.mem.startsWith(u8, topic, prefix);
    }
    // 精确匹配
    return std.mem.eql(u8, pattern, topic);
}
```

### 性能优化

发布时需要遍历所有订阅检查通配符匹配：

```zig
pub fn publish(self: *MessageBus, topic: []const u8, event: Event) !void {
    var iter = self.subscribers.iterator();
    while (iter.next()) |entry| {
        if (matchWildcard(entry.key_ptr.*, topic)) {
            for (entry.value_ptr.items) |handler| {
                handler(event);
            }
        }
    }
}
```

**优化策略**:
- 精确匹配订阅单独存储，O(1) 查找
- 通配符订阅单独存储，遍历匹配
- 大多数场景使用精确匹配

---

## 事件分发流程

### Publish-Subscribe 流程

```
1. publish("market_data.BTC-USDT", event)
   │
   ├──→ 查找精确匹配订阅者
   │    └──→ 调用每个 handler(event)
   │
   └──→ 遍历通配符订阅者
        └──→ 匹配 "market_data.*" ?
             └──→ 调用 handler(event)
```

### Request-Response 流程

```
1. request("order.validate", req)
   │
   ├──→ 查找端点处理器
   │    └──→ 未找到: 返回 EndpointNotFound
   │
   └──→ 调用处理器
        └──→ 返回 Response 或 Error
```

---

## 内存管理

### 分配策略

- **初始化时**: 分配 HashMap 内部存储
- **订阅时**: 分配 ArrayList 和字符串副本
- **运行时**: 零分配（事件通过引用传递）

### 清理流程

```zig
pub fn deinit(self: *MessageBus) void {
    // 释放所有订阅者列表
    var iter = self.subscribers.iterator();
    while (iter.next()) |entry| {
        entry.value_ptr.deinit();
    }
    self.subscribers.deinit();

    // 释放端点注册表
    self.endpoints.deinit();
}
```

---

## 线程安全

### 当前设计

MessageBus 设计为**单线程使用**：

- 所有操作在同一线程执行
- 无需锁保护
- 最高性能

### 多线程扩展 (未来)

如需多线程支持，可考虑：

```zig
pub const ThreadSafeMessageBus = struct {
    inner: MessageBus,
    mutex: std.Thread.Mutex,

    pub fn publish(self: *ThreadSafeMessageBus, topic: []const u8, event: Event) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        try self.inner.publish(topic, event);
    }
};
```

---

## 性能优化

### 1. 批量发布

减少锁竞争（如果未来添加锁）：

```zig
pub fn publishBatch(self: *MessageBus, events: []const struct { topic: []const u8, event: Event }) !void {
    for (events) |e| {
        try self.publish(e.topic, e.event);
    }
}
```

### 2. 预编译主题

避免运行时字符串操作：

```zig
const Topics = struct {
    pub const market_data_btc = "market_data.BTC-USDT";
    pub const order_submitted = "order.submitted";
};
```

### 3. 事件池

复用事件对象减少分配：

```zig
pub const EventPool = struct {
    pool: ArrayList(Event),

    pub fn acquire(self: *EventPool) *Event {
        if (self.pool.popOrNull()) |event| {
            return event;
        }
        return self.allocator.create(Event);
    }

    pub fn release(self: *EventPool, event: *Event) void {
        self.pool.append(event);
    }
};
```

---

## 错误处理

### 错误类型

```zig
pub const MessageBusError = error{
    EndpointNotFound,
    HandlerError,
    OutOfMemory,
};
```

### 错误传播

- `publish`: 忽略单个处理器错误，继续分发
- `request`: 传播处理器错误
- `subscribe`: 传播内存分配错误

---

## 文件结构

```
src/core/
├── message_bus.zig          # MessageBus 实现
├── events/
│   ├── types.zig            # Event 联合类型
│   ├── market_events.zig    # 市场事件定义
│   ├── order_events.zig     # 订单事件定义
│   ├── position_events.zig  # 仓位事件定义
│   └── system_events.zig    # 系统事件定义
└── wildcard.zig             # 通配符匹配
```

---

## 相关文档

- [功能概览](./README.md)
- [API 参考](./api.md)
- [测试文档](./testing.md)

---

**版本**: v0.5.0
**状态**: 计划中
