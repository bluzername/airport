/**
 * Types shared between the desktop sync server and mobile client.
 * These define the WebSocket protocol for Airport mobile sync.
 */

import type { TerminalSession, Workspace, SessionStatus } from './types';

// ── Connection & Auth ──────────────────────────────────────────────

export interface PairingInfo {
  host: string;
  port: number;
  token: string;          // One-time pairing token
  publicKey: string;      // Base64-encoded X25519 public key
  name: string;           // Desktop machine name
}

export interface PairedDevice {
  id: string;             // Unique device ID
  name: string;           // e.g. "iPhone 15 Pro"
  pairedAt: number;       // Timestamp
  lastSeenAt: number;     // Timestamp
  publicKey: string;      // Device's public key
}

export interface SyncConfig {
  enabled: boolean;
  port: number;
  pairedDevices: PairedDevice[];
}

export const DEFAULT_SYNC_PORT = 19840;

// ── Mobile-friendly session (subset of TerminalSession) ───────────

export interface MobileSession {
  id: string;
  title: string;
  customTitle: boolean;
  status: SessionStatus;
  processName: string;
  isStandby: boolean;
  lastOutputAt: number;
  hookMessage: string;
  hookDone: boolean;
  waitingQuestion: string;
  gitRepo: string;
  gitBranch: string;
  colorIndex: number;
  backlog: boolean;
  cwd: string;
  workspaceId: string;
  hasPlans: boolean;       // Simplified: just whether plans exist
}

export function toMobileSession(session: TerminalSession): MobileSession {
  return {
    id: session.id,
    title: session.title,
    customTitle: session.customTitle,
    status: session.status,
    processName: session.processName,
    isStandby: session.isStandby,
    lastOutputAt: session.lastOutputAt,
    hookMessage: session.hookMessage,
    hookDone: session.hookDone,
    waitingQuestion: session.waitingQuestion,
    gitRepo: session.gitRepo,
    gitBranch: session.gitBranch,
    colorIndex: session.colorIndex,
    backlog: session.backlog,
    cwd: session.cwd,
    workspaceId: session.workspaceId,
    hasPlans: session.planFiles.length > 0,
  };
}

// ── Desktop → Mobile messages ─────────────────────────────────────

export type ServerMessage =
  | { type: 'snapshot'; sessions: MobileSession[]; workspaces: Workspace[]; activeSessionId: string | null; activeWorkspaceId: string }
  | { type: 'session:update'; id: string; changes: Partial<MobileSession> }
  | { type: 'session:add'; session: MobileSession }
  | { type: 'session:remove'; id: string }
  | { type: 'terminal:output'; id: string; lines: string[] }
  | { type: 'workspace:update'; workspaces: Workspace[]; activeWorkspaceId: string }
  | { type: 'plan:content'; sessionId: string; filename: string; content: string }
  | { type: 'notification'; sessionId: string; kind: 'waiting' | 'done' | 'error'; title: string; body: string }
  | { type: 'pong' };

// ── Mobile → Desktop messages ─────────────────────────────────────

export type ClientMessage =
  | { type: 'auth'; deviceId: string; token: string }
  | { type: 'pty:write'; sessionId: string; data: string }
  | { type: 'session:rename'; id: string; title: string }
  | { type: 'session:backlog'; id: string }
  | { type: 'session:restore'; id: string }
  | { type: 'session:setActive'; id: string }
  | { type: 'workspace:switch'; id: string }
  | { type: 'plan:request'; sessionId: string; filename: string }
  | { type: 'terminal:subscribe'; sessionId: string }
  | { type: 'terminal:unsubscribe'; sessionId: string }
  | { type: 'ping' };
