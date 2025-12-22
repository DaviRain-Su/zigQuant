# ZigQuant 安全设计

> 生产级安全架构与合规性设计

---

## 🔒 安全架构总览

```
┌─────────────────────────────────────────────────────────────────┐
│                        Security Layer                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │  Key Vault   │  │   Auth &     │  │   Audit      │          │
│  │  Management  │  │   Access     │  │   Logging    │          │
│  │              │  │   Control    │  │              │          │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘          │
│         │                 │                  │                   │
│         └─────────────────┼──────────────────┘                   │
│                           │                                      │
│  ┌────────────────────────▼──────────────────────────┐          │
│  │            Trading Engine (Protected)             │          │
│  └───────────────────────────────────────────────────┘          │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘
```

---

## 1. API 密钥管理

### 1.1 密钥加密存储

```zig
// src/security/key_vault.zig

pub const KeyVault = struct {
    allocator: std.mem.Allocator,
    master_key: [32]u8,
    encrypted_keys: std.StringHashMap(EncryptedKey),

    pub const EncryptedKey = struct {
        ciphertext: []const u8,
        nonce: [12]u8,
        tag: [16]u8,
        created_at: i64,
        last_rotated: i64,
    };

    pub fn init(allocator: std.mem.Allocator, password: []const u8) !KeyVault {
        // 使用 Argon2id 派生主密钥
        const master_key = try deriveKey(password);

        return .{
            .allocator = allocator,
            .master_key = master_key,
            .encrypted_keys = std.StringHashMap(EncryptedKey).init(allocator),
        };
    }

    /// 存储 API 密钥 (使用 ChaCha20-Poly1305 加密)
    pub fn storeKey(
        self: *KeyVault,
        name: []const u8,
        api_key: []const u8,
        api_secret: []const u8,
    ) !void {
        // 生成随机 nonce
        var nonce: [12]u8 = undefined;
        std.crypto.random.bytes(&nonce);

        // 组合 key + secret
        const plaintext = try std.fmt.allocPrint(
            self.allocator,
            "{s}:{s}",
            .{ api_key, api_secret }
        );
        defer self.allocator.free(plaintext);

        // 使用 ChaCha20-Poly1305 加密
        var ciphertext = try self.allocator.alloc(u8, plaintext.len);
        var tag: [16]u8 = undefined;

        std.crypto.aead.chacha_poly.ChaCha20Poly1305.encrypt(
            ciphertext,
            &tag,
            plaintext,
            &.{},
            nonce,
            self.master_key,
        );

        try self.encrypted_keys.put(name, .{
            .ciphertext = ciphertext,
            .nonce = nonce,
            .tag = tag,
            .created_at = std.time.milliTimestamp(),
            .last_rotated = std.time.milliTimestamp(),
        });
    }

    /// 读取 API 密钥
    pub fn retrieveKey(
        self: *KeyVault,
        name: []const u8,
    ) !struct { api_key: []const u8, api_secret: []const u8 } {
        const encrypted = self.encrypted_keys.get(name) orelse
            return error.KeyNotFound;

        // 解密
        var plaintext = try self.allocator.alloc(u8, encrypted.ciphertext.len);

        std.crypto.aead.chacha_poly.ChaCha20Poly1305.decrypt(
            plaintext,
            encrypted.ciphertext,
            encrypted.tag,
            &.{},
            encrypted.nonce,
            self.master_key,
        ) catch return error.DecryptionFailed;

        // 分离 key 和 secret
        var iter = std.mem.splitScalar(u8, plaintext, ':');
        const api_key = iter.first();
        const api_secret = iter.next() orelse return error.InvalidFormat;

        return .{
            .api_key = try self.allocator.dupe(u8, api_key),
            .api_secret = try self.allocator.dupe(u8, api_secret),
        };
    }

    /// 密钥轮换
    pub fn rotateKey(
        self: *KeyVault,
        name: []const u8,
        new_api_key: []const u8,
        new_api_secret: []const u8,
    ) !void {
        // 存储旧密钥用于回滚
        const old_key = try self.retrieveKey(name);
        defer {
            self.allocator.free(old_key.api_key);
            self.allocator.free(old_key.api_secret);
        }

        const backup_name = try std.fmt.allocPrint(
            self.allocator,
            "{s}.backup.{d}",
            .{ name, std.time.milliTimestamp() }
        );
        try self.storeKey(backup_name, old_key.api_key, old_key.api_secret);

        // 存储新密钥
        try self.storeKey(name, new_api_key, new_api_secret);
    }

    fn deriveKey(password: []const u8) ![32]u8 {
        var key: [32]u8 = undefined;
        const salt = "zigquant-salt-v1"; // 生产环境应使用随机盐

        try std.crypto.pwhash.argon2.kdf(
            self.allocator,
            &key,
            password,
            salt,
            .{
                .t = 3,  // 迭代次数
                .m = 65536,  // 内存使用 (64MB)
                .p = 4,  // 并行度
            },
            .argon2id,
        );

        return key;
    }

    /// 导出加密的密钥库 (用于备份)
    pub fn exportEncrypted(self: *KeyVault, path: []const u8) !void {
        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();

        // 写入加密的密钥数据
        var iter = self.encrypted_keys.iterator();
        while (iter.next()) |entry| {
            const json = try std.json.stringifyAlloc(
                self.allocator,
                .{
                    .name = entry.key_ptr.*,
                    .data = entry.value_ptr.*,
                },
                .{},
            );
            defer self.allocator.free(json);

            try file.writeAll(json);
            try file.writeAll("\n");
        }
    }
};
```

