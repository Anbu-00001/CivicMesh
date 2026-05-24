import { useEffect, useMemo, useState } from 'react';
import { Activity, RotateCw } from 'lucide-react';
import { apiBase, vaultAddress } from '../utils/vaultContract.js';
import { heartbeatCommitment, randomSecretHex, readHeartbeatSecret, rememberHeartbeatSecret } from '../utils/heartbeat.js';

const DAY = 86400000;

export default function HeartbeatWidget({ heartbeat, onStatus, onRenewed }) {
  const [timeLeft, setTimeLeft] = useState(0);
  const [prevSecret, setPrevSecret] = useState('');
  const [busy, setBusy] = useState(false);
  const vault = vaultAddress();

  const epoch = Number(heartbeat?.heartbeatEpoch || 0);
  const lastHeartbeat = Number(heartbeat?.lastHeartbeat || 0);
  const silenceThreshold = Number(heartbeat?.silenceThreshold || 0);

  useEffect(() => {
    setPrevSecret(readHeartbeatSecret(vault, epoch));
  }, [vault, epoch]);

  useEffect(() => {
    if (!lastHeartbeat || !silenceThreshold) return;
    const deadline = (lastHeartbeat + silenceThreshold) * 1000;
    const tick = () => setTimeLeft(Math.max(0, deadline - Date.now()));
    tick();
    const interval = setInterval(tick, 1000);
    return () => clearInterval(interval);
  }, [lastHeartbeat, silenceThreshold]);

  const days = Math.floor(timeLeft / DAY);
  const urgency = days < 7 ? 'text-red-300' : days < 30 ? 'text-yellow-200' : 'text-emerald-300';
  const initialized = Boolean(lastHeartbeat && silenceThreshold && epoch);

  const helper = useMemo(() => {
    if (!initialized) return 'Initialize a rolling commitment before relying on automatic heir access.';
    return 'Renew before the deadline to keep the vault locked for heirs.';
  }, [initialized]);

  async function initHeartbeat() {
    setBusy(true);
    try {
      const firstEpoch = 1;
      const secret = randomSecretHex();
      const commitment = heartbeatCommitment(secret, firstEpoch);
      const res = await fetch(`${apiBase()}/api/init-heartbeat`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ commitment, silenceThresholdDays: 90 })
      });
      if (!res.ok) throw new Error(await res.text());
      rememberHeartbeatSecret(vault, firstEpoch, secret);
      setPrevSecret(secret);
      onStatus?.('Heartbeat initialized with a 90-day silence threshold.');
      onRenewed?.();
    } finally {
      setBusy(false);
    }
  }

  async function renewHeartbeat() {
    setBusy(true);
    try {
      const secret = prevSecret || readHeartbeatSecret(vault, epoch);
      if (!secret) throw new Error('Previous heartbeat secret is required.');
      const nextSecret = randomSecretHex();
      const nextCommitment = heartbeatCommitment(nextSecret, epoch + 1);
      const res = await fetch(`${apiBase()}/api/renew-heartbeat`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ prevSecret: secret, prevEpoch: epoch, newCommitment: nextCommitment })
      });
      if (!res.ok) throw new Error(await res.text());
      rememberHeartbeatSecret(vault, epoch + 1, nextSecret);
      setPrevSecret(nextSecret);
      onStatus?.('Heartbeat renewed and next secret stored locally.');
      onRenewed?.();
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="rounded-lg border border-white/10 p-4">
      <div className="flex items-center gap-2 text-sm font-semibold text-[#C4A87C]">
        <Activity size={16} />
        Vault Heartbeat
      </div>
      <p className={`mt-2 font-mono text-2xl font-bold ${urgency}`}>{initialized ? `${days}d remaining` : 'Not initialized'}</p>
      <p className="mt-1 text-xs text-[#8A8F99]">{helper}</p>
      {initialized && (
        <input
          value={prevSecret}
          onChange={(event) => setPrevSecret(event.target.value)}
          placeholder="Previous 32-byte secret"
          className="mt-3 w-full rounded-md border border-white/10 bg-black/20 px-3 py-2 text-xs"
        />
      )}
      <button
        type="button"
        onClick={initialized ? renewHeartbeat : initHeartbeat}
        disabled={busy}
        className="mt-3 inline-flex items-center gap-2 rounded-md bg-emerald-400 px-4 py-2 text-sm font-semibold text-slate-950 disabled:opacity-50"
      >
        <RotateCw size={16} />
        {busy ? 'Working...' : initialized ? 'Renew heartbeat' : 'Initialize heartbeat'}
      </button>
    </div>
  );
}
