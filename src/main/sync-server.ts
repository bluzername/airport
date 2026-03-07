/**
 * WebSocket sync server for Airport mobile companion app.
 *
 * Runs inside the Electron main process. Pushes session state changes
 * to connected mobile clients and receives commands (quick reply, etc.)
 * back from them.
 */

import { createServer, IncomingMessage } from 'node:http';
import type { Server } from 'node:http';
import { WebSocketServer, WebSocket } from 'ws';
import os from 'node:os';
import { BrowserWindow } from 'electron';
import { PtyManager } from './pty-manager';
import { IPC } from '../shared/ipc-channels';
import {
  loadSyncConfig, saveSyncConfig,
  generatePairingToken, generateDeviceToken,
  addPairedDevice, isDeviceAuthorized, touchDevice,
  isPairRateLimited, recordPairFailure, resetPairAttempts,
} from './sync-auth';

// ── Security Constants ────────────────────────────────────────────

const MAX_REQUEST_BODY_BYTES = 4096;       // 4KB max for pairing POST
const MAX_WS_MESSAGE_BYTES = 64 * 1024;   // 64KB max WebSocket message
const MAX_CONNECTED_CLIENTS = 5;           // Max simultaneous connections
const MAX_TERMINAL_SUBSCRIPTIONS = 10;     // Max subscriptions per client
import { startAdvertising, stopAdvertising, getLocalIPs } from './bonjour';
import type {
  ServerMessage, ClientMessage, MobileSession, PairingInfo,
} from '../shared/sync-types';
import { DEFAULT_SYNC_PORT, toMobileSession } from '../shared/sync-types';
import type { TerminalSession, Workspace, HookStatusEvent } from '../shared/types';

// ── Types ─────────────────────────────────────────────────────────

interface ConnectedClient {
  ws: WebSocket;
  deviceId: string;
  authenticated: boolean;
  subscribedTerminals: Set<string>;
}

interface SessionSnapshot {
  sessions: TerminalSession[];
  workspaces: Workspace[];
  activeSessionId: string | null;
  activeWorkspaceId: string;
}

// ── Ring buffer for terminal output per session ───────────────────

const MAX_LINES = 200;
const terminalBuffers = new Map<string, string[]>();

function appendTerminalOutput(sessionId: string, data: string): void {
  let buf = terminalBuffers.get(sessionId);
  if (!buf) {
    buf = [];
    terminalBuffers.set(sessionId, buf);
  }
  // Split on newlines, append
  const lines = data.split('\n');
  buf.push(...lines);
  // Trim to max
  if (buf.length > MAX_LINES) {
    terminalBuffers.set(sessionId, buf.slice(buf.length - MAX_LINES));
  }
}

function getTerminalLines(sessionId: string): string[] {
  return terminalBuffers.get(sessionId) || [];
}

// ── Server ────────────────────────────────────────────────────────

let httpServer: Server | null = null;
let wss: WebSocketServer | null = null;
const clients: ConnectedClient[] = [];

// Pairing state (active pairing session)
let activePairingToken: string | null = null;
let activePairingExpiry = 0;

// Current state snapshot (updated by the renderer via IPC)
let currentSnapshot: SessionSnapshot = {
  sessions: [],
  workspaces: [{ id: 'default', name: 'Default' }],
  activeSessionId: null,
  activeWorkspaceId: 'default',
};

/**
 * Start the sync server.
 */
