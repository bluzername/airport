/**
 * Bonjour/mDNS service advertisement for Airport mobile sync.
 * Advertises the sync server on the local network so the iOS app
 * can discover it automatically without manual IP entry.
 *
 * Uses dns-sd CLI on macOS (built-in) and avahi-publish on Linux.
 * Falls back gracefully if neither is available.
 */

import { execFile } from 'node:child_process';
import type { ChildProcess } from 'node:child_process';
import os from 'node:os';

const SERVICE_TYPE = '_airport-sync._tcp';

let advertiseProcess: ChildProcess | null = null;

/**
 * Get the machine's local network IP addresses (non-loopback IPv4).
 */
export function getLocalIPs(): string[] {
  const interfaces = os.networkInterfaces();
  const ips: string[] = [];
  for (const name of Object.keys(interfaces)) {
    for (const iface of interfaces[name] || []) {
      if (iface.family === 'IPv4' && !iface.internal) {
        ips.push(iface.address);
      }
    }
  }
  return ips;
}

/**
 * Start advertising the Airport sync service via mDNS.
 */
export function startAdvertising(port: number): void {
  stopAdvertising();

  const machineName = os.hostname().replace(/\.local$/, '');
  const serviceName = `Airport - ${machineName}`;

  if (process.platform === 'darwin') {
    // macOS: use built-in dns-sd
    advertiseProcess = execFile('dns-sd', [
      '-R', serviceName, SERVICE_TYPE, 'local', String(port),
    ]);
    advertiseProcess.on('error', () => {
      advertiseProcess = null;
    });
  } else if (process.platform === 'linux') {
    // Linux: try avahi-publish
    advertiseProcess = execFile('avahi-publish', [
      '-s', serviceName, SERVICE_TYPE, String(port),
    ]);
    advertiseProcess.on('error', () => {
      advertiseProcess = null;
    });
  }
  // Windows: no built-in mDNS — mobile app will use manual IP entry
}

/**
 * Stop advertising the service.
 */
export function stopAdvertising(): void {
  if (advertiseProcess) {
    advertiseProcess.kill();
    advertiseProcess = null;
  }
}

/**
 * Check if Bonjour advertising is currently active.
 */
export function isAdvertising(): boolean {
  return advertiseProcess !== null && !advertiseProcess.killed;
}
