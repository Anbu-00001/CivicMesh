import 'dotenv/config';
import crypto from 'node:crypto';
import express from 'express';
import cors from 'cors';
import multer from 'multer';
import sharesRouter from './routes/shares.js';
import heartbeatRouter from './routes/heartbeat.js';
import { getVaultContract, getVaultContractReadOnly } from './lib/contracts.js';
import { ensureLocalStore, getMemory, listMemories, localUploadDir, readMemoryBlob, saveMemory } from './lib/store.js';
import { startHeartbeatMonitor } from './jobs/heartbeatMonitor.js';

await ensureLocalStore();

const app = express();
const upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: 100 * 1024 * 1024 } });
const port = Number(process.env.PORT || 8000);

app.use(cors({ origin: process.env.CORS_ORIGIN || true }));
app.use(express.json({ limit: '2mb' }));
app.use('/uploads', express.static(localUploadDir()));
app.use('/api', sharesRouter);
app.use('/api', heartbeatRouter);

app.post('/api/memories', upload.single('file'), async (req, res, next) => {
  try {
    if (!req.file) return res.status(400).json({ error: 'file is required' });
    const meta = JSON.parse(req.body.meta || '{}');
    const id = crypto.randomUUID();
    const row = await saveMemory(
      {
        id,
        owner: req.body.owner || null,
        ownerDid: req.body.ownerDid || null,
        meta,
        createdAt: new Date().toISOString()
      },
      req.file.buffer
    );
    res.json({ ok: true, id: row.id, path: row.path });
  } catch (err) {
    next(err);
  }
});

app.get('/api/memories', async (req, res, next) => {
  try {
    res.json(await listMemories(req.query.heir));
  } catch (err) {
    next(err);
  }
});

app.get('/api/memories/:id/blob', async (req, res, next) => {
  try {
    const memory = await getMemory(req.params.id);
    if (!memory) return res.status(404).json({ error: 'Memory not found' });
    const blob = await readMemoryBlob(memory);
    res.setHeader('Content-Type', 'application/octet-stream');
    res.send(blob);
  } catch (err) {
    next(err);
  }
});

app.get('/api/verify-heir', async (req, res) => {
  const { address } = req.query;
  if (!address) return res.json({ isHeir: false });

  try {
    const contract = getVaultContractReadOnly();
    const isHeir = await contract.heirs(address);
    res.json({ isHeir: Boolean(isHeir), address });
  } catch (err) {
    res.json({ isHeir: false, address, error: err.message });
  }
});

app.get('/api/can-access', async (req, res, next) => {
  try {
    const { address } = req.query;
    if (!address) return res.status(400).json({ error: 'address is required' });
    const contract = getVaultContractReadOnly();
    const canAccess = await contract.canAccess(address);
    res.json({ address, canAccess: Boolean(canAccess) });
  } catch (err) {
    next(err);
  }
});

app.post('/api/notify-death', async (_req, res, next) => {
  try {
    const contract = getVaultContract();
    const tx = await contract.markDeceased();
    await tx.wait();
    res.json({ ok: true, txHash: tx.hash });
  } catch (err) {
    next(err);
  }
});

app.use((err, _req, res, _next) => {
  console.error(err);
  res.status(500).json({ error: err.message || 'Internal server error' });
});

if (process.env.ENABLE_HEARTBEAT_MONITOR !== 'false') {
  startHeartbeatMonitor();
}

app.listen(port, () => {
  console.log(`MemCap backend listening on http://localhost:${port}`);
});