export function startSyncServer(
  ptyManager: PtyManager,
  getWindow: () => BrowserWindow | null,
): { stop: () => void } {
  const config = loadSyncConfig();
  const port = config.port || DEFAULT_SYNC_PORT;

  httpServer = createServer((req, res) => {
    // Pairing endpoint — mobile scans QR or enters code
    if (req.method === 'POST' && req.url === '/pair') {
      handlePairRequest(req, res);
      return;
    }
    // Health check
    if (req.method === 'GET' && req.url === '/health') {
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ status: 'ok', name: os.hostname() }));
      return;
    }
    res.writeHead(404);
    res.end();
  });

  wss = new WebSocketServer({
    server: httpServer,
    maxPayload: MAX_WS_MESSAGE_BYTES,
  });

  wss.on('connection', (ws: WebSocket) => {
    // Reject if too many connections
    if (clients.length >= MAX_CONNECTED_CLIENTS) {
      ws.close(4008, 'Too many connections');
      return;
    }

    const client: ConnectedClient = {
      ws,
      deviceId: '',
      authenticated: false,
      subscribedTerminals: new Set(),
    };
    clients.push(client);

    ws.on('message', (raw: Buffer | string) => {
      let msg: ClientMessage;
      try {
        msg = JSON.parse(typeof raw === 'string' ? raw : raw.toString('utf-8'));
      } catch {
        return;
      }
      handleClientMessage(client, msg, ptyManager, getWindow);
    });

    ws.on('close', () => {
      const idx = clients.indexOf(client);
      if (idx >= 0) clients.splice(idx, 1);
    });

    ws.on('error', () => {
      ws.close();
    });

    // Client must authenticate within 10 seconds
    setTimeout(() => {
      if (!client.authenticated) {
        ws.close(4001, 'Authentication timeout');
      }
    }, 10000);
  });

  httpServer.listen(port, '0.0.0.0', () => {
    startAdvertising(port);
  });

  httpServer.on('error', (err: NodeJS.ErrnoException) => {
    if (err.code === 'EADDRINUSE') {
      // Port in use — try next port
      httpServer?.listen(port + 1, '0.0.0.0');
    }
  });

  // Hook into PTY data for terminal output forwarding
  const origCreate = ptyManager.create.bind(ptyManager);
  ptyManager.create = function (options, onData, onExit) {
    const sessionId = origCreate(
      options,
      (sid, data) => {
        onData(sid, data);
        // Buffer output and forward to subscribed mobile clients
        appendTerminalOutput(sid, data);
        broadcastToSubscribers(sid, {
          type: 'terminal:output',
          id: sid,
          lines: data.split('\n'),
        });
      },
      onExit,
    );
    return sessionId;
  };

  return {
    stop: () => {
      stopAdvertising();
      for (const client of clients) {
        client.ws.close(1001, 'Server shutting down');
      }
      clients.length = 0;
      wss?.close();
      httpServer?.close();
      wss = null;
      httpServer = null;
    },
  };
}

// ── Pairing ───────────────────────────────────────────────────────

export function startPairing(): PairingInfo {
  activePairingToken = generatePairingToken();
  activePairingExpiry = Date.now() + 5 * 60 * 1000; // 5 minutes

  const config = loadSyncConfig();
  const ips = getLocalIPs();

  return {
    host: ips[0] || '127.0.0.1',
    port: config.port || DEFAULT_SYNC_PORT,
    token: activePairingToken,
    publicKey: '', // Reserved for future E2E encryption
    name: os.hostname(),
  };
}

function handlePairRequest(req: IncomingMessage, res: import('node:http').ServerResponse): void {
  // Rate limiting
  if (isPairRateLimited()) {
    res.writeHead(429, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: 'Too many attempts. Try again later.' }));
    return;
  }

  let body = '';
  let bodySize = 0;

  req.on('data', (chunk: Buffer) => {
    bodySize += chunk.length;
    // Enforce body size limit to prevent memory exhaustion
    if (bodySize > MAX_REQUEST_BODY_BYTES) {
      req.destroy();
      res.writeHead(413, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'Request too large' }));
      return;
    }
    body += chunk.toString();
  });

  req.on('end', () => {
    if (bodySize > MAX_REQUEST_BODY_BYTES) return; // Already handled

    try {
      const { token, deviceName, deviceId } = JSON.parse(body);

      if (!activePairingToken || Date.now() > activePairingExpiry) {
        res.writeHead(403, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: 'No active pairing session' }));
        return;
      }

      // Validate inputs
      if (typeof token !== 'string' || typeof deviceId !== 'string') {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: 'Invalid request' }));
        return;
      }

      if (token !== activePairingToken) {
        const lockedOut = recordPairFailure();
        res.writeHead(401, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({
          error: lockedOut
            ? 'Too many failed attempts. Locked for 1 minute.'
            : 'Invalid pairing token',
        }));
        return;
      }

      // Pairing successful — generate a persistent device token
      resetPairAttempts();
      const deviceToken = generateDeviceToken();

      // Sanitize device name (limit length, strip control chars)
      const safeName = (typeof deviceName === 'string' ? deviceName : 'Unknown Device')
        .slice(0, 64)
        .replace(/[\x00-\x1f\x7f]/g, '');

      addPairedDevice({
        id: deviceId.slice(0, 128),
        name: safeName || 'Unknown Device',
        pairedAt: Date.now(),
        lastSeenAt: Date.now(),
        publicKey: deviceToken,
      });

      // Invalidate pairing token
      activePairingToken = null;

      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({
        deviceToken,
        serverName: os.hostname(),
      }));
    } catch {
      res.writeHead(400, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'Invalid request' }));
    }
  });
}