### 1.2 密钥权限隔离

```zig
// src/security/permissions.zig

pub const KeyPermissions = struct {
    read_only: bool = false,
    can_trade: bool = true,
    can_withdraw: bool = false,

    pub fn validate(self: KeyPermissions, operation: Operation) !void {
        switch (operation) {
            .read_balance, .read_orders => {
                // 所有密钥都可以读取
            },
            .create_order, .cancel_order => {
                if (!self.can_trade) {
                    return error.InsufficientPermissions;
                }
            },
            .withdraw => {
                if (!self.can_withdraw) {
                    return error.WithdrawNotAllowed;
                }
            },
        }
    }

    pub const Operation = enum {
        read_balance,
        read_orders,
        create_order,
        cancel_order,
        withdraw,
    };
};
```

---

## 2. 审计日志系统

### 2.1 审计日志设计

```zig
// src/security/audit.zig

pub const AuditLogger = struct {
    allocator: std.mem.Allocator,
    db: sqlite.Database,
    buffer: std.ArrayList(AuditEvent),
    flush_interval: i64 = 5_000,  // 5秒

    pub const AuditEvent = struct {
        timestamp: i64,
        event_type: EventType,
        user: []const u8,
        resource: []const u8,
        action: []const u8,
        details: std.json.Value,
        ip_address: ?[]const u8,
        success: bool,
        error_message: ?[]const u8,

        pub const EventType = enum {
            authentication,
            configuration_change,
            order_submitted,
            order_cancelled,
            strategy_started,
            strategy_stopped,
            api_key_rotated,
            balance_query,
            withdrawal_attempt,
            system_error,
        };
    };

    pub fn init(allocator: std.mem.Allocator, db_path: []const u8) !AuditLogger {
        var db = try sqlite.Database.open(db_path);

        // 创建审计表
        try db.exec(
            \\CREATE TABLE IF NOT EXISTS audit_log (
            \\  id INTEGER PRIMARY KEY AUTOINCREMENT,
            \\  timestamp INTEGER NOT NULL,
            \\  event_type TEXT NOT NULL,
            \\  user TEXT NOT NULL,
            \\  resource TEXT NOT NULL,
            \\  action TEXT NOT NULL,
            \\  details TEXT,
            \\  ip_address TEXT,
            \\  success INTEGER NOT NULL,
            \\  error_message TEXT,
            \\  INDEX idx_timestamp (timestamp),
            \\  INDEX idx_event_type (event_type),
            \\  INDEX idx_user (user)
            \\)
        );

        return .{
            .allocator = allocator,
            .db = db,
            .buffer = std.ArrayList(AuditEvent).init(allocator),
        };
    }

    /// 记录审计事件
    pub fn log(self: *AuditLogger, event: AuditEvent) !void {
        // 添加到缓冲区
        try self.buffer.append(event);

        // 达到阈值时刷新
        if (self.buffer.items.len >= 100) {
            try self.flush();
        }
    }

    /// 刷新缓冲区到数据库
    pub fn flush(self: *AuditLogger) !void {
        if (self.buffer.items.len == 0) return;

        var stmt = try self.db.prepare(
            \\INSERT INTO audit_log
            \\(timestamp, event_type, user, resource, action, details, ip_address, success, error_message)
            \\VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        );
        defer stmt.deinit();

        for (self.buffer.items) |event| {
            const details_json = try std.json.stringifyAlloc(
                self.allocator,
                event.details,
                .{},
            );
            defer self.allocator.free(details_json);

            try stmt.bind(.{
                event.timestamp,
                @tagName(event.event_type),
                event.user,
                event.resource,
                event.action,
                details_json,
                event.ip_address,
                @intFromBool(event.success),
                event.error_message,
            });
            try stmt.step();
            stmt.reset();
        }

        self.buffer.clearRetainingCapacity();
    }

    /// 查询审计日志
    pub fn query(
        self: *AuditLogger,
        filters: QueryFilters,
    ) ![]AuditEvent {
        var conditions = std.ArrayList([]const u8).init(self.allocator);
        defer conditions.deinit();

        if (filters.start_time) |start| {
            try conditions.append(try std.fmt.allocPrint(
                self.allocator,
                "timestamp >= {d}",
                .{start}
            ));
        }

        if (filters.event_type) |et| {
            try conditions.append(try std.fmt.allocPrint(
                self.allocator,
                "event_type = '{s}'",
                .{@tagName(et)}
            ));
        }

        const where_clause = if (conditions.items.len > 0)
            try std.mem.join(self.allocator, " AND ", conditions.items)
        else
            "";

        const query_sql = try std.fmt.allocPrint(
            self.allocator,
            "SELECT * FROM audit_log WHERE {s} ORDER BY timestamp DESC LIMIT {d}",
            .{ where_clause, filters.limit }
        );

        // 执行查询...
        // 返回结果
    }

    pub const QueryFilters = struct {
        start_time: ?i64 = null,
        end_time: ?i64 = null,
        event_type: ?AuditEvent.EventType = null,
        user: ?[]const u8 = null,
        limit: u32 = 100,
    };
};
```

