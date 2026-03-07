/**
 * TLS certificate management for the sync server.
 *
 * Generates a self-signed certificate on first run and persists it
 * in the app's userData directory. The certificate fingerprint is
 * shared during pairing so the mobile client can pin it.
 */

import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { app } from 'electron';

const CERT_DIR = 'sync-tls';
const CERT_FILE = 'cert.pem';
const KEY_FILE = 'key.pem';
const FINGERPRINT_FILE = 'fingerprint.txt';

function certDir(): string {
  return path.join(app.getPath('userData'), CERT_DIR);
}

export interface TlsCredentials {
  cert: string;
  key: string;
  fingerprint: string;  // SHA-256 fingerprint of the certificate
}

/**
 * Get or generate TLS credentials for the sync server.
 * Generates a self-signed cert on first call, then reuses it.
 */
export function getOrCreateTlsCredentials(): TlsCredentials {
  const dir = certDir();
  const certPath = path.join(dir, CERT_FILE);
  const keyPath = path.join(dir, KEY_FILE);
  const fpPath = path.join(dir, FINGERPRINT_FILE);

  // Check if cert already exists
  if (fs.existsSync(certPath) && fs.existsSync(keyPath) && fs.existsSync(fpPath)) {
    return {
      cert: fs.readFileSync(certPath, 'utf-8'),
      key: fs.readFileSync(keyPath, 'utf-8'),
      fingerprint: fs.readFileSync(fpPath, 'utf-8').trim(),
    };
  }

  // Generate new self-signed certificate
  fs.mkdirSync(dir, { recursive: true });

  const { privateKey, publicKey } = crypto.generateKeyPairSync('ec', {
    namedCurve: 'prime256v1',
  });

  // Create a self-signed X.509 certificate
  // Node.js doesn't have a built-in X.509 builder, so we use
  // a minimal ASN.1 DER construction for the self-signed cert.
  // For simplicity, we'll use the forge-free approach with openssl-compatible
  // PEM output via Node's crypto module (available since Node 15+).
  const cert = generateSelfSignedCert(privateKey, publicKey);

  const keyPem = privateKey.export({ type: 'sec1', format: 'pem' }) as string;

  // Compute SHA-256 fingerprint from the DER-encoded certificate
  const derMatch = cert.match(/-----BEGIN CERTIFICATE-----\n([\s\S]+?)\n-----END CERTIFICATE-----/);
  const derBuffer = Buffer.from(derMatch?.[1]?.replace(/\n/g, '') || '', 'base64');
  const fingerprint = crypto.createHash('sha256').update(derBuffer).digest('hex')
    .match(/.{2}/g)!.join(':').toUpperCase();

  fs.writeFileSync(certPath, cert, { mode: 0o600 });
  fs.writeFileSync(keyPath, keyPem, { mode: 0o600 });
  fs.writeFileSync(fpPath, fingerprint, { mode: 0o600 });

  return { cert, key: keyPem, fingerprint };
}

/**
 * Generate a minimal self-signed X.509 certificate using Node's crypto.
 * Valid for 10 years, with CN=Airport Sync.
 */
