import { split, combine } from 'shamir-secret-sharing';
import { fromBase64, toBase64 } from './crypto.js';

export async function splitVaultKey(vaultKey, heirAddresses, threshold) {
  if (!vaultKey) throw new Error('Vault key is required.');
  if (!Array.isArray(heirAddresses) || heirAddresses.length === 0) {
    throw new Error('At least one heir address is required.');
  }
  if (threshold < 1 || threshold > heirAddresses.length) {
    throw new Error('Threshold must be between 1 and the number of heirs.');
  }

  const secret = new TextEncoder().encode(vaultKey);
  const shares = await split(secret, { shares: heirAddresses.length, threshold });
  return shares.map((share, index) => ({
    heir: heirAddresses[index],
    share: toBase64(share)
  }));
}

export async function combineVaultKeyShares(base64Shares) {
  const usableShares = base64Shares.filter(Boolean).map((share) => fromBase64(share.trim()));
  if (usableShares.length === 0) throw new Error('At least one decrypted share is required.');
  const reconstructed = await combine(usableShares);
  return new TextDecoder().decode(reconstructed);
}