### 2.2 敏感操作审计

```zig
// 使用示例
pub fn submitOrder(
    ctx: *TradingContext,
    request: OrderRequest,
) !Order {
    // 记录订单提交
    try ctx.audit_logger.log(.{
        .timestamp = std.time.milliTimestamp(),
        .event_type = .order_submitted,
        .user = ctx.user_id,
        .resource = request.pair.symbol(),
        .action = "submit_order",
        .details = try std.json.parseFromValue(
            std.json.Value,
            ctx.allocator,
            request,
            .{}
        ),
        .ip_address = ctx.ip_address,
        .success = true,
        .error_message = null,
    });

    const order = try ctx.order_manager.submitOrder(request);

    return order;
}
```

---

## 3. API 访问控制

### 3.1 认证系统

```zig
// src/security/auth.zig

pub const AuthManager = struct {
    allocator: std.mem.Allocator,
    api_keys: std.StringHashMap(APIKeyInfo),
    sessions: std.StringHashMap(Session),

    pub const APIKeyInfo = struct {
        key_hash: [32]u8,
        name: []const u8,
        permissions: KeyPermissions,
        rate_limit: RateLimit,
        created_at: i64,
        last_used: i64,
        expires_at: ?i64,
    };

    pub const Session = struct {
        token: []const u8,
        user: []const u8,
        permissions: KeyPermissions,
        created_at: i64,
        expires_at: i64,
        ip_address: []const u8,
    };

    pub const RateLimit = struct {
        requests_per_minute: u32 = 60,
        requests_per_hour: u32 = 1000,

        current_minute: std.ArrayList(i64),
        current_hour: std.ArrayList(i64),
    };

    pub fn init(allocator: std.mem.Allocator) AuthManager {
        return .{
            .allocator = allocator,
            .api_keys = std.StringHashMap(APIKeyInfo).init(allocator),
            .sessions = std.StringHashMap(Session).init(allocator),
        };
    }

    /// 创建 API Key
    pub fn createAPIKey(
        self: *AuthManager,
        name: []const u8,
        permissions: KeyPermissions,
    ) ![]const u8 {
        // 生成随机 API key
        var key_bytes: [32]u8 = undefined;
        std.crypto.random.bytes(&key_bytes);

        const api_key = try std.fmt.allocPrint(
            self.allocator,
            "zq_{s}",
            .{std.fmt.fmtSliceHexLower(&key_bytes)}
        );

        // Hash API key for storage
        var key_hash: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(api_key, &key_hash, .{});

        try self.api_keys.put(api_key, .{
            .key_hash = key_hash,
            .name = try self.allocator.dupe(u8, name),
            .permissions = permissions,
            .rate_limit = .{
                .current_minute = std.ArrayList(i64).init(self.allocator),
                .current_hour = std.ArrayList(i64).init(self.allocator),
            },
            .created_at = std.time.milliTimestamp(),
            .last_used = 0,
            .expires_at = null,
        });

        return api_key;
    }

    /// 验证 API Key
    pub fn authenticate(
        self: *AuthManager,
        api_key: []const u8,
    ) !APIKeyInfo {
        const info = self.api_keys.getPtr(api_key) orelse
            return error.InvalidAPIKey;

        // 检查过期
        if (info.expires_at) |expires| {
            if (std.time.milliTimestamp() > expires) {
                return error.APIKeyExpired;
            }
        }

        // 检查速率限制
        try self.checkRateLimit(info);

        // 更新最后使用时间
        info.last_used = std.time.milliTimestamp();

        return info.*;
    }

    fn checkRateLimit(self: *AuthManager, info: *APIKeyInfo) !void {
        const now = std.time.milliTimestamp();
        const one_minute_ago = now - 60_000;
        const one_hour_ago = now - 3600_000;

        // 清理过期记录
        var i: usize = 0;
        while (i < info.rate_limit.current_minute.items.len) {
            if (info.rate_limit.current_minute.items[i] < one_minute_ago) {
                _ = info.rate_limit.current_minute.orderedRemove(i);
            } else {
                i += 1;
            }
        }

        // 检查分钟限制
        if (info.rate_limit.current_minute.items.len >= info.rate_limit.requests_per_minute) {
            return error.RateLimitExceeded;
        }

        // 记录本次请求
        try info.rate_limit.current_minute.append(now);
        try info.rate_limit.current_hour.append(now);
    }

    /// 创建会话令牌
    pub fn createSession(
        self: *AuthManager,
        user: []const u8,
        permissions: KeyPermissions,
        ip_address: []const u8,
    ) ![]const u8 {
        var token_bytes: [32]u8 = undefined;
        std.crypto.random.bytes(&token_bytes);

        const token = try std.fmt.allocPrint(
            self.allocator,
            "sess_{s}",
            .{std.fmt.fmtSliceHexLower(&token_bytes)}
        );

        const now = std.time.milliTimestamp();

        try self.sessions.put(token, .{
            .token = try self.allocator.dupe(u8, token),
            .user = try self.allocator.dupe(u8, user),
            .permissions = permissions,
            .created_at = now,
            .expires_at = now + 24 * 60 * 60 * 1000,  // 24小时
            .ip_address = try self.allocator.dupe(u8, ip_address),
        });

        return token;
    }
};
```

