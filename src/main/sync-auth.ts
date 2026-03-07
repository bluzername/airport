/**
 * Sync authentication: pairing tokens, device management, and message signing.
 * Uses crypto from Node.js — no external dependencies.
 */

import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { app } from 'electron';
import type { SyncConfig, PairedDevice } from '../shared/sync-types';
import { DEFAULT_SYNC_PORT } from '../shared/sync-types';

const CONFIG_FILE = 'sync-config.json';

function configPath(): string {
  return path.join(app.getPath('userData'), CONFIG_FILE);
}

export function loadSyncConfig(): SyncConfig {
  try {
    const raw = fs.readFileSync(configPath(), 'utf-8');
    const parsed = JSON.parse(raw);
    return {
      enabled: parsed.enabled ?? false,
      port: parsed.port ?? DEFAULT_SYNC_PORT,
      pairedDevices: parsed.pairedDevices ?? [],
    };
  } catch {
    return { enabled: false, port: DEFAULT_SYNC_PORT, pairedDevices: [] };
  }
}

export function saveSyncConfig(config: SyncConfig): void {
  fs.writeFileSync(configPath(), JSON.stringify(config, null, 2), 'utf-8');
}

/**
 * Generate a short-lived pairing token.
 * Returns a 6-character alphanumeric code (easy to type as fallback to QR).
 */
export function generatePairingToken(): string {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // no ambiguous chars
  let token = '';
  const bytes = crypto.randomBytes(6);
  for (let i = 0; i < 6; i++) {
    token += chars[bytes[i] % chars.length];
  }
  return token;
}

/**
 * Generate a random device authentication token (used after pairing).
 */
export function generateDeviceToken(): string {
  return crypto.randomBytes(32).toString('hex');
}

/**
 * Add a paired device to the config.
 */
export function addPairedDevice(device: PairedDevice): void {
  const config = loadSyncConfig();
  // Remove existing device with same ID
  config.pairedDevices = config.pairedDevices.filter(d => d.id !== device.id);
  config.pairedDevices.push(device);
  saveSyncConfig(config);
}

/**
 * Remove a paired device.
 */
export function removePairedDevice(deviceId: string): void {
  const config = loadSyncConfig();
  config.pairedDevices = config.pairedDevices.filter(d => d.id !== deviceId);
  saveSyncConfig(config);
}

/**
 * Check if a device token is valid (belongs to a paired device).
 */
export function isDeviceAuthorized(deviceId: string, token: string): boolean {
  const config = loadSyncConfig();
  const device = config.pairedDevices.find(d => d.id === deviceId);
  if (!device) return false;
  // Token is stored as the device's publicKey field for simplicity
  // In production, use proper challenge-response
  return device.publicKey === token;
}

/**
 * Update lastSeenAt for a device.
 */
export function touchDevice(deviceId: string): void {
  const config = loadSyncConfig();
  const device = config.pairedDevices.find(d => d.id === deviceId);
  if (device) {
    device.lastSeenAt = Date.now();
    saveSyncConfig(config);
  }
}
