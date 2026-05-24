# MemCap

MemCap is a QIE Mainnet digital legacy vault prototype with client-side AES-GCM encryption, Shamir threshold key recovery, rolling heartbeat access escalation, and per-heir forensic image watermarking.

## Environment

Frontend:

```bash
VITE_API_BASE=http://localhost:8000
VITE_QIE_RPC_URL=https://rpc-mainnet.qiblockchain.online
VITE_LEGACY_VAULT_ADDRESS=0x...
```

Backend:

```bash
PORT=8000
QIE_RPC_URL=https://rpc-mainnet.qiblockchain.online
LEGACY_VAULT_ADDRESS=0x...
VAULT_OWNER_PRIVATE_KEY=0x...
SUPABASE_URL=https://...
SUPABASE_SERVICE_ROLE_KEY=...
SUPABASE_BUCKET=memories
```

If Supabase variables are omitted, the backend stores encrypted blobs and metadata under `backend/data` and `backend/uploads` for local development.

## Run

```bash
cd backend && npm install && npm run dev
cd frontend && npm install && npm run dev
```

Apply `supabase/schema.sql` when using Supabase.
