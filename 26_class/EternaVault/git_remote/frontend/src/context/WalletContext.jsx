import React, { createContext, useContext, useMemo, useState } from 'react';

export const QIE_MAINNET = {
  chainId: '0x7c6',
  chainName: 'QIE Mainnet',
  nativeCurrency: { name: 'QIE', symbol: 'QIE', decimals: 18 },
  rpcUrls: [import.meta.env.VITE_QIE_RPC_URL || 'https://rpc-mainnet.qiblockchain.online'],
  blockExplorerUrls: [import.meta.env.VITE_QIE_EXPLORER_URL || 'https://mainnet.qiblockchain.online']
};

const WalletContext = createContext(null);

export function WalletProvider({ children }) {
  const [walletAddress, setWalletAddress] = useState('');
  const [chainId, setChainId] = useState('');
  const [error, setError] = useState('');

  async function connectWallet() {
    setError('');
    if (!window.ethereum) {
      setError('MetaMask is required for MemCap wallet operations.');
      return null;
    }

    const accounts = await window.ethereum.request({ method: 'eth_requestAccounts' });
    const currentChain = await window.ethereum.request({ method: 'eth_chainId' });
    setWalletAddress(accounts[0] || '');
    setChainId(currentChain);
    return accounts[0] || null;
  }

  async function ensureQieMainnet() {
    if (!window.ethereum) return;
    const currentChain = await window.ethereum.request({ method: 'eth_chainId' });
    if (currentChain === QIE_MAINNET.chainId) {
      setChainId(currentChain);
      return;
    }

    try {
      await window.ethereum.request({
        method: 'wallet_switchEthereumChain',
        params: [{ chainId: QIE_MAINNET.chainId }]
      });
    } catch (err) {
      if (err.code === 4902) {
        await window.ethereum.request({
          method: 'wallet_addEthereumChain',
          params: [QIE_MAINNET]
        });
      } else {
        throw err;
      }
    }
    setChainId(QIE_MAINNET.chainId);
  }

  const value = useMemo(
    () => ({
      walletAddress,
      chainId,
      error,
      connectWallet,
      ensureQieMainnet
    }),
    [walletAddress, chainId, error]
  );

  return <WalletContext.Provider value={value}>{children}</WalletContext.Provider>;
}

export function useWallet() {
  const ctx = useContext(WalletContext);
  if (!ctx) throw new Error('useWallet must be used inside WalletProvider');
  return ctx;
}
