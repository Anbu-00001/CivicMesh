import { Router } from 'express';
import { getVaultContract, getVaultContractReadOnly, encryptedShareToBytes } from '../lib/contracts.js';
import { getEncryptionKey, getShare, saveEncryptionKey, saveShare } from '../lib/store.js';

const router = Router();

router.post('/register-encryption-key', async (req, res, next) => {
  try {
    const { heir, encryptionPublicKey } = req.body;
    if (!heir || !encryptionPublicKey) {
      return res.status(400).json({ error: 'heir and encryptionPublicKey are required' });
    }
    const row = await saveEncryptionKey({ heir, encryptionPublicKey });
    res.json({ ok: true, key: row });
  } catch (err) {
    next(err);
  }
});

router.get('/encryption-key', async (req, res, next) => {
  try {
    const { heir } = req.query;
    if (!heir) return res.status(400).json({ error: 'heir is required' });
    const row = await getEncryptionKey(heir);
    if (!row) return res.status(404).json({ error: 'No encryption public key registered for heir' });
    res.json({ heir, encryptionPublicKey: row.encryption_public_key });
  } catch (err) {
    next(err);
  }
});

router.post('/deposit-share', async (req, res, next) => {
  try {
    const { heir, encryptedShare, ownerDid, threshold } = req.body;
    if (!heir || !encryptedShare) return res.status(400).json({ error: 'heir and encryptedShare are required' });

    const row = await saveShare({ ownerDid, heir, encryptedShare });
    let txHash = null;

    if (process.env.LEGACY_VAULT_ADDRESS || process.env.VAULT_ADDRESS) {
      const contract = getVaultContract();
      if (threshold) {
        const tx = await contract.setShareThreshold(BigInt(threshold));
        await tx.wait();
      }
      const tx = await contract.depositEncryptedShare(heir, encryptedShareToBytes(row.encrypted_share));
      await tx.wait();
      txHash = tx.hash;
    }

    res.json({ ok: true, txHash, share: row });
  } catch (err) {
    next(err);
  }
});

router.get('/my-share', async (req, res, next) => {
  try {
    const { heir } = req.query;
    if (!heir) return res.status(400).json({ error: 'heir is required' });

    if (process.env.LEGACY_VAULT_ADDRESS || process.env.VAULT_ADDRESS) {
      const contract = getVaultContractReadOnly();
      const canAccess = await contract.canAccess(heir);
      if (!canAccess) return res.status(403).json({ error: 'Access not yet granted on-chain' });
    }

    const row = await getShare(heir);
    if (!row) return res.status(404).json({ error: 'No encrypted share found for heir' });
    res.json({ encryptedShare: row.encrypted_share, ownerDid: row.owner_did });
  } catch (err) {
    next(err);
  }
});

export default router;
