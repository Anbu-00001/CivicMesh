import { useEffect, useState } from 'react';
import { Download, KeyRound, ShieldCheck } from 'lucide-react';
import GlassCard from '../components/GlassCard.jsx';
import { useWallet } from '../context/WalletContext.jsx';
import { apiBase } from '../utils/vaultContract.js';
import { decryptArrayBuffer } from '../utils/crypto.js';
import { decryptShareWithWallet, registerMyEncryptionPublicKey } from '../utils/ethEncryption.js';
import { combineVaultKeyShares } from '../utils/shamirKey.js';
import { embedHeirWatermark } from '../utils/watermark.js';

export default function HeirDashboard() {
  const { walletAddress, connectWallet } = useWallet();
  const [memories, setMemories] = useState([]);
  const [extraShares, setExtraShares] = useState('');
  const [vaultKey, setVaultKey] = useState('');
  const [status, setStatus] = useState('');
  const [busyId, setBusyId] = useState('');

  async function loadMemories() {
    if (!walletAddress) return;
    const res = await fetch(`${apiBase()}/api/memories?heir=${walletAddress}`);
    if (res.ok) setMemories(await res.json());
  }

  useEffect(() => {
    loadMemories().catch(() => {});
  }, [walletAddress]);

  async function reconstructVaultKey() {
    const address = walletAddress || (await connectWallet());
    if (!address) return;

    const res = await fetch(`${apiBase()}/api/my-share?heir=${address}`);
    if (!res.ok) throw new Error(await res.text());
    const { encryptedShare } = await res.json();
    const myShare = await decryptShareWithWallet(encryptedShare, address);
    const collected = extraShares.split(/\s+/).map((share) => share.trim()).filter(Boolean);
    const reconstructed = await combineVaultKeyShares([myShare, ...collected]);
    setVaultKey(reconstructed);
    setStatus('Vault key reconstructed in this browser.');
  }

  async function registerEncryptionKey() {
    const address = walletAddress || (await connectWallet());
    if (!address) return;
    await registerMyEncryptionPublicKey(address);
    setStatus('Encryption public key registered for owner-side Shamir share encryption.');
  }

  async function decryptMemory(entry) {
    const address = walletAddress || (await connectWallet());
    if (!vaultKey) throw new Error('Reconstruct or enter the vault key first.');

    setBusyId(entry.id);
    try {
      const access = await fetch(`${apiBase()}/api/can-access?address=${address}`);
      if (access.ok) {
        const data = await access.json();
        if (!data.canAccess) throw new Error('On-chain access has not been granted yet.');
      }

      setStatus('Downloading encrypted memory...');
      const encryptedRes = await fetch(entry.url || `${apiBase()}/api/memories/${entry.id}/blob`);
      if (!encryptedRes.ok) throw new Error(await encryptedRes.text());
      const encryptedBuffer = await encryptedRes.arrayBuffer();

      setStatus('Decrypting with AES-GCM...');
      const meta = entry.meta || {};
      const decryptedBlob = await decryptArrayBuffer(
        encryptedBuffer,
        vaultKey,
        meta.cryptoPayload,
        meta.originalType || 'application/octet-stream'
      );

      let finalBlob = decryptedBlob;
      if ((decryptedBlob.type || '').startsWith('image/') && address) {
        setStatus('Applying invisible heir attribution watermark...');
        finalBlob = await embedHeirWatermark(decryptedBlob, address);
      }

      const url = URL.createObjectURL(finalBlob);
      const a = document.createElement('a');
      a.href = url;
      a.download = meta.originalName || 'decrypted-file';
      document.body.appendChild(a);
      a.click();
      a.remove();
      URL.revokeObjectURL(url);
      setStatus('Decrypted download completed.');
    } finally {
      setBusyId('');
    }
  }

  return (
    <div className="grid gap-5">
      <GlassCard>
        <div className="flex items-center gap-2 text-[#C4A87C]">
          <KeyRound size={20} />
          <h2 className="text-xl font-semibold">Heir Access</h2>
        </div>
        <div className="mt-4 grid gap-3">
          <textarea
            value={extraShares}
            onChange={(event) => setExtraShares(event.target.value)}
            placeholder="Paste decrypted base64 shares from cooperating heirs, separated by whitespace"
            className="min-h-24 rounded-md border border-white/10 bg-black/20 p-3 text-sm"
          />
          <div className="grid gap-2 md:grid-cols-[1fr_auto]">
            <input
              value={vaultKey}
              onChange={(event) => setVaultKey(event.target.value)}
              placeholder="Reconstructed vault key"
              className="rounded-md border border-white/10 bg-black/20 px-3 py-2 text-sm"
            />
            <button type="button" onClick={reconstructVaultKey} className="inline-flex items-center gap-2 rounded-md bg-emerald-400 px-4 py-2 text-sm font-semibold text-slate-950">
              <ShieldCheck size={16} />
              Reconstruct key
            </button>
          </div>
          <button type="button" onClick={registerEncryptionKey} className="inline-flex w-fit items-center gap-2 rounded-md border border-white/10 px-3 py-2 text-sm">
            <KeyRound size={16} />
            Register encryption key
          </button>
        </div>
      </GlassCard>

      <div className="grid gap-3">
        {memories.map((entry) => (
          <article key={entry.id} className="flex items-center justify-between gap-4 rounded-lg border border-white/10 bg-white/[0.03] p-4">
            <div>
              <h3 className="font-semibold">{entry.meta?.originalName || entry.id}</h3>
              <p className="text-xs text-[#8A8F99]">{entry.created_at || entry.createdAt || 'Encrypted memory'}</p>
            </div>
            <button
              type="button"
              onClick={() => decryptMemory(entry)}
              disabled={busyId === entry.id}
              className="inline-flex items-center gap-2 rounded-md border border-white/10 px-3 py-2 text-sm disabled:opacity-50"
            >
              <Download size={16} />
              {busyId === entry.id ? 'Working...' : 'Decrypt'}
            </button>
          </article>
        ))}
        {memories.length === 0 && <p className="text-sm text-[#8A8F99]">Connect as an heir to load available encrypted memories.</p>}
      </div>

      {status && <p className="rounded-lg border border-white/10 bg-white/[0.03] p-3 text-sm text-emerald-200">{status}</p>}
    </div>
  );
}
