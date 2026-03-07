# Airport Mobile — iOS Companion App Plan

## Overview

A native iOS app that provides a seamless mobile extension of the Airport desktop experience. Monitor, interact with, and manage your Claude Code sessions from your phone — with real-time sync between desktop and mobile.

---

## 1. Core Mobile Experience

### What you can do on mobile:

| Feature | Description |
|---------|-------------|
| **Live Session Dashboard** | See all sessions across workspaces with real-time status (busy/idle/standby/waiting-for-input) |
| **Push Notifications** | Get notified when Claude is waiting for input, finishes a task, or encounters an error |
| **Quick Reply** | Answer Claude's questions directly from mobile (approve plans, respond to prompts) |
| **Terminal Viewer** | Read-only scrollable view of recent terminal output per session |
| **Plan Review** | Read and approve Claude Code plan files with markdown rendering |
| **Session Management** | Reorder, rename, move to backlog, switch workspaces |
| **Status at a Glance** | Home screen widget showing session count + how many need attention |

### What stays desktop-only:
- Full terminal input (typing commands, coding)
- Creating new PTY sessions
- Adopting external terminals
- Session spawn requests

---

## 2. Synchronization Architecture

### Approach: Embedded HTTP/WebSocket Server in Desktop App

**No Tailscale required.** The desktop Electron app runs a lightweight sync server that the mobile app connects to.

```
┌─────────────────────┐         ┌──────────────────────┐
│   Airport Desktop   │         │   Airport Mobile     │
│   (Electron)        │         │   (iOS)              │
│                     │  WS/    │                      │
│  ┌───────────────┐  │  HTTPS  │  ┌────────────────┐  │
│  │ Sync Server   │◄─┼────────┼──│ Sync Client    │  │
│  │ (port 19840)  │──┼────────┼─►│                │  │
│  └───────────────┘  │         │  └────────────────┘  │
│         │           │         │         │            │
│  ┌──────▼────────┐  │         │  ┌──────▼─────────┐  │
│  │ Zustand Store │  │         │  │ Local State    │  │
│  │ PTY Manager   │  │         │  │ (SwiftData)    │  │
│  │ Hook Watcher  │  │         │  └────────────────┘  │
│  └───────────────┘  │         │                      │
└─────────────────────┘         └──────────────────────┘
```

### Connection Modes (in priority order):

#### Mode 1: Local Network (LAN) — Primary
- Desktop broadcasts via Bonjour/mDNS (`_airport._tcp`)
- Mobile discovers automatically on same Wi-Fi
- Direct WebSocket connection, sub-50ms latency
- Zero configuration required

#### Mode 2: Cloud Relay — Optional, for remote access
- Lightweight relay server (Cloudflare Workers or fly.io)
- Desktop registers with a short-lived pairing code
- Mobile connects via relay when off-LAN
- End-to-end encrypted (device-generated keys)
- No account required — just a 6-digit pairing code

#### Mode 3: Tailscale — Power user option
- If Tailscale is already installed, detect it
- Connect via Tailscale IP directly (same as LAN mode)
- Works everywhere without relay

### Pairing Flow:
```
Desktop:                          Mobile:
1. Settings → "Mobile Sync"
2. Shows QR code containing:      1. Open app → "Connect"
   - LAN IP:port                   2. Scan QR code
   - Pairing token (one-time)      3. Receives connection info
   - Encryption public key         4. Establishes secure channel
3. Confirms pairing               5. Paired ✓
```

---

## 3. Sync Protocol

### WebSocket Messages (JSON):

```typescript
// Desktop → Mobile
type SyncMessage =
  | { type: 'snapshot'; state: FullState }           // Initial full state
  | { type: 'session:update'; id: string; changes: Partial<Session> }
  | { type: 'session:add'; session: Session }
  | { type: 'session:remove'; id: string }
  | { type: 'terminal:output'; id: string; data: string }  // Recent lines only
  | { type: 'workspace:update'; workspaces: Workspace[] }
  | { type: 'plan:content'; sessionId: string; content: string }
  | { type: 'hook:status'; sessionId: string; status: string; message: string }

// Mobile → Desktop
type MobileMessage =
  | { type: 'pty:write'; sessionId: string; data: string }  // Quick reply
  | { type: 'session:rename'; id: string; title: string }
  | { type: 'session:backlog'; id: string }
  | { type: 'session:restore'; id: string }
  | { type: 'session:setActive'; id: string }
  | { type: 'workspace:switch'; id: string }
  | { type: 'plan:approve'; sessionId: string }              // Write "yes" to PTY
```

