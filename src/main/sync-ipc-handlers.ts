/**
 * IPC handlers for mobile sync features.
 * Bridges the renderer process with the sync server.
 */

import { ipcMain, BrowserWindow } from 'electron';
import { IPC } from '../shared/ipc-channels';
import { PtyManager } from './pty-manager';
import {
  startSyncServer, updateSnapshot, startPairing,
  getSyncStatus, sendPlanContent,
} from './sync-server';
import {
  loadSyncConfig, saveSyncConfig, removePairedDevice,
} from './sync-auth';
import type { TerminalSession, Workspace } from '../shared/types';

interface SnapshotPayload {
  sessions: TerminalSession[];
  workspaces: Workspace[];
  activeSessionId: string | null;
  activeWorkspaceId: string;
}

export function registerSyncIpcHandlers(
  getWindow: () => BrowserWindow | null,
  ptyManager: PtyManager,
  getSyncHandle: () => { stop: () => void } | null,
  setSyncHandle: (handle: { stop: () => void } | null) => void,
): void {
  // Renderer pushes state snapshots to sync server
  ipcMain.on(IPC.SYNC_UPDATE_SNAPSHOT, (_event, payload: SnapshotPayload) => {
    updateSnapshot(payload);
  });

  // Start pairing mode — returns QR data
  ipcMain.handle(IPC.SYNC_START_PAIRING, () => {
    // Ensure server is running
    if (!getSyncHandle()) {
      const handle = startSyncServer(ptyManager, getWindow);
      setSyncHandle(handle);
      const config = loadSyncConfig();
      config.enabled = true;
      saveSyncConfig(config);
    }
    return startPairing();
  });

  // Get sync server status
  ipcMain.handle(IPC.SYNC_GET_STATUS, () => {
    return getSyncStatus();
  });

  // Enable/disable sync
  ipcMain.handle(IPC.SYNC_SET_ENABLED, (_event, enabled: boolean) => {
    const config = loadSyncConfig();
    config.enabled = enabled;
    saveSyncConfig(config);

    if (enabled && !getSyncHandle()) {
      const handle = startSyncServer(ptyManager, getWindow);
      setSyncHandle(handle);
    } else if (!enabled && getSyncHandle()) {
      getSyncHandle()!.stop();
      setSyncHandle(null);
    }
  });

  // Remove a paired device
  ipcMain.handle(IPC.SYNC_REMOVE_DEVICE, (_event, deviceId: string) => {
    removePairedDevice(deviceId);
  });

  // Forward plan content to mobile (called from renderer when plan is read)
  ipcMain.on(IPC.SYNC_PLAN_CONTENT, (_event, sessionId: string, filename: string, content: string) => {
    sendPlanContent(sessionId, filename, content);
  });
}
