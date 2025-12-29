# zigQuant TUI Design Document

## Overview

This document describes the design and architecture for zigQuant's Terminal User Interface (TUI), replacing the current Web-based interface.

## Architecture

### Current Architecture (Web)
```
┌─────────────────┐     ┌──────────────┐     ┌─────────────────┐
│  React Frontend │────▶│  Zap HTTP    │────▶│  Engine Manager │
│  (Browser)      │◀────│  Server      │◀────│  (Trading)      │
└─────────────────┘     └──────────────┘     └─────────────────┘
        │                      │
        └── WebSocket ─────────┘
        
Issues:
- Multiple processes
- WebSocket thread management
- Complex shutdown sequence
- Browser dependency
```

### New Architecture (TUI)
```
┌─────────────────────────────────────────────────────────────┐
│                    Single Zig Process                        │
│  ┌─────────────┐     ┌──────────────┐     ┌───────────────┐ │
│  │  TUI Layer  │────▶│  App State   │────▶│ Engine Manager│ │
│  │  (libvaxis) │◀────│  (Model)     │◀────│  (Trading)    │ │
│  └─────────────┘     └──────────────┘     └───────────────┘ │
│         │                                         │          │
│         └─────────── Event Loop ──────────────────┘          │
└─────────────────────────────────────────────────────────────┘

Benefits:
- Single process, clean shutdown
- Direct function calls
- No network layer
- Simple event loop
```

## Component Design

### 1. Application State (Model)

```zig
const AppState = struct {
    allocator: Allocator,
    engine_manager: *EngineManager,
    
    // UI State
    selected_session_idx: usize,
    sessions: []LiveSummary,
    current_view: View,
    
    // Dialog state
    show_new_session_dialog: bool,
    new_session_form: NewSessionForm,
    
    // Refresh
    last_refresh: i64,
    refresh_interval_ms: u64,
    
    pub const View = enum {
        dashboard,
        session_detail,
        logs,
        help,
    };
};
```

### 2. Views

#### Dashboard View
- Session list (left panel)
- Selected session details (right panel)
- Action bar (bottom)

#### Session Detail View
- Full session information
- Order history
- Trade history
- Real-time updates

#### Logs View
- Scrollable log buffer
- Filter by level
- Search functionality

#### Help View
- Keyboard shortcuts
- Command reference

### 3. Widgets

Using libvaxis vxfw framework:

```zig
// Custom Widgets
const SessionList = struct {
    sessions: []LiveSummary,
    selected: usize,
    
    pub fn widget(self: *SessionList) vxfw.Widget { ... }
    pub fn draw(self: *SessionList, ctx: vxfw.DrawContext) !vxfw.Surface { ... }
};

const SessionDetail = struct {
    session: ?LiveSummary,
    
    pub fn widget(self: *SessionDetail) vxfw.Widget { ... }
    pub fn draw(self: *SessionDetail, ctx: vxfw.DrawContext) !vxfw.Surface { ... }
};

const OrderTable = struct {
    orders: []OrderInfo,
    
    pub fn widget(self: *OrderTable) vxfw.Widget { ... }
    pub fn draw(self: *OrderTable, ctx: vxfw.DrawContext) !vxfw.Surface { ... }
};
```

### 4. Event Handling

```zig
fn handleEvent(state: *AppState, event: vxfw.Event) !void {
    switch (event) {
        .key_press => |key| {
            if (key.matches('q', .{})) {
                // Quit
            } else if (key.matches('n', .{})) {
                // New session
            } else if (key.matches('s', .{})) {
                // Start session
            } else if (key.matches('p', .{})) {
                // Pause session
            } else if (key.matches('x', .{})) {
                // Stop session
            } else if (key.matches('j', .{}) or key.codepoint == .down) {
                // Move down in list
            } else if (key.matches('k', .{}) or key.codepoint == .up) {
                // Move up in list
            }
        },
        .winsize => |ws| {
            // Handle terminal resize
        },
        else => {},
    }
}
```

## Screen Layouts

### Main Dashboard (80x24 minimum)

