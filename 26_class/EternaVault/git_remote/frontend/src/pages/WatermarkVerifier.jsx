import { useState } from 'react';
import { Fingerprint, SearchCheck } from 'lucide-react';
import GlassCard from '../components/GlassCard.jsx';
import { apiBase } from '../utils/vaultContract.js';
import { extractHeirWatermark } from '../utils/watermark.js';

export default function WatermarkVerifier() {
  const [result, setResult] = useState('');
  const [isHeir, setIsHeir] = useState(null);
  const [status, setStatus] = useState('');

  async function handleFileUpload(event) {
    const file = event.target.files?.[0];
    if (!file) return;
    setStatus('Extracting DCT watermark...');
    const extractedAddress = await extractHeirWatermark(file);
    setResult(extractedAddress);

    const res = await fetch(`${apiBase()}/api/verify-heir?address=${encodeURIComponent(extractedAddress)}`);
    const data = await res.json();
    setIsHeir(Boolean(data.isHeir));
    setStatus('Watermark extraction completed.');
  }

  return (
    <GlassCard>
      <div className="flex items-center gap-2 text-[#C4A87C]">
        <Fingerprint size={20} />
        <h2 className="text-xl font-semibold">Watermark Forensic Verifier</h2>
      </div>
      <div className="mt-5 grid gap-4">
        <input type="file" accept="image/*" onChange={handleFileUpload} className="rounded-md border border-white/10 p-3 text-sm" />
        {result && (
          <div className="rounded-lg border border-white/10 p-4">
            <div className="flex items-center gap-2 text-emerald-200">
              <SearchCheck size={18} />
              <span className="font-semibold">Extracted address</span>
            </div>
            <code className="mt-2 block break-all text-sm">{result}</code>
            <p className="mt-2 text-sm text-[#9aa0ab]">
              On-chain status: {isHeir ? 'Registered heir' : 'Not registered as an heir'}
            </p>
          </div>
        )}
        {status && <p className="text-sm text-emerald-200">{status}</p>}
      </div>
    </GlassCard>
  );
}
