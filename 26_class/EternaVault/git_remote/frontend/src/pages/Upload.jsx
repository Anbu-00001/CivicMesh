import { useEffect, useMemo, useState } from 'react';
import { CloudUpload, Plus, ShieldCheck } from 'lucide-react';
import GlassCard from '../components/GlassCard.jsx';
import HeartbeatWidget from '../components/HeartbeatWidget.jsx';
import ShareSetup from '../components/ShareSetup.jsx';
import { useWallet } from '../context/WalletContext.jsx';
import { encryptArrayBuffer, randomVaultKey } from '../utils/crypto.js';
import { apiBase } from '../utils/vaultContract.js';

const EMPTY_HEIR = '';

export default function Upload() {
  const { walletAddress, connectWallet } = useWallet();
  const [file, setFile] = useState(null);
  const [vaultKey, setVaultKey] = useState('');
  const [heirs, setHeirs] = useState([EMPTY_HEIR, EMPTY_HEIR, EMPTY_HEIR]);
  const [threshold, setThreshold] = useState(2);
  const [ownerDid, setOwnerDid] = useState('');
  const [status, setStatus] = useState('');
  const [heartbeat, setHeartbeat] = useState(null);
  const [busy, setBusy] = useState(false);

  const cleanHeirs = useMemo(() => heirs.map((heir) => heir.trim()).filter(Boolean), [heirs]);

  useEffect(() => {
    setOwnerDid(walletAddress ? `did:pkh:eip155:1990:${walletAddress.toLowerCase()}` : '');
  }, [walletAddress]);

  async function loadHeartbeat() {
    const res = await fetch(`${apiBase()}/api/heartbeat`);
    if (res.ok) setHeartbeat(await res.json());
  }

  useEffect(() => {
    loadHeartbeat().catch(() => {});
  }, []);

  function updateHeir(index, value) {
    setHeirs((current) => current.map((heir, i) => (i === index ? value : heir)));
  }

  async function uploadEncryptedMemory() {
    setBusy(true);
    try {
      if (!walletAddress) await connectWallet();
      if (!file) throw new Error('Choose a file first.');
      if (!vaultKey) throw new Error('Set or generate a vault key first.');

      const buffer = await file.arrayBuffer();
      const { encryptedBuffer, cryptoPayload } = await encryptArrayBuffer(buffer, vaultKey);
      const form = new FormData();
      form.append('file', new Blob([encryptedBuffer], { type: 'application/octet-stream' }), `${file.name}.enc`);
      form.append('owner', walletAddress);
      form.append('ownerDid', ownerDid);
      form.append('meta', JSON.stringify({
        originalName: file.name,
        originalType: file.type || 'application/octet-stream',
        size: file.size,
        heirs: cleanHeirs,
        threshold,
        cryptoPayload
      }));

      const res = await fetch(`${apiBase()}/api/memories`, { method: 'POST', body: form });
      if (!res.ok) throw new Error(await res.text());
      const data = await res.json();
      setStatus(`Encrypted upload stored: ${data.id || data.path}`);
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="grid gap-5 lg:grid-cols-[1.2fr_0.8fr]">
      <GlassCard>
        <div className="flex items-center gap-2 text-[#C4A87C]">
          <CloudUpload size={20} />
          <h2 className="text-xl font-semibold">Owner Upload</h2>
        </div>

        <div className="mt-5 grid gap-4">
          <input type="file" onChange={(event) => setFile(event.target.files?.[0] || null)} className="rounded-md border border-white/10 p-3 text-sm" />
          <div className="grid gap-2 md:grid-cols-[1fr_auto]">
            <input
              value={vaultKey}
              onChange={(event) => setVaultKey(event.target.value)}
              placeholder="Vault passphrase or generated key"
              className="rounded-md border border-white/10 bg-black/20 px-3 py-2 text-sm"
            />
            <button type="button" onClick={() => setVaultKey(randomVaultKey())} className="rounded-md border border-white/10 px-4 py-2 text-sm">
              Generate key
            </button>
          </div>

          <div className="grid gap-2">
            {heirs.map((heir, index) => (
              <input
                key={index}
                value={heir}
                onChange={(event) => updateHeir(index, event.target.value)}
                placeholder={`Heir ${index + 1} wallet address`}
                className="rounded-md border border-white/10 bg-black/20 px-3 py-2 text-sm"
              />
            ))}
            <button type="button" onClick={() => setHeirs((current) => [...current, EMPTY_HEIR])} className="inline-flex w-fit items-center gap-2 rounded-md border border-white/10 px-3 py-2 text-sm">
              <Plus size={16} />
              Add heir
            </button>
          </div>

          <label className="text-sm text-[#9aa0ab]">
            Share threshold
            <input
              type="number"
              min="1"
              max={Math.max(1, cleanHeirs.length)}
              value={threshold}
              onChange={(event) => setThreshold(event.target.value)}
              className="mt-1 w-full rounded-md border border-white/10 bg-black/20 px-3 py-2 text-sm text-slate-100"
            />
          </label>

          <button type="button" onClick={uploadEncryptedMemory} disabled={busy} className="inline-flex w-fit items-center gap-2 rounded-md bg-[#C4A87C] px-4 py-2 font-semibold text-black disabled:opacity-50">
            <ShieldCheck size={16} />
            {busy ? 'Encrypting...' : 'Encrypt and upload'}
          </button>
        </div>
      </GlassCard>

      <div className="grid gap-5">
        <HeartbeatWidget heartbeat={heartbeat} onStatus={setStatus} onRenewed={loadHeartbeat} />
        <ShareSetup vaultKey={vaultKey} ownerDid={ownerDid} heirs={cleanHeirs} threshold={threshold} onStatus={setStatus} />
        {status && <p className="rounded-lg border border-white/10 bg-white/[0.03] p-3 text-sm text-emerald-200">{status}</p>}
      </div>
    </div>
  );
}