```
┌──────────────────────────────────────────────────────────────────────────────┐
│ zigQuant Trading Dashboard                    BTC: $94,523.00    12:34:56   │
├──────────────────────────────────────────────────────────────────────────────┤
│ Sessions (3)                    │ btc_grid - Details                         │
│ ┌─────────────────────────────┐ │ ┌───────────────────────────────────────┐  │
│ │▶ btc_grid    [●] Running 5x │ │ │ Strategy: grid     Leverage: 5x      │  │
│ │  eth_dca     [‖] Paused  1x │ │ │ Symbol: BTC        Timeframe: 1h     │  │
│ │  sol_trend   [■] Stopped 3x │ │ │ Exchange: hyperliquid (testnet)      │  │
│ └─────────────────────────────┘ │ ├───────────────────────────────────────┤  │
│                                 │ │ Balance:    $995.29                   │  │
│                                 │ │ Position:   0.05 BTC                  │  │
│                                 │ │ Entry:      $94,100.00                │  │
│ ─────────────────────────────── │ │ Unrealized: +$21.15 (+2.25%)         │  │
│ Quick Stats                     │ │ Realized:   +$45.30                   │  │
│ ┌─────────────────────────────┐ │ ├───────────────────────────────────────┤  │
│ │ Total PnL:   +$66.45        │ │ │ Grid: $93,000 - $95,000 (10 levels) │  │
│ │ Win Rate:    65%            │ │ │ Order Size: 0.001 BTC                │  │
│ │ Total Trades: 23            │ │ │ Orders: 2 pending, 5 filled          │  │
│ └─────────────────────────────┘ │ └───────────────────────────────────────┘  │
├──────────────────────────────────────────────────────────────────────────────┤
│ [N]ew  [S]tart  [P]ause  [X]Stop  [L]ogs  [H]elp  [Q]uit          Testnet   │
└──────────────────────────────────────────────────────────────────────────────┘
```

### New Session Dialog

```
┌─────────────────────────────────────────────────────────────────────┐
│                                                                      │
│  ┌─────────────────── New Trading Session ───────────────────────┐  │
│  │                                                                │  │
│  │  Name:      [btc_scalp________________]                       │  │
│  │  Symbol:    [BTC_______] ▼                                    │  │
│  │  Exchange:  [hyperliquid] ▼                                   │  │
│  │  Strategy:  [grid______] ▼                                    │  │
│  │  Timeframe: [1h________] ▼                                    │  │
│  │                                                                │  │
│  │  ─── Capital & Risk ───                                       │  │
│  │  Initial Capital: [0______] (0 = real balance)                │  │
│  │  Leverage:        [5______] (1-100)                           │  │
│  │                                                                │  │
│  │  ─── Grid Parameters ───                                      │  │
│  │  Upper Price:     [95000___]                                  │  │
│  │  Lower Price:     [93000___]                                  │  │
│  │  Grid Levels:     [10______]                                  │  │
│  │  Order Size:      [0.001___]                                  │  │
│  │                                                                │  │
│  │  [x] Testnet Mode                                             │  │
│  │                                                                │  │
│  │  ┌──────────┐    ┌──────────┐                                 │  │
│  │  │  Create  │    │  Cancel  │                                 │  │
│  │  └──────────┘    └──────────┘                                 │  │
│  └────────────────────────────────────────────────────────────────┘  │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### Logs View

```
┌──────────────────────────────────────────────────────────────────────────────┐
│ Logs - [A]ll [I]nfo [W]arn [E]rror                      [/] Search  [Q] Back │
├──────────────────────────────────────────────────────────────────────────────┤
│ 12:34:56 [INFO]  LiveRunner: Session btc_grid started                        │
│ 12:34:57 [INFO]  WebSocket connected to hyperliquid testnet                  │
│ 12:34:58 [INFO]  Subscribed to BTC trades                                    │
│ 12:35:00 [DEBUG] Received tick: BTC $94,523.00                               │
│ 12:35:01 [INFO]  Signal: ENTRY_LONG @ $94,500.00                             │
│ 12:35:02 [INFO]  Order submitted: BUY 0.001 BTC @ $94,500.00                 │
│ 12:35:02 [INFO]  Order filled: ID=12345                                      │
│ 12:35:10 [WARN]  Rate limit approaching (80%)                                │
│ 12:35:15 [DEBUG] Received tick: BTC $94,550.00                               │
│ 12:35:20 [INFO]  Signal: EXIT_LONG @ $94,600.00                              │
│                                                                              │
│                                                                              │
│                                                                              │
├──────────────────────────────────────────────────────────────────────────────┤
│ Showing 10 of 156 entries                                        Page 1/16  │
└──────────────────────────────────────────────────────────────────────────────┘
```

## Keyboard Shortcuts

| Key | Action |
|-----|--------|
| `q` | Quit application |
| `n` | New session |
| `s` | Start selected session |
| `p` | Pause selected session |
| `x` | Stop selected session |
| `j` / `↓` | Move down in list |
| `k` / `↑` | Move up in list |
| `Enter` | Select / Confirm |
| `Esc` | Cancel / Back |
| `l` | View logs |
| `h` / `?` | Help |
| `r` | Refresh data |
| `Tab` | Switch panels |

## Color Scheme

```zig
const Colors = struct {
    // Status colors
    pub const running = vaxis.Color{ .rgb = .{ 0, 255, 0 } };    // Green
    pub const paused = vaxis.Color{ .rgb = .{ 255, 255, 0 } };   // Yellow
    pub const stopped = vaxis.Color{ .rgb = .{ 128, 128, 128 } }; // Gray
    pub const error_color = vaxis.Color{ .rgb = .{ 255, 0, 0 } }; // Red
    
    // PnL colors
    pub const profit = vaxis.Color{ .rgb = .{ 0, 255, 0 } };     // Green
    pub const loss = vaxis.Color{ .rgb = .{ 255, 0, 0 } };       // Red
    
    // UI colors
    pub const border = vaxis.Color{ .rgb = .{ 100, 100, 100 } };
    pub const selected_bg = vaxis.Color{ .rgb = .{ 50, 50, 80 } };
    pub const header_bg = vaxis.Color{ .rgb = .{ 30, 30, 50 } };
};
```

## Data Flow

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Event Loop                                   │
│                                                                      │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐      │
│  │ Terminal │───▶│  Event   │───▶│  State   │───▶│  Render  │      │
│  │  Input   │    │ Handler  │    │  Update  │    │  Screen  │      │
│  └──────────┘    └──────────┘    └──────────┘    └──────────┘      │
│       ▲                               │                              │
│       │                               ▼                              │
│       │                        ┌──────────────┐                      │
│       │                        │ Engine       │                      │
│       │                        │ Manager      │                      │
│       │                        │ (Trading)    │                      │
│       │                        └──────────────┘                      │
│       │                               │                              │
│       └───────────── Timer ───────────┘                              │
│                   (Refresh Data)                                     │
└─────────────────────────────────────────────────────────────────────┘
```