function generateSelfSignedCert(
  privateKey: crypto.KeyObject,
  publicKey: crypto.KeyObject,
): string {
  // Use Node's built-in X509Certificate creation (Node 20+)
  // We create a CSR-like structure and self-sign it.
  // Since Node doesn't expose a certificate builder API directly,
  // we use the `crypto.X509Certificate` class for verification but
  // need to build the cert ourselves or use a child process.
  //
  // The cleanest zero-dep approach: use `crypto.createSign` with
  // raw ASN.1 DER encoding. But this is complex, so we use a simpler
  // approach with a pre-built minimal ASN.1 template.

  const now = new Date();
  const expiry = new Date(now.getTime() + 10 * 365.25 * 24 * 60 * 60 * 1000);

  // Export public key in DER format for embedding
  const pubDer = publicKey.export({ type: 'spki', format: 'der' });

  // Build TBS (To-Be-Signed) certificate
  const serialNumber = crypto.randomBytes(8);
  serialNumber[0] &= 0x7f; // Ensure positive

  const tbs = buildTBSCertificate(serialNumber, pubDer, now, expiry);

  // Sign the TBS certificate
  const signer = crypto.createSign('SHA256');
  signer.update(tbs);
  const signature = signer.sign({ key: privateKey, dsaEncoding: 'der' });

  // Build final certificate: SEQUENCE { tbs, signatureAlgorithm, signature }
  const signatureAlgOid = Buffer.from([
    0x30, 0x0a, 0x06, 0x08,
    0x2a, 0x86, 0x48, 0xce, 0x3d, 0x04, 0x03, 0x02, // ecdsa-with-SHA256
  ]);

  const signatureBits = Buffer.concat([
    Buffer.from([0x03, signature.length + 1, 0x00]),
    signature,
  ]);

  const certDer = wrapSequence(Buffer.concat([tbs, signatureAlgOid, signatureBits]));

  // Convert to PEM
  const b64 = certDer.toString('base64');
  const lines = b64.match(/.{1,64}/g) || [];
  return `-----BEGIN CERTIFICATE-----\n${lines.join('\n')}\n-----END CERTIFICATE-----\n`;
}

function buildTBSCertificate(
  serial: Buffer,
  pubKeyDer: Buffer,
  notBefore: Date,
  notAfter: Date,
): Buffer {
  // Version: v3 (explicitly tagged [0])
  const version = Buffer.from([0xa0, 0x03, 0x02, 0x01, 0x02]);

  // Serial number
  const serialNum = wrapTag(0x02, serial);

  // Signature algorithm: ecdsa-with-SHA256
  const sigAlg = Buffer.from([
    0x30, 0x0a, 0x06, 0x08,
    0x2a, 0x86, 0x48, 0xce, 0x3d, 0x04, 0x03, 0x02,
  ]);

  // Issuer: CN=Airport Sync
  const issuer = buildDN('Airport Sync');

  // Validity
  const validity = wrapSequence(Buffer.concat([
    encodeUTCTime(notBefore),
    encodeUTCTime(notAfter),
  ]));

  // Subject: CN=Airport Sync
  const subject = buildDN('Airport Sync');

  return wrapSequence(Buffer.concat([
    version, serialNum, sigAlg, issuer, validity, subject, pubKeyDer,
  ]));
}

function buildDN(cn: string): Buffer {
  const cnOid = Buffer.from([0x06, 0x03, 0x55, 0x04, 0x03]); // OID 2.5.4.3
  const cnValue = wrapTag(0x0c, Buffer.from(cn, 'utf-8')); // UTF8String
  const attrSet = wrapSequence(Buffer.concat([cnOid, cnValue]));
  const rdnSet = wrapTag(0x31, attrSet);
  return wrapSequence(rdnSet);
}

function encodeUTCTime(date: Date): Buffer {
  const yy = (date.getUTCFullYear() % 100).toString().padStart(2, '0');
  const mm = (date.getUTCMonth() + 1).toString().padStart(2, '0');
  const dd = date.getUTCDate().toString().padStart(2, '0');
  const hh = date.getUTCHours().toString().padStart(2, '0');
  const mi = date.getUTCMinutes().toString().padStart(2, '0');
  const ss = date.getUTCSeconds().toString().padStart(2, '0');
  const str = `${yy}${mm}${dd}${hh}${mi}${ss}Z`;
  return wrapTag(0x17, Buffer.from(str, 'ascii'));
}

function wrapTag(tag: number, content: Buffer): Buffer {
  return Buffer.concat([Buffer.from([tag]), encodeLength(content.length), content]);
}

function wrapSequence(content: Buffer): Buffer {
  return wrapTag(0x30, content);
}

function encodeLength(len: number): Buffer {
  if (len < 0x80) return Buffer.from([len]);
  if (len < 0x100) return Buffer.from([0x81, len]);
  return Buffer.from([0x82, (len >> 8) & 0xff, len & 0xff]);
}