### Sync Principles:
- **Desktop is source of truth** — mobile never modifies terminal state directly
- **Incremental updates** — only changed fields sent after initial snapshot
- **Terminal output throttled** — mobile receives last 200 lines per session, batched at 100ms intervals
- **Reconnect resilience** — on reconnect, desktop sends fresh snapshot

---

## 4. Desktop-Side Changes (Electron)

New module: `src/main/sync-server.ts`

### Implementation:

```typescript
// New files needed in the desktop app:
src/main/sync-server.ts       // WebSocket server + REST endpoints
src/main/sync-auth.ts         // Pairing, token management, encryption
src/main/bonjour.ts           // mDNS service advertisement
src/shared/sync-types.ts      // Shared message type definitions
```

### What the sync server does:
1. **Starts on app launch** (configurable port, default 19840)
2. **Advertises via Bonjour** on LAN
3. **Authenticates** mobile clients via pairing token
4. **Subscribes to Zustand store** changes → pushes diffs to mobile
5. **Subscribes to hook watcher** events → forwards to mobile
6. **Buffers terminal output** per session (ring buffer, last 200 lines)
7. **Receives mobile commands** → dispatches to PTY manager / store
8. **Sends push notification triggers** via APNs when:
   - Session goes to `waiting-for-input` status
   - Hook fires `done` event
   - Session exits unexpectedly

### Dependencies to add:
- `ws` — WebSocket server (lightweight, no Express needed)
- `bonjour-service` — mDNS advertisement
- `tweetnacl` — Encryption (small, audited, zero-dep)

---

## 5. iOS App Architecture

### Tech Stack:
| Layer | Technology |
|-------|-----------|
| **UI** | SwiftUI |
| **State** | Swift Observation (`@Observable`) |
| **Networking** | URLSessionWebSocketTask (native) |
| **Local Storage** | SwiftData (lightweight persistence) |
| **Push Notifications** | APNs via local push (no server needed for LAN) |
| **QR Scanning** | AVFoundation |
| **Widgets** | WidgetKit |
| **Min Target** | iOS 17+ |

### App Structure:

```
AirportMobile/
├── App/
│   ├── AirportApp.swift              // Entry point
│   └── AppState.swift                // Root observable state
├── Models/
│   ├── Session.swift                 // Mirror of desktop Session type
│   ├── Workspace.swift               // Workspace model
│   └── ConnectionInfo.swift          // Paired desktop info
├── Networking/
│   ├── SyncClient.swift              // WebSocket connection manager
│   ├── MessageHandler.swift          // Parse/dispatch sync messages
│   ├── BonjourBrowser.swift          // mDNS discovery
│   └── PairingManager.swift          // QR scan + token exchange
├── Views/
│   ├── Dashboard/
│   │   ├── DashboardView.swift       // Main session grid
│   │   ├── SessionCard.swift         // Individual session tile
│   │   └── StatusBadge.swift         // Status indicator
│   ├── Terminal/
│   │   ├── TerminalView.swift        // Read-only terminal output
│   │   └── QuickReplyBar.swift       // Input bar for responses
│   ├── Plan/
│   │   └── PlanView.swift            // Markdown plan viewer
│   ├── Settings/
│   │   ├── SettingsView.swift        // Connection settings
│   │   └── PairingView.swift         // QR scanner
│   └── Onboarding/
│       └── OnboardingFlow.swift      // First-launch pairing guide
├── Widgets/
│   └── SessionStatusWidget.swift     // Home screen widget
└── Utilities/
    ├── HapticFeedback.swift
    └── Theme.swift                   // Match desktop color scheme
```

### Key Screens:

#### Dashboard (Home)
```
┌─────────────────────────────┐
│  Airport          ⚙️        │
│                              │
│  Workspace: Default    ● ○   │
│                              │
│  ┌──────────┐ ┌──────────┐  │
│  │ 🟢 api   │ │ 🟡 auth  │  │
│  │ Running   │ │ Thinking │  │
│  │ agent:fix │ │          │  │
│  └──────────┘ └──────────┘  │
│  ┌──────────┐ ┌──────────┐  │
│  │ 🔴 tests │ │ ⚪ db    │  │
│  │ NEEDS    │ │ Idle     │  │
│  │ INPUT    │ │          │  │
│  └──────────┘ └──────────┘  │
│                              │
│  Backlog (2)            ▼   │
└─────────────────────────────┘
```

