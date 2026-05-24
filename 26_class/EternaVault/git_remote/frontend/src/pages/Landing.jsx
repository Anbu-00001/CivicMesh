import { Link } from 'react-router-dom';
import { Fingerprint, HeartPulse, KeyRound } from 'lucide-react';

export default function Landing() {
  const features = [
    { icon: HeartPulse, title: 'Trustless heartbeat', body: 'Rolling commit-reveal liveness unlocks heirs after owner silence.' },
    { icon: KeyRound, title: 'Threshold recovery', body: 'Vault keys split into encrypted t-of-n Shamir shares for registered heirs.' },
    { icon: Fingerprint, title: 'Forensic downloads', body: 'Image downloads receive invisible heir attribution watermarks.' }
  ];

  return (
    <div className="grid gap-5 md:grid-cols-3">
      {features.map(({ icon: Icon, title, body }) => (
        <article key={title} className="rounded-lg border border-white/10 bg-white/[0.03] p-4">
          <Icon className="text-[#C4A87C]" size={22} />
          <h2 className="mt-3 text-lg font-semibold">{title}</h2>
          <p className="mt-2 text-sm text-[#9aa0ab]">{body}</p>
        </article>
      ))}
      <Link to="/upload" className="md:col-span-3 rounded-lg border border-[#C4A87C]/50 p-4 text-center font-semibold text-[#C4A87C]">
        Open owner vault controls
      </Link>
    </div>
  );
}
