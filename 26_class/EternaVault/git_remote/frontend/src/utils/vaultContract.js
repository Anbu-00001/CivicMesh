export const LEGACY_VAULT_ABI = [
  'function owner() view returns (address)',
  'function heirs(address) view returns (bool)',
  'function canAccess(address) view returns (bool)',
  'function shareThreshold() view returns (uint256)',
  'function encryptedShares(address) view returns (bytes)',
  'function getEncryptedShare(address heir) view returns (bytes)',
  'function claimMyShare() returns (bytes)',
  'function heartbeatEpoch() view returns (uint256)',
  'function lastHeartbeat() view returns (uint256)',
  'function silenceThreshold() view returns (uint256)',
  'function heartbeatCommitment() view returns (bytes32)',
  'function initHeartbeat(bytes32 commitment,uint256 thresholdSeconds)',
  'function renewHeartbeat(bytes32 prevSecret,uint256 prevEpoch,bytes32 newCommitment)',
  'function escalateAccess()',
  'function setShareThreshold(uint256 threshold)',
  'function depositEncryptedShare(address heir,bytes encryptedShare)'
];

export function vaultAddress() {
  return import.meta.env.VITE_LEGACY_VAULT_ADDRESS || '';
}

export function apiBase() {
  return import.meta.env.VITE_API_BASE || 'http://localhost:8000';
}

export function normalizeHex32(hex) {
  const clean = String(hex || '').replace(/^0x/, '');
  if (!/^[0-9a-fA-F]{64}$/.test(clean)) throw new Error('Expected a 32-byte hex value.');
  return `0x${clean}`;
}
