import { Router } from 'express';
import { getVaultContract, getVaultContractReadOnly } from '../lib/contracts.js';

const router = Router();

router.post('/init-heartbeat', async (req, res, next) => {
  try {
    const { commitment, silenceThresholdDays } = req.body;
    if (!commitment || !silenceThresholdDays) {
      return res.status(400).json({ error: 'commitment and silenceThresholdDays are required' });
    }

    const thresholdSeconds = BigInt(Math.floor(Number(silenceThresholdDays) * 86400));
    const contract = getVaultContract();
    const tx = await contract.initHeartbeat(commitment, thresholdSeconds);
    await tx.wait();
    res.json({ ok: true, txHash: tx.hash });
  } catch (err) {
    next(err);
  }
});

router.post('/renew-heartbeat', async (req, res, next) => {
  try {
    const { prevSecret, prevEpoch, newCommitment } = req.body;
    if (!prevSecret || !prevEpoch || !newCommitment) {
      return res.status(400).json({ error: 'prevSecret, prevEpoch, and newCommitment are required' });
    }

    const contract = getVaultContract();
    const tx = await contract.renewHeartbeat(prevSecret, BigInt(prevEpoch), newCommitment);
    await tx.wait();
    res.json({ ok: true, txHash: tx.hash });
  } catch (err) {
    next(err);
  }
});

router.post('/escalate-access', async (_req, res, next) => {
  try {
    const contract = getVaultContract();
    const tx = await contract.escalateAccess();
    await tx.wait();
    res.json({ ok: true, txHash: tx.hash });
  } catch (err) {
    next(err);
  }
});

router.get('/heartbeat', async (_req, res, next) => {
  try {
    const contract = getVaultContractReadOnly();
    const [heartbeatEpoch, lastHeartbeat, silenceThreshold, heartbeatCommitment] = await Promise.all([
      contract.heartbeatEpoch(),
      contract.lastHeartbeat(),
      contract.silenceThreshold(),
      contract.heartbeatCommitment()
    ]);
    res.json({
      heartbeatEpoch: Number(heartbeatEpoch),
      lastHeartbeat: Number(lastHeartbeat),
      silenceThreshold: Number(silenceThreshold),
      heartbeatCommitment
    });
  } catch (err) {
    next(err);
  }
});

export default router;