---

## 4. 合规性支持

### 4.1 税务报告

```zig
// src/compliance/tax_reporter.zig

pub const TaxReporter = struct {
    allocator: std.mem.Allocator,
    trades: []Trade,
    cost_basis_method: CostBasisMethod,

    pub const CostBasisMethod = enum {
        fifo,  // First In First Out
        lifo,  // Last In First Out
        hifo,  // Highest In First Out
        specific_identification,
    };

    pub const TaxReport = struct {
        year: u32,
        short_term_gains: []CapitalGain,
        long_term_gains: []CapitalGain,
        total_proceeds: Decimal,
        total_cost_basis: Decimal,
        net_gain_loss: Decimal,

        pub const CapitalGain = struct {
            asset: []const u8,
            date_acquired: i64,
            date_sold: i64,
            proceeds: Decimal,
            cost_basis: Decimal,
            gain_loss: Decimal,
            holding_period_days: u32,
        };
    };

    pub fn init(
        allocator: std.mem.Allocator,
        trades: []Trade,
        method: CostBasisMethod,
    ) TaxReporter {
        return .{
            .allocator = allocator,
            .trades = trades,
            .cost_basis_method = method,
        };
    }

    /// 生成税务报告
    pub fn generateReport(self: *TaxReporter, year: u32) !TaxReport {
        var short_term = std.ArrayList(TaxReport.CapitalGain).init(self.allocator);
        var long_term = std.ArrayList(TaxReport.CapitalGain).init(self.allocator);

        // 按资产分组交易
        var positions = std.StringHashMap(Position).init(self.allocator);

        for (self.trades) |trade| {
            const year_start = yearToTimestamp(year);
            const year_end = yearToTimestamp(year + 1);

            if (trade.timestamp < year_start or trade.timestamp >= year_end) {
                continue;
            }

            if (trade.side == .buy) {
                // 记录买入
                try self.recordPurchase(&positions, trade);
            } else {
                // 计算卖出的资本利得
                const gains = try self.calculateGains(&positions, trade);

                for (gains) |gain| {
                    if (gain.holding_period_days > 365) {
                        try long_term.append(gain);
                    } else {
                        try short_term.append(gain);
                    }
                }
            }
        }

        // 计算总计
        var total_proceeds = Decimal.ZERO;
        var total_cost = Decimal.ZERO;

        for (short_term.items) |gain| {
            total_proceeds = total_proceeds.add(gain.proceeds);
            total_cost = total_cost.add(gain.cost_basis);
        }
        for (long_term.items) |gain| {
            total_proceeds = total_proceeds.add(gain.proceeds);
            total_cost = total_cost.add(gain.cost_basis);
        }

        return .{
            .year = year,
            .short_term_gains = try short_term.toOwnedSlice(),
            .long_term_gains = try long_term.toOwnedSlice(),
            .total_proceeds = total_proceeds,
            .total_cost_basis = total_cost,
            .net_gain_loss = total_proceeds.sub(total_cost),
        };
    }

    /// 导出为 IRS Form 8949 格式
    pub fn exportForm8949(self: *TaxReporter, report: TaxReport) ![]const u8 {
        var output = std.ArrayList(u8).init(self.allocator);
        const writer = output.writer();

        try writer.print("Form 8949 - Sales and Other Dispositions of Capital Assets\n", .{});
        try writer.print("Tax Year: {d}\n\n", .{report.year});

        try writer.print("Short-Term Transactions:\n", .{});
        try writer.print("Description,Date Acquired,Date Sold,Proceeds,Cost Basis,Gain/Loss\n", .{});

        for (report.short_term_gains) |gain| {
            try writer.print("{s},{d},{d},{d},{d},{d}\n", .{
                gain.asset,
                gain.date_acquired,
                gain.date_sold,
                gain.proceeds.toFloat(),
                gain.cost_basis.toFloat(),
                gain.gain_loss.toFloat(),
            });
        }

        try writer.print("\nLong-Term Transactions:\n", .{});
        for (report.long_term_gains) |gain| {
            try writer.print("{s},{d},{d},{d},{d},{d}\n", .{
                gain.asset,
                gain.date_acquired,
                gain.date_sold,
                gain.proceeds.toFloat(),
                gain.cost_basis.toFloat(),
                gain.gain_loss.toFloat(),
            });
        }

        try writer.print("\nSummary:\n", .{});
        try writer.print("Total Proceeds: ${d:.2}\n", .{report.total_proceeds.toFloat()});
        try writer.print("Total Cost Basis: ${d:.2}\n", .{report.total_cost_basis.toFloat()});
        try writer.print("Net Gain/Loss: ${d:.2}\n", .{report.net_gain_loss.toFloat()});

        return output.toOwnedSlice();
    }

    fn calculateGains(
        self: *TaxReporter,
        positions: *std.StringHashMap(Position),
        sale: Trade,
    ) ![]TaxReport.CapitalGain {
        var gains = std.ArrayList(TaxReport.CapitalGain).init(self.allocator);

        var remaining = sale.amount;

        switch (self.cost_basis_method) {
            .fifo => {
                // 使用最早的买入记录
                // ...
            },
            .lifo => {
                // 使用最晚的买入记录
                // ...
            },
            // ...
        }

        return gains.toOwnedSlice();
    }
};
```

