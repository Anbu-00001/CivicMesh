import cron from 'node-cron';
import { getVaultContractReadOnly } from '../lib/contracts.js';

export function startHeartbeatMonitor({ sendHeartbeatReminder = defaultReminder } = {}) {
  cron.schedule('0 8 * * *', async () => {
    try {
      const contract = getVaultContractReadOnly();
      const lastBeat = Number(await contract.lastHeartbeat());
      const threshold = Number(await contract.silenceThreshold());
      if (!lastBeat || !threshold) return;

      const deadline = (lastBeat + threshold) * 1000;
      const daysLeft = Math.floor((deadline - Date.now()) / 86400000);
      if ([30, 14, 3].includes(daysLeft)) {
        await sendHeartbeatReminder(daysLeft);
      }
    } catch (err) {
      console.error('heartbeat monitor failed:', err.message);
    }
  });
}

async function defaultReminder(daysLeft) {
  console.log(`MemCap heartbeat reminder: ${daysLeft} days left before silence unlock.`);
}
