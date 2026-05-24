import { useState } from 'react';
import { KeyRound, Send } from 'lucide-react';
import { apiBase } from '../utils/vaultContract.js';
import { splitVaultKey } from '../utils/shamirKey.js';
import { encryptShareForHeir } from '../utils/ethEncryption.js';

export default function ShareSetup({ vaultKey, ownerDid, heirs, threshold, onStatus }) {
  const [busy, setBusy] = useState(false);

  async function splitAndDepositKey() {
    setBusy(true);
    try {
      const cleanHeirs = heirs.map((heir) => heir.trim()).filter(Boolean);
      const shares = await splitVaultKey(vaultKey, cleanHeirs, Number(threshold));
      onStatus?.(`Generated ${shares.length} threshold shares. Requesting heir encryption keys...`);

      for (const share of shares) {
        const encrypted = await encryptShareForHeir(share.share, share.heir);
        const res = await fetch(`${apiBase()}/api/deposit-share`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            ownerDid,
            heir: share.heir,
            encryptedShare: encrypted,
            threshold: Number(threshold)
          })
        });
        if (!res.ok) throw new Error(await res.text());
      }
      onStatus?.('Encrypted Shamir shares deposited for all heirs.');
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="rounded-lg border border-white/10 p-4">
      <div className="flex items-center gap-2 text-sm font-semibold text-[#C4A87C]">
        <KeyRound size={16} />
        Threshold social recovery
      </div>
      <button
        type="button"
        onClick={splitAndDepositKey}
        disabled={busy || !vaultKey}
        className="mt-3 inline-flex items-center gap-2 rounded-md bg-[#C4A87C] px-4 py-2 text-sm font-semibold text-black disabled:cursor-not-allowed disabled:opacity-50"
      >
        <Send size={16} />
        {busy ? 'Depositing shares...' : 'Split and deposit shares'}
      </button>
    </div>
  );
}
