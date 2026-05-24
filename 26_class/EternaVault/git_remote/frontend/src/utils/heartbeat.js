import { keccak_256 } from '@noble/hashes/sha3';

export function randomSecretHex() {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  return `0x${Array.from(bytes, (byte) => byte.toString(16).padStart(2, '0')).join('')}`;
}

export function heartbeatCommitment(secretHex, epoch) {
  const secret = hexToBytes(secretHex);
  if (secret.length !== 32) throw new Error('Heartbeat secret must be 32 bytes.');
  const encodedEpoch = uint256Bytes(BigInt(epoch));
  return `0x${bytesToHex(keccak_256(new Uint8Array([...secret, ...encodedEpoch])))}`;
}

export function rememberHeartbeatSecret(vault, epoch, secretHex) {
  localStorage.setItem(`memcap:heartbeat:${vault}:${epoch}`, secretHex);
}

export function readHeartbeatSecret(vault, epoch) {
  return localStorage.getItem(`memcap:heartbeat:${vault}:${epoch}`) || '';
}

function hexToBytes(hex) {
  const clean = String(hex || '').replace(/^0x/, '');
  if (!/^[0-9a-fA-F]*$/.test(clean) || clean.length % 2 !== 0) throw new Error('Invalid hex string.');
  const bytes = new Uint8Array(clean.length / 2);
  for (let i = 0; i < bytes.length; i++) {
    bytes[i] = Number.parseInt(clean.slice(i * 2, i * 2 + 2), 16);
  }
  return bytes;
}

function uint256Bytes(value) {
  const bytes = new Uint8Array(32);
  let current = value;
  for (let i = 31; i >= 0; i--) {
    bytes[i] = Number(current & 0xffn);
    current >>= 8n;
  }
  return bytes;
}

function bytesToHex(bytes) {
  return Array.from(bytes, (byte) => byte.toString(16).padStart(2, '0')).join('');
}