#### Terminal View (tap a session)
```
┌─────────────────────────────┐
│  ← api-refactor   🟢 busy  │
│─────────────────────────────│
│                              │
│  $ claude                    │
│  > Reading src/api/routes.ts │
│  > Editing handler.ts        │
│  > Running tests...          │
│                              │
│  ⚡ Do you want to proceed   │
│  with the refactor?          │
│                              │
│  ┌─────────────────────────┐│
│  │ Quick Reply: Yes / No   ││
│  │ [  Custom reply...    ] ││
│  └─────────────────────────┘│
└─────────────────────────────┘
```

---

## 6. Push Notifications

### LAN Mode (no server needed):
- Use **UserNotifications** framework with local scheduling
- Desktop sends notification trigger via WebSocket
- Mobile app schedules local notification immediately
- Works even when app is backgrounded (via background WebSocket keepalive)

### Remote Mode:
- Desktop sends to relay → relay forwards APNs payload
- Lightweight: only sends when session status changes to `waiting-for-input` or `done`

### Notification Types:
| Trigger | Title | Body | Action |
|---------|-------|------|--------|
| Waiting for input | "Claude needs you" | "Session 'api': Do you want to proceed?" | Quick reply |
| Task complete | "Task finished" | "Session 'auth': Authentication flow complete" | View |
| Session error | "Session error" | "Session 'tests' exited unexpectedly" | View |

---

## 7. Security

- **All connections encrypted** via TLS (self-signed cert generated at pairing)
- **Pairing token** is single-use, exchanged for a persistent device key
- **No data stored on any server** — relay mode only forwards encrypted blobs
- **Auto-disconnect** after 30 min of no heartbeat
- **Device management** in desktop settings (revoke mobile access)

---

## 8. Implementation Phases

### Phase 1 — Foundation (Desktop sync server + basic iOS app)
- [ ] `sync-server.ts` — WebSocket server with auth
- [ ] `sync-auth.ts` — QR pairing flow
- [ ] `bonjour.ts` — mDNS advertisement
- [ ] iOS: Bonjour discovery + QR pairing
- [ ] iOS: WebSocket client with reconnect
- [ ] iOS: Dashboard view with live session status
- [ ] iOS: Basic terminal output viewer (read-only)

### Phase 2 — Interaction
- [ ] iOS: Quick reply bar (send text to PTY)
- [ ] iOS: Plan review with markdown rendering
- [ ] iOS: Session management (rename, backlog, workspace switch)
- [ ] Desktop: Terminal output ring buffer + throttled sync
- [ ] Push notifications (local, LAN mode)

### Phase 3 — Polish & Remote
- [ ] iOS: Home screen widget (WidgetKit)
- [ ] iOS: Haptic feedback for status changes
- [ ] Cloud relay for off-LAN access
- [ ] Tailscale auto-detection as alternative
- [ ] Desktop: Settings UI for mobile sync management

### Phase 4 — Advanced
- [ ] iOS: Live Activities (Dynamic Island showing active session)
- [ ] iOS: Shortcuts/Siri integration ("How's my Claude session?")
- [ ] Apple Watch complication (session count + status)
- [ ] Multi-desktop support (pair with multiple machines)

---

## 9. Why This Architecture?

### No Tailscale requirement:
- Bonjour/mDNS discovery is native to Apple ecosystem — zero config on same network
- Optional cloud relay covers remote use without VPN complexity
- Tailscale remains a power-user option that "just works" if present

### No account/login:
- Consistent with Airport's local-first philosophy
- QR pairing is instant and secure
- No dependency on external auth services

### Desktop as source of truth:
- Mobile is a "window" into desktop state, not a separate terminal
- Avoids conflict resolution complexity
- Desktop PTY sessions can't be meaningfully owned by mobile

### Native iOS (not React Native):
- SwiftUI provides best-in-class iOS feel
- WidgetKit, Live Activities, Shortcuts are Swift-only
- Small app — no need for cross-platform abstraction
- Terminal rendering is simple (attributed text, not full xterm)

---

## 10. Estimated Scope

| Component | New Files | Complexity |
|-----------|-----------|------------|
| Desktop sync server | ~4 files, ~600 lines | Medium |
| Desktop UI changes (settings) | ~2 files, ~200 lines | Low |
| iOS app | ~25 files, ~3000 lines | Medium-High |
| iOS widget | ~3 files, ~200 lines | Low |
| Shared types | ~1 file, ~100 lines | Low |
