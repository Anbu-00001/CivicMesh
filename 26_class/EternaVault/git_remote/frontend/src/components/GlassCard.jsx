export default function GlassCard({ className = '', children }) {
  return (
    <section className={`rounded-lg border border-white/10 bg-white/[0.04] p-5 shadow-xl ${className}`}>
      {children}
    </section>
  );
}
