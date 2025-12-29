# Zig TUI Library Research

## Overview

This document evaluates available TUI (Terminal User Interface) libraries for Zig to replace the current Web-based interface in zigQuant.

## Why Switch to TUI?

### Current Web Interface Issues
1. **Shutdown Problems**: WebSocket threads don't cleanly terminate on Ctrl+C
2. **Complexity**: Requires HTTP server (Zap), React frontend, npm build process
3. **Debugging Difficulty**: Multiple processes and async communication make debugging hard
4. **Leverage Issues**: Exchange API calls (like updateLeverage) have signature problems
5. **Resource Usage**: Higher memory footprint due to HTTP server + WebSocket handling

### TUI Advantages
1. **Single Process**: Everything runs in one process, clean shutdown
2. **Simpler Architecture**: Direct terminal I/O, no network layer
3. **Better for Servers**: Works over SSH, no browser needed
4. **Faster Development**: No frontend build step, pure Zig
5. **Lower Latency**: Direct rendering, no HTTP overhead

---

## Evaluated Libraries

### 1. libvaxis (Recommended)
- **Repository**: https://github.com/rockorager/libvaxis
- **Stars**: 1,500+
- **Zig Version**: 0.15.1 (compatible!)
- **License**: MIT
- **Status**: Actively maintained

#### Features
- Modern TUI library, doesn't use terminfo
- Cross-platform: macOS, Windows, Linux/BSD
- RGB color support
- Hyperlinks (OSC 8)
- Kitty Keyboard Protocol
- Mouse support
- Bracketed paste
- Synchronized output
- Image support (kitty graphics protocol)
- Flutter-like widget framework (vxfw)

#### API Levels
1. **Low-level API**: Full control over each cell
2. **High-level Framework (vxfw)**: Widget-based, handles event loop, focus management

#### Example (vxfw)
```zig
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;

var app = try vxfw.App.init(allocator);
defer app.deinit();
try app.run(model.widget(), .{});
```

#### Pros
- Most feature-rich Zig TUI library
- Active development and community
- Good documentation
- Built-in widgets (Button, TextInput, etc.)

#### Cons
- Larger dependency
- May be overkill for simple UIs

---

### 2. mibu
- **Repository**: https://github.com/xyaman/mibu
- **Stars**: 126
- **Zig Version**: 0.15.1 (compatible!)
- **License**: MIT
- **Status**: Beta, actively maintained

#### Features
- Zero heap allocations
- UTF-8 support
- Terminal raw mode
- Text styling (bold, italic, underline)
- Color output (8, 16, 24-bit)
- Cursor movement
- Screen clearing
- Key and mouse event handling

#### Example
```zig
const mibu = @import("mibu");
const color = mibu.color;

std.debug.print("{s}Hello World!\n", .{color.print.bgRGB(97, 37, 160)});
```

#### Pros
- Lightweight, zero allocations
- Simple API
- Good for custom TUI implementations

#### Cons
- Low-level only, no widget system
- Need to build UI framework on top

---

### 3. tuile (Archived)
- **Repository**: https://github.com/akarpovskii/tuile
- **Stars**: 213
- **Status**: **ARCHIVED (March 2025)** - NOT RECOMMENDED

#### Note
This library was archived and is no longer maintained. Do not use.

---

### 4. ziglibs/ansi_term
- **Repository**: https://github.com/ziglibs/ansi_term
- **Stars**: 95
- **License**: MIT

#### Features
- ANSI terminal escape sequences
- Color support
- Cursor control

#### Pros
- Very lightweight
- Part of ziglibs ecosystem

#### Cons
- Very low-level
- No event handling

---

## Recommendation

### Primary Choice: **libvaxis**

For zigQuant's trading dashboard, **libvaxis** is the best choice because:

1. **Widget Framework**: vxfw provides ready-to-use widgets (buttons, text inputs, tables)
2. **Event Loop**: Built-in event handling, no manual thread management
3. **Mouse Support**: Important for interactive trading UI
4. **Active Community**: Regular updates, GitHub Discussions for support
5. **Zig 0.15.1 Compatible**: Works with our current Zig version

### Fallback: **mibu**

If libvaxis proves too heavy, mibu can be used as a foundation to build a custom lightweight TUI. This would require more development effort but offers maximum control.

---

## Integration Plan

### Phase 1: Setup (1-2 days)
1. Add libvaxis dependency to build.zig.zon
2. Create basic TUI application skeleton
3. Test compilation and basic rendering

### Phase 2: Core UI (3-5 days)
1. Dashboard view with session list
2. Session details panel
3. Real-time price display
4. PnL tracking display

### Phase 3: Interactive Features (3-5 days)
1. Create new session dialog
2. Start/Stop/Pause controls
3. Strategy parameter editing
4. Keyboard shortcuts

### Phase 4: Advanced Features (5-7 days)
1. Order book display
2. Trade history table
3. Chart rendering (ASCII/Unicode)
4. Log viewer

---

## UI Design Concept

```
┌─────────────────────────────────────────────────────────────────────────┐
│ zigQuant v0.9.2                           BTC: $94,523.00  │ 12:34:56 │
├─────────────────────────────────────────────────────────────────────────┤
│ Sessions                          │ Session Details                     │
│ ┌───────────────────────────────┐ │ ┌─────────────────────────────────┐ │
│ │ > btc_grid     [Running] 5x   │ │ │ Name: btc_grid                  │ │
│ │   eth_dca      [Paused]  1x   │ │ │ Strategy: grid                  │ │
│ │   sol_mm       [Stopped] 3x   │ │ │ Symbol: BTC                     │ │
│ └───────────────────────────────┘ │ │ Leverage: 5x                    │ │
│                                   │ │ Status: Running                 │ │
│ [N]ew  [S]tart  [P]ause  [X]Stop │ │ ├─────────────────────────────────┤ │
│                                   │ │ │ PnL: +$123.45 (+2.3%)          │ │
├───────────────────────────────────┤ │ │ Position: 0.05 BTC             │ │
│ Orders                            │ │ │ Entry: $94,100.00              │ │
│ ┌───────────────────────────────┐ │ │ │ Current: $94,523.00            │ │
│ │ BUY  0.01 @ 94000 [Pending]   │ │ │ └─────────────────────────────────┘ │
│ │ SELL 0.01 @ 95000 [Pending]   │ │ │                                   │
│ │ BUY  0.01 @ 93500 [Filled]    │ │ │ Grid Levels: 10                   │
│ └───────────────────────────────┘ │ │ Upper: $95,000  Lower: $93,000    │
│                                   │ │ Order Size: 0.001 BTC             │
├───────────────────────────────────┴─┴───────────────────────────────────┤
│ [Q]uit  [R]efresh  [L]ogs  [H]elp                          Testnet     │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## References

- libvaxis documentation: https://rockorager.github.io/libvaxis/
- libvaxis examples: https://github.com/rockorager/libvaxis/tree/main/examples
- mibu examples: https://github.com/xyaman/mibu/tree/main/examples
