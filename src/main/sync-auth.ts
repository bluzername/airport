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
const MAX_PAIR_ATTEMPTS = 5;
const PAIR_LOCKOUT_MS = 60 * 1000; // 1 minute lockout after max attempts

// Brute-force protection state
let pairAttemptCount = 0;
let pairLockoutUntil = 0;

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
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // 31 chars, no ambiguous
  let token = '';
  // Use rejection sampling to avoid modulo bias
  for (let i = 0; i < 6; i++) {
    const limit = 256 - (256 % chars.length); // 256 - (256 % 31) = 248
    let val: number;
    do {
      val = crypto.randomBytes(1)[0];
    } while (val >= limit);
    token += chars[val % chars.length];
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
 * Uses timing-safe comparison to prevent timing attacks.
 */
export function isDeviceAuthorized(deviceId: string, token: string): boolean {
  const config = loadSyncConfig();
  const device = config.pairedDevices.find(d => d.id === deviceId);
  if (!device) return false;
  const expected = Buffer.from(device.publicKey, 'utf-8');
  const provided = Buffer.from(token, 'utf-8');
  if (expected.length !== provided.length) return false;
  return crypto.timingSafeEqual(expected, provided);
}

/**
 * Check if pairing attempts are rate-limited.
 */
export function isPairRateLimited(): boolean {
  if (Date.now() < pairLockoutUntil) return true;
  return false;
}

/**
 * Record a failed pairing attempt. Returns true if now locked out.
 */
export function recordPairFailure(): boolean {
  pairAttemptCount++;
  if (pairAttemptCount >= MAX_PAIR_ATTEMPTS) {
    pairLockoutUntil = Date.now() + PAIR_LOCKOUT_MS;
    pairAttemptCount = 0;
    return true;
  }
  return false;
}

/**
 * Reset pairing attempt counter (on success).
 */
export function resetPairAttempts(): void {
  pairAttemptCount = 0;
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
