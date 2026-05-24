import React from 'react';
import { Routes, Route, Link } from 'react-router-dom';
import { Analytics } from '@vercel/analytics/react';
import Landing from './pages/Landing.jsx';
import Upload from './pages/Upload.jsx';
import Timeline from './pages/Timeline.jsx';
import HeirDashboard from './pages/HeirDashboard.jsx';
import ValidatorDashboard from './pages/ValidatorDashboard.jsx';
import TokenizationInfo from './pages/TokenizationInfo.jsx';
import WatermarkVerifier from './pages/WatermarkVerifier.jsx';
import GlassCard from './components/GlassCard.jsx';
import NeonBlob from './components/NeonBlob.jsx';
import QuirkyWidget from './components/QuirkyWidget.jsx';

function App() {
  return (
    <div className="min-h-screen flex flex-col bg-[#0d0e11] text-slate-100 font-['Inter']">
      <header className="border-b border-white/5 bg-[#0d0e11] py-3">
        <div className="max-w-5xl mx-auto px-4 flex items-center justify-between gap-4">
          <div className="flex items-center gap-4">
            <Link to="/" className="text-2xl text-[#C4A87C] font-bold">
              MemCap
            </Link>
            <nav className="hidden md:flex gap-4 text-sm text-[#8A8F99]">
              <Link to="/" className="transition">Home</Link>
              <Link to="/upload" className="transition">Upload</Link>
              <Link to="/timeline" className="transition">Timeline</Link>
              <Link to="/heir" className="transition">Heir</Link>
              <Link to="/validator" className="transition">Validator</Link>
              <Link to="/verify-watermark" className="transition">Verify</Link>
              <Link to="/tokenization" className="transition">Tokenization</Link>
            </nav>
          </div>
          <div className="flex items-center gap-3">
            <QuirkyWidget />
          </div>
        </div>
      </header>

      <div className="hero-wrap">
        <NeonBlob className="-left-48 -top-40" />
        <NeonBlob className="-right-40 bottom-20" />
        <main className="hero-inner flex-1 max-w-5xl mx-auto w-full px-4 py-10">
          <GlassCard className="mb-8">
            <div className="flex flex-col md:flex-row md:items-center md:justify-between gap-4">
              <div>
                <h1 className="text-3xl md:text-4xl font-bold" style={{fontFamily: 'Playfair Display'}}>
                  MemCap - Your encrypted heirloom vault
                </h1>
                <p className="mt-2 text-[#9aa0ab]">Securely store and release files on-chain with elegant UX and modern cryptography.</p>
              </div>
              <div className="flex items-center gap-3">
                <Link to="/upload" className="px-4 py-2 bg-[#C4A87C] text-black font-semibold rounded-lg transition">Upload File</Link>
                <Link to="/timeline" className="px-4 py-2 border border-white/10 rounded-lg text-sm">View Timeline</Link>
              </div>
            </div>
          </GlassCard>

          <Routes>
            <Route path="/" element={<Landing />} />
            <Route path="/upload" element={<Upload />} />
            <Route path="/timeline" element={<Timeline />} />
            <Route path="/heir" element={<HeirDashboard />} />
            <Route path="/validator" element={<ValidatorDashboard />} />
            <Route path="/verify-watermark" element={<WatermarkVerifier />} />
            <Route path="/tokenization" element={<TokenizationInfo />} />
          </Routes>
        </main>
      </div>

      <footer className="border-t border-white/5 text-xs text-[#8A8F99] py-4 text-center">
        Prototype for QIE Hackathon - Not legal advice or production-ready.
      </footer>
      <Analytics />
    </div>
  );
}

export default App;