---

## 5. 数据加密与传输安全

### 5.1 传输层安全

```zig
// src/network/secure_http.zig

pub const SecureHTTPClient = struct {
    allocator: std.mem.Allocator,
    tls_config: TLSConfig,

    pub const TLSConfig = struct {
        min_version: TLSVersion = .tls_1_2,
        verify_peer: bool = true,
        verify_hostname: bool = true,
        ca_bundle: ?[]const u8 = null,

        pub const TLSVersion = enum {
            tls_1_2,
            tls_1_3,
        };
    };

    pub fn init(allocator: std.mem.Allocator, config: TLSConfig) !SecureHTTPClient {
        return .{
            .allocator = allocator,
            .tls_config = config,
        };
    }

    pub fn get(self: *SecureHTTPClient, url: []const u8) ![]const u8 {
        // 验证 URL 使用 HTTPS
        if (!std.mem.startsWith(u8, url, "https://")) {
            return error.InsecureConnection;
        }

        // 使用 TLS 连接
        // ...
    }

    /// 证书 pinning
    pub fn pinCertificate(self: *SecureHTTPClient, host: []const u8, fingerprint: []const u8) !void {
        // 固定特定主机的证书指纹
        // 防止中间人攻击
    }
};
```

### 5.2 敏感数据脱敏

