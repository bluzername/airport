import { useState, useEffect, useCallback } from 'react';

interface SyncStatus {
  running: boolean;
  port: number;
  connectedDevices: number;
  localIPs: string[];
}

interface PairingInfo {
  host: string;
  port: number;
  token: string;
  publicKey: string;
  name: string;
}

declare global {
  interface Window {
    airportSync?: {
      updateSnapshot: (payload: unknown) => void;
      startPairing: () => Promise<PairingInfo>;
      getStatus: () => Promise<SyncStatus>;
      setEnabled: (enabled: boolean) => Promise<void>;
      removeDevice: (deviceId: string) => Promise<void>;
      sendPlanContent: (sessionId: string, filename: string, content: string) => void;
      onSessionRename: (cb: (id: string, title: string) => void) => () => void;
      onSessionBacklog: (cb: (id: string) => void) => () => void;
      onSessionRestore: (cb: (id: string) => void) => () => void;
      onSessionSetActive: (cb: (id: string) => void) => () => void;
      onWorkspaceSwitch: (cb: (id: string) => void) => () => void;
    };
  }
}

export function SyncSettingsPanel({ onClose }: { onClose: () => void }) {
  const [status, setStatus] = useState<SyncStatus | null>(null);
  const [pairing, setPairing] = useState<PairingInfo | null>(null);
  const [loading, setLoading] = useState(false);

  const refreshStatus = useCallback(async () => {
    if (!window.airportSync) return;
    const s = await window.airportSync.getStatus();
    setStatus(s);
  }, []);

  useEffect(() => {
    refreshStatus();
    const interval = setInterval(refreshStatus, 3000);
    return () => clearInterval(interval);
  }, [refreshStatus]);

  const handleToggle = async () => {
    if (!window.airportSync || !status) return;
    setLoading(true);
    await window.airportSync.setEnabled(!status.running);
    await refreshStatus();
    setLoading(false);
  };

  const handleStartPairing = async () => {
    if (!window.airportSync) return;
    setLoading(true);
    const info = await window.airportSync.startPairing();
    setPairing(info);
    setLoading(false);
  };

  const qrData = pairing
    ? JSON.stringify({ h: pairing.host, p: pairing.port, t: pairing.token, n: pairing.name, k: pairing.publicKey })
    : '';

  return (
    <div style={{
      position: 'absolute',
      inset: 0,
      background: 'rgba(0,0,0,0.85)',
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center',
      zIndex: 1000,
    }}>
      <div style={{
        background: '#1e1e2e',
        borderRadius: 12,
        padding: 32,
        width: 420,
        maxHeight: '80vh',
        overflow: 'auto',
        color: '#cdd6f4',
        fontFamily: 'system-ui, -apple-system, sans-serif',
      }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 24 }}>
          <h2 style={{ margin: 0, fontSize: 20, color: '#f5f5f5' }}>Mobile Sync</h2>
          <button
            onClick={onClose}
            style={{
              background: 'none', border: 'none', color: '#6c7086',
              fontSize: 20, cursor: 'pointer', padding: '4px 8px',
            }}
          >
            &times;
          </button>
        </div>

        {/* Status */}
        <div style={{
          background: '#11111b', borderRadius: 8, padding: 16, marginBottom: 16,
        }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
            <span>Sync Server</span>
            <button
              onClick={handleToggle}
              disabled={loading}
              style={{
                background: status?.running ? '#a6e3a1' : '#45475a',
                color: status?.running ? '#1e1e2e' : '#cdd6f4',
                border: 'none', borderRadius: 6, padding: '6px 16px',
                cursor: 'pointer', fontSize: 13, fontWeight: 600,
              }}
            >
              {status?.running ? 'Running' : 'Stopped'}
            </button>
          </div>
          {status?.running && (
            <div style={{ marginTop: 12, fontSize: 13, color: '#a6adc8' }}>
              <div>Port: {status.port}</div>
              <div>Connected devices: {status.connectedDevices}</div>
              {status.localIPs.length > 0 && (
                <div>Network: {status.localIPs.join(', ')}</div>
              )}
            </div>
          )}
        </div>

        {/* Pairing */}
        <div style={{
          background: '#11111b', borderRadius: 8, padding: 16, marginBottom: 16,
        }}>
          <div style={{ marginBottom: 12, fontWeight: 600 }}>Pair Mobile Device</div>
          {pairing ? (
            <div style={{ textAlign: 'center' }}>
              <div style={{
                background: '#fff', borderRadius: 8, padding: 16,
                display: 'inline-block', marginBottom: 12,
              }}>
                {/* QR code placeholder — in production, use a QR library */}
                <div style={{
                  width: 180, height: 180,
                  display: 'flex', alignItems: 'center', justifyContent: 'center',
                  fontSize: 11, color: '#333', wordBreak: 'break-all',
                  fontFamily: 'monospace',
                }}>
                  {qrData}
                </div>
              </div>
              <div style={{ fontSize: 13, color: '#a6adc8', marginBottom: 8 }}>
                Scan with Airport Mobile or enter code:
              </div>
              <div style={{
                fontSize: 32, fontWeight: 700, letterSpacing: 8,
                color: '#89b4fa', fontFamily: 'monospace',
              }}>
                {pairing.token}
              </div>
              <div style={{ fontSize: 12, color: '#6c7086', marginTop: 8 }}>
                Code expires in 5 minutes
              </div>
            </div>
          ) : (
            <button
              onClick={handleStartPairing}
              disabled={loading}
              style={{
                background: '#89b4fa', color: '#1e1e2e',
                border: 'none', borderRadius: 6, padding: '10px 20px',
                cursor: 'pointer', fontSize: 14, fontWeight: 600,
                width: '100%',
              }}
            >
              Generate Pairing Code
            </button>
          )}
        </div>

        {/* Instructions */}
        <div style={{ fontSize: 13, color: '#6c7086', lineHeight: 1.6 }}>
          <div style={{ fontWeight: 600, color: '#a6adc8', marginBottom: 4 }}>How it works:</div>
          <ol style={{ margin: 0, paddingLeft: 20 }}>
            <li>Enable the sync server above</li>
            <li>Install Airport Mobile on your iPhone</li>
            <li>Tap &ldquo;Connect&rdquo; and scan the QR code</li>
            <li>Your sessions sync automatically on the same network</li>
          </ol>
        </div>
      </div>
    </div>
  );
}
