export default function NeonBlob({ className = '' }) {
  return <div className={`pointer-events-none absolute h-px w-px opacity-0 ${className}`} aria-hidden="true" />;
}