// ── Client message handling ───────────────────────────────────────

function handleClientMessage(
  client: ConnectedClient,
  msg: ClientMessage,
  ptyManager: PtyManager,
  getWindow: () => BrowserWindow | null,
): void {
  // Auth must be first message
  if (msg.type === 'auth') {
    if (isDeviceAuthorized(msg.deviceId, msg.token)) {
      client.authenticated = true;
      client.deviceId = msg.deviceId;
      touchDevice(msg.deviceId);
      // Send initial snapshot
      sendSnapshot(client);
    } else {
      client.ws.close(4003, 'Unauthorized');
    }
    return;
  }

  if (!client.authenticated) {
    client.ws.close(4001, 'Not authenticated');
    return;
  }

  switch (msg.type) {
    case 'ping':
      send(client, { type: 'pong' });
      break;

    case 'pty:write': {
      // Validate session exists before writing
      const sessionExists = currentSnapshot.sessions.some(s => s.id === msg.sessionId);
      if (!sessionExists) break;
      // Limit write size to prevent abuse (max 1KB per message)
      const data = typeof msg.data === 'string' ? msg.data.slice(0, 1024) : '';
      ptyManager.write(msg.sessionId, data);
      break;
    }

    case 'session:rename': {
      const win = getWindow();
      if (win && !win.isDestroyed()) {
        win.webContents.send('sync:session:rename', msg.id, msg.title);
      }
      break;
    }

    case 'session:backlog': {
      const win = getWindow();
      if (win && !win.isDestroyed()) {
        win.webContents.send('sync:session:backlog', msg.id);
      }
      break;
    }

    case 'session:restore': {
      const win = getWindow();
      if (win && !win.isDestroyed()) {
        win.webContents.send('sync:session:restore', msg.id);
      }
      break;
    }

    case 'session:setActive': {
      const win = getWindow();
      if (win && !win.isDestroyed()) {
        win.webContents.send('sync:session:setActive', msg.id);
      }
      break;
    }

    case 'workspace:switch': {
      const win = getWindow();
      if (win && !win.isDestroyed()) {
        win.webContents.send('sync:workspace:switch', msg.id);
      }
      break;
    }

    case 'plan:request': {
      const win = getWindow();
      if (win && !win.isDestroyed()) {
        win.webContents.send('sync:plan:request', msg.sessionId, msg.filename);
      }
      break;
    }

    case 'terminal:subscribe':
      // Limit subscriptions per client
      if (client.subscribedTerminals.size >= MAX_TERMINAL_SUBSCRIPTIONS) break;
      // Validate session exists
      if (!currentSnapshot.sessions.some(s => s.id === msg.sessionId)) break;
      client.subscribedTerminals.add(msg.sessionId);
      // Send buffered output
      send(client, {
        type: 'terminal:output',
        id: msg.sessionId,
        lines: getTerminalLines(msg.sessionId),
      });
      break;

    case 'terminal:unsubscribe':
      client.subscribedTerminals.delete(msg.sessionId);
      break;
  }
}

// ── Broadcasting ──────────────────────────────────────────────────

function send(client: ConnectedClient, msg: ServerMessage): void {
  if (client.ws.readyState === WebSocket.OPEN) {
    client.ws.send(JSON.stringify(msg));
  }
}

function broadcast(msg: ServerMessage): void {
  const data = JSON.stringify(msg);
  for (const client of clients) {
    if (client.authenticated && client.ws.readyState === WebSocket.OPEN) {
      client.ws.send(data);
    }
  }
}

function broadcastToSubscribers(sessionId: string, msg: ServerMessage): void {
  const data = JSON.stringify(msg);
  for (const client of clients) {
    if (
      client.authenticated &&
      client.subscribedTerminals.has(sessionId) &&
      client.ws.readyState === WebSocket.OPEN
    ) {
      client.ws.send(data);
    }
  }
}

