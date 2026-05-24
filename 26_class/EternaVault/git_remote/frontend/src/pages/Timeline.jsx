import { useEffect, useState } from 'react';
import GlassCard from '../components/GlassCard.jsx';
import { apiBase } from '../utils/vaultContract.js';

export default function Timeline() {
  const [memories, setMemories] = useState([]);

  useEffect(() => {
    fetch(`${apiBase()}/api/memories`)
      .then((res) => (res.ok ? res.json() : []))
      .then(setMemories)
      .catch(() => setMemories([]));
  }, []);

  return (
    <GlassCard>
      <h2 className="text-xl font-semibold text-[#C4A87C]">Encrypted Timeline</h2>
      <div className="mt-4 grid gap-3">
        {memories.map((memory) => (
          <article key={memory.id} className="rounded-md border border-white/10 p-3">
            <h3 className="font-semibold">{memory.meta?.originalName || memory.id}</h3>
            <p className="text-xs text-[#8A8F99]">{memory.created_at || memory.createdAt || 'Stored memory'}</p>
          </article>
        ))}
        {memories.length === 0 && <p className="text-sm text-[#8A8F99]">No encrypted memories returned by the backend.</p>}
      </div>
    </GlassCard>
  );
}
