import { Wallet } from 'lucide-react';
import { useWallet } from '../context/WalletContext.jsx';

export default function QuirkyWidget() {
  const { walletAddress, connectWallet } = useWallet();
  const label = walletAddress ? `${walletAddress.slice(0, 6)}...${walletAddress.slice(-4)}` : 'Connect';

  return (
    <button
      type="button"
      onClick={connectWallet}
      className="inline-flex h-9 items-center gap-2 rounded-md border border-white/10 px-3 text-sm text-slate-100 transition hover:border-[#C4A87C]"
      title="Connect wallet"
    >
      <Wallet size={16} />
      <span>{label}</span>
    </button>
  );
}