function sendSnapshot(client: ConnectedClient): void {
  send(client, {
    type: 'snapshot',
    sessions: currentSnapshot.sessions.map(toMobileSession),
    workspaces: currentSnapshot.workspaces,
    activeSessionId: currentSnapshot.activeSessionId,
    activeWorkspaceId: currentSnapshot.activeWorkspaceId,
  });
}

// ── Public API for main process integration ───────────────────────

/**
 * Update the current state snapshot.
 * Called by the renderer (via IPC) whenever Zustand store changes.
 */
export function updateSnapshot(snapshot: SessionSnapshot): void {
  const prevSessions = new Map(currentSnapshot.sessions.map(s => [s.id, s]));
  currentSnapshot = snapshot;

  // Diff and broadcast changes
  const currentIds = new Set(snapshot.sessions.map(s => s.id));
  const prevIds = new Set(prevSessions.keys());

  // New sessions
  for (const session of snapshot.sessions) {
    if (!prevIds.has(session.id)) {
      broadcast({ type: 'session:add', session: toMobileSession(session) });
    }
  }

  // Removed sessions
  for (const id of prevIds) {
    if (!currentIds.has(id)) {
      broadcast({ type: 'session:remove', id });
      terminalBuffers.delete(id);
    }
  }

  // Updated sessions
  for (const session of snapshot.sessions) {
    const prev = prevSessions.get(session.id);
    if (!prev) continue;
    const changes = diffSession(prev, session);
    if (changes) {
      broadcast({ type: 'session:update', id: session.id, changes });
    }
  }
}

/**
 * Forward a hook status event to mobile clients.
 */
export function forwardHookStatus(event: HookStatusEvent): void {
  const session = currentSnapshot.sessions.find(s => s.id === event.sessionId);
  if (!session) return;

  // Send notification for waiting-for-input transitions
  if (event.state === 'done' || session.status === 'waiting-for-input') {
    broadcast({
      type: 'notification',
      sessionId: event.sessionId,
      kind: event.state === 'done' ? 'done' : 'waiting',
      title: event.state === 'done' ? 'Task finished' : 'Claude needs you',
      body: `${session.title}: ${event.message}`,
    });
  }
}

/**
 * Send plan content to mobile clients.
 */
export function sendPlanContent(sessionId: string, filename: string, content: string): void {
  broadcast({ type: 'plan:content', sessionId, filename, content });
}

/**
 * Check if any mobile clients are connected.
 */
export function hasConnectedClients(): boolean {
  return clients.some(c => c.authenticated && c.ws.readyState === WebSocket.OPEN);
}

/**
 * Get the sync server status for the settings UI.
 */
export function getSyncStatus(): {
  running: boolean;
  port: number;
  connectedDevices: number;
  localIPs: string[];
} {
  const config = loadSyncConfig();
  return {
    running: httpServer !== null && httpServer.listening,
    port: config.port || DEFAULT_SYNC_PORT,
    connectedDevices: clients.filter(c => c.authenticated).length,
    localIPs: getLocalIPs(),
  };
}

// ── Helpers ───────────────────────────────────────────────────────

function diffSession(
  prev: TerminalSession,
  next: TerminalSession,
): Partial<MobileSession> | null {
  const changes: Partial<MobileSession> = {};
  let hasChanges = false;

  const fields: (keyof MobileSession)[] = [
    'title', 'customTitle', 'status', 'processName', 'isStandby',
    'lastOutputAt', 'hookMessage', 'hookDone', 'waitingQuestion',
    'gitRepo', 'gitBranch', 'colorIndex', 'backlog', 'cwd', 'workspaceId',
  ];

  for (const key of fields) {
    if ((prev as Record<string, unknown>)[key] !== (next as Record<string, unknown>)[key]) {
      (changes as Record<string, unknown>)[key] = (next as Record<string, unknown>)[key];
      hasChanges = true;
    }
  }

  // Check hasPlans
  const prevHasPlans = prev.planFiles.length > 0;
  const nextHasPlans = next.planFiles.length > 0;
  if (prevHasPlans !== nextHasPlans) {
    changes.hasPlans = nextHasPlans;
    hasChanges = true;
  }

  return hasChanges ? changes : null;
}
