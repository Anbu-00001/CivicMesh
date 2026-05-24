import { Contract, JsonRpcProvider, Wallet, toUtf8Bytes, toUtf8String } from 'ethers';

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
  'function markDeceased()',
  'function setShareThreshold(uint256 threshold)',
  'function depositEncryptedShare(address heir,bytes encryptedShare)',
  'function initHeartbeat(bytes32 commitment,uint256 thresholdSeconds)',
  'function renewHeartbeat(bytes32 prevSecret,uint256 prevEpoch,bytes32 newCommitment)',
  'function escalateAccess()'
];

export function getProvider() {
  const rpcUrl = process.env.QIE_RPC_URL || process.env.RPC_URL;
  if (!rpcUrl) throw new Error('QIE_RPC_URL or RPC_URL is required.');
  return new JsonRpcProvider(rpcUrl, 1990);
}

export function getVaultAddress() {
  const address = process.env.LEGACY_VAULT_ADDRESS || process.env.VAULT_ADDRESS;
  if (!address) throw new Error('LEGACY_VAULT_ADDRESS or VAULT_ADDRESS is required.');
  return address;
}

export function getVaultContractReadOnly() {
  return new Contract(getVaultAddress(), LEGACY_VAULT_ABI, getProvider());
}

export function getVaultContract() {
  const privateKey = process.env.VAULT_OWNER_PRIVATE_KEY || process.env.PRIVATE_KEY;
  if (!privateKey) throw new Error('VAULT_OWNER_PRIVATE_KEY or PRIVATE_KEY is required for write routes.');
  const signer = new Wallet(privateKey, getProvider());
  return new Contract(getVaultAddress(), LEGACY_VAULT_ABI, signer);
}

export function encryptedShareToBytes(encryptedShare) {
  return toUtf8Bytes(typeof encryptedShare === 'string' ? encryptedShare : JSON.stringify(encryptedShare));
}

export function bytesToEncryptedShare(bytes) {
  return toUtf8String(bytes);
}