```zig
// src/security/masking.zig

pub const DataMasking = struct {
    /// 脱敏 API 密钥 (只显示前4位和后4位)
    pub fn maskAPIKey(api_key: []const u8) []const u8 {
        if (api_key.len <= 8) return "****";

        return std.fmt.allocPrint(
            allocator,
            "{s}...{s}",
            .{ api_key[0..4], api_key[api_key.len-4..] }
        ) catch "****";
    }

    /// 脱敏金额 (大额交易)
    pub fn maskAmount(amount: Decimal, threshold: Decimal) []const u8 {
        if (amount.cmp(threshold) == .gt) {
            return ">10000";
        }
        return amount.toString();
    }
};
```

---

## 6. 安全检查清单

### 生产部署前检查

- [ ] **密钥管理**
  - [ ] 所有 API 密钥已加密存储
  - [ ] 主密钥使用强密码派生
  - [ ] 密钥权限已正确配置
  - [ ] 不允许提现权限的密钥

- [ ] **审计日志**
  - [ ] 所有敏感操作已记录
  - [ ] 日志定期归档
  - [ ] 日志完整性验证机制

- [ ] **访问控制**
  - [ ] API 认证已启用
  - [ ] 速率限制已配置
  - [ ] Session 超时已设置
  - [ ] IP 白名单(可选)

- [ ] **传输安全**
  - [ ] 仅使用 HTTPS
  - [ ] TLS 1.2+ 强制启用
  - [ ] 证书验证已启用

- [ ] **合规性**
  - [ ] 税务报告功能已测试
  - [ ] 交易记录保留策略已定义

- [ ] **应急响应**
  - [ ] Kill Switch 测试通过
  - [ ] 密钥轮换流程已演练
  - [ ] 数据恢复流程已验证

---

*Last updated: 2025-01*
