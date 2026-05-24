import { Buffer } from 'buffer';
import { encrypt } from '@metamask/eth-sig-util';
import { apiBase } from './vaultContract.js';

if (!window.Buffer) window.Buffer = Buffer;

export async function getEncryptionPublicKey(address) {
  if (!window.ethereum) throw new Error('MetaMask is required.');
  return window.ethereum.request({
    method: 'eth_getEncryptionPublicKey',
    params: [address]
  });
}

export async function encryptShareForHeir(base64Share, heirAddress) {
  const publicKey = await getRegisteredOrWalletPublicKey(heirAddress);
  return encrypt({
    publicKey,
    data: base64Share,
    version: 'x25519-xsalsa20-poly1305'
  });
}

export async function registerMyEncryptionPublicKey(address) {
  const encryptionPublicKey = await getEncryptionPublicKey(address);
  const res = await fetch(`${apiBase()}/api/register-encryption-key`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ heir: address, encryptionPublicKey })
  });
  if (!res.ok) throw new Error(await res.text());
  return encryptionPublicKey;
}

async function getRegisteredOrWalletPublicKey(heirAddress) {
  const res = await fetch(`${apiBase()}/api/encryption-key?heir=${encodeURIComponent(heirAddress)}`);
  if (res.ok) {
    const data = await res.json();
    return data.encryptionPublicKey;
  }
  return getEncryptionPublicKey(heirAddress);
}

export async function decryptShareWithWallet(encryptedShare, heirAddress) {
  if (!window.ethereum) throw new Error('MetaMask is required.');
  const payload = typeof encryptedShare === 'string' ? encryptedShare : JSON.stringify(encryptedShare);
  return window.ethereum.request({
    method: 'eth_decrypt',
    params: [payload, heirAddress]
  });
}
