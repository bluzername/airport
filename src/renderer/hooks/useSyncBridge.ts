/**
 * Bridges the renderer Zustand store with the sync server in the main process.
 * Pushes state snapshots whenever the store changes, and applies
 * commands received from mobile clients.
 */

import { useEffect } from 'react';
import { useTerminalStore } from '../store/terminal-store';

export function useSyncBridge(): void {
  useEffect(() => {
    const sync = window.airportSync;
    if (!sync) return;

    // Push state to sync server whenever the store changes
    const unsub = useTerminalStore.subscribe((state) => {
      sync.updateSnapshot({
        sessions: state.sessions,
        workspaces: state.workspaces,
        activeSessionId: state.activeSessionId,
        activeWorkspaceId: state.activeWorkspaceId,
      });
    });

    // Listen for mobile → desktop commands
    const cleanups: (() => void)[] = [unsub];

    cleanups.push(
      sync.onSessionRename((id, title) => {
        useTerminalStore.getState().setSessionTitle(id, title, true);
      }),
    );

    cleanups.push(
      sync.onSessionBacklog((id) => {
        useTerminalStore.getState().moveToBacklog(id);
      }),
    );

    cleanups.push(
      sync.onSessionRestore((id) => {
        useTerminalStore.getState().restoreFromBacklog(id);
      }),
    );

    cleanups.push(
      sync.onSessionSetActive((id) => {
        useTerminalStore.getState().setActiveSession(id);
      }),
    );

    cleanups.push(
      sync.onWorkspaceSwitch((id) => {
        useTerminalStore.getState().setActiveWorkspace(id);
      }),
    );

    return () => {
      for (const cleanup of cleanups) cleanup();
    };
  }, []);
}