## Implementation Phases

### Phase 1: Foundation (Week 1)
- [ ] Add libvaxis dependency
- [ ] Create basic application skeleton
- [ ] Implement main event loop
- [ ] Basic dashboard layout

### Phase 2: Core Features (Week 2)
- [ ] Session list widget
- [ ] Session detail widget  
- [ ] Start/Stop/Pause controls
- [ ] Real-time data refresh

### Phase 3: Session Management (Week 3)
- [ ] New session dialog
- [ ] Form input handling
- [ ] Session creation API
- [ ] Validation

### Phase 4: Advanced Features (Week 4)
- [ ] Log viewer
- [ ] Order table
- [ ] Help screen
- [ ] Error handling & notifications

### Phase 5: Polish (Week 5)
- [ ] Keyboard shortcut hints
- [ ] Loading states
- [ ] Graceful shutdown
- [ ] Testing & bug fixes

## File Structure

```
src/
├── tui/
│   ├── mod.zig              # TUI module root
│   ├── app.zig              # Application state & main loop
│   ├── views/
│   │   ├── dashboard.zig    # Main dashboard view
│   │   ├── session_detail.zig
│   │   ├── logs.zig
│   │   └── help.zig
│   ├── widgets/
│   │   ├── session_list.zig
│   │   ├── session_card.zig
│   │   ├── order_table.zig
│   │   ├── price_display.zig
│   │   └── status_bar.zig
│   ├── dialogs/
│   │   ├── new_session.zig
│   │   └── confirm.zig
│   └── theme.zig            # Colors & styles
├── main.zig                 # Entry point (now starts TUI)
└── ...
```

## Migration Strategy

1. **Keep Web Code**: Don't delete web/ directory immediately
2. **Add TUI Command**: `zigquant tui` starts TUI mode
3. **Default to TUI**: Make TUI the default, `zigquant serve` for web
4. **Deprecate Web**: Mark web as deprecated after TUI is stable
5. **Remove Web**: Delete web code in future version
