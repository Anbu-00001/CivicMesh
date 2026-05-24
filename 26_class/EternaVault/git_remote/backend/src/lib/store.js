import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createClient } from '@supabase/supabase-js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const dataDir = path.resolve(__dirname, '../../data');
const uploadDir = path.resolve(__dirname, '../../uploads');
const memoryFile = path.join(dataDir, 'memories.json');
const shareFile = path.join(dataDir, 'shares.json');
const encryptionKeyFile = path.join(dataDir, 'encryption-keys.json');

let supabaseClient = null;

export function supabase() {
  if (supabaseClient) return supabaseClient;
  if (!process.env.SUPABASE_URL || !process.env.SUPABASE_SERVICE_ROLE_KEY) return null;
  supabaseClient = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY);
  return supabaseClient;
}

export async function ensureLocalStore() {
  await fs.mkdir(dataDir, { recursive: true });
  await fs.mkdir(uploadDir, { recursive: true });
  await ensureJson(memoryFile, []);
  await ensureJson(shareFile, []);
  await ensureJson(encryptionKeyFile, []);
}

export function localUploadDir() {
  return uploadDir;
}

export async function saveMemory(record, fileBuffer) {
  const sb = supabase();
  if (sb && process.env.SUPABASE_BUCKET) {
    const pathName = `${record.owner || 'unknown'}/${record.id}.enc`;
    const { error } = await sb.storage.from(process.env.SUPABASE_BUCKET).upload(pathName, fileBuffer, {
      contentType: 'application/octet-stream',
      upsert: true
    });
    if (error) throw error;
    const row = { ...record, path: pathName };
    const { error: insertError } = await sb.from('memories').upsert(row);
    if (insertError) throw insertError;
    return row;
  }

  await ensureLocalStore();
  const diskPath = path.join(uploadDir, `${record.id}.enc`);
  await fs.writeFile(diskPath, fileBuffer);
  const row = { ...record, path: diskPath };
  const memories = await readJson(memoryFile, []);
  memories.push(row);
  await writeJson(memoryFile, memories);
  return row;
}

export async function listMemories(heir) {
  const sb = supabase();
  if (sb) {
    let query = sb.from('memories').select('*').order('created_at', { ascending: false });
    const { data, error } = await query;
    if (error) throw error;
    return filterByHeir(data || [], heir);
  }

  await ensureLocalStore();
  return filterByHeir(await readJson(memoryFile, []), heir);
}

export async function getMemory(id) {
  const memories = await listMemories();
  return memories.find((memory) => memory.id === id);
}

export async function readMemoryBlob(memory) {
  const sb = supabase();
  if (sb && process.env.SUPABASE_BUCKET && memory.path && !path.isAbsolute(memory.path)) {
    const { data, error } = await sb.storage.from(process.env.SUPABASE_BUCKET).download(memory.path);
    if (error) throw error;
    return Buffer.from(await data.arrayBuffer());
  }
  return fs.readFile(memory.path);
}

export async function saveShare({ ownerDid, heir, encryptedShare }) {
  const row = {
    owner_did: ownerDid || null,
    heir_address: heir.toLowerCase(),
    encrypted_share: typeof encryptedShare === 'string' ? encryptedShare : JSON.stringify(encryptedShare),
    updated_at: new Date().toISOString()
  };

  const sb = supabase();
  if (sb) {
    const { error } = await sb.from('vault_shares').upsert(row, { onConflict: 'heir_address' });
    if (error) throw error;
    return row;
  }

  await ensureLocalStore();
  const shares = await readJson(shareFile, []);
  const next = shares.filter((share) => share.heir_address !== row.heir_address);
  next.push(row);
  await writeJson(shareFile, next);
  return row;
}

export async function getShare(heir) {
  const normalized = heir.toLowerCase();
  const sb = supabase();
  if (sb) {
    const { data, error } = await sb.from('vault_shares').select('*').eq('heir_address', normalized).maybeSingle();
    if (error) throw error;
    return data;
  }

  await ensureLocalStore();
  const shares = await readJson(shareFile, []);
  return shares.find((share) => share.heir_address === normalized) || null;
}

export async function saveEncryptionKey({ heir, encryptionPublicKey }) {
  const row = {
    heir_address: heir.toLowerCase(),
    encryption_public_key: encryptionPublicKey,
    updated_at: new Date().toISOString()
  };

  const sb = supabase();
  if (sb) {
    const { error } = await sb.from('heir_encryption_keys').upsert(row, { onConflict: 'heir_address' });
    if (error) throw error;
    return row;
  }

  await ensureLocalStore();
  const keys = await readJson(encryptionKeyFile, []);
  const next = keys.filter((key) => key.heir_address !== row.heir_address);
  next.push(row);
  await writeJson(encryptionKeyFile, next);
  return row;
}

export async function getEncryptionKey(heir) {
  const normalized = heir.toLowerCase();
  const sb = supabase();
  if (sb) {
    const { data, error } = await sb
      .from('heir_encryption_keys')
      .select('*')
      .eq('heir_address', normalized)
      .maybeSingle();
    if (error) throw error;
    return data;
  }

  await ensureLocalStore();
  const keys = await readJson(encryptionKeyFile, []);
  return keys.find((key) => key.heir_address === normalized) || null;
}

function filterByHeir(memories, heir) {
  if (!heir) return memories;
  const normalized = heir.toLowerCase();
  return memories.filter((memory) => {
    const heirs = memory.meta?.heirs || [];
    return heirs.map((address) => String(address).toLowerCase()).includes(normalized);
  });
}

async function ensureJson(file, fallback) {
  try {
    await fs.access(file);
  } catch {
    await writeJson(file, fallback);
  }
}

async function readJson(file, fallback) {
  try {
    return JSON.parse(await fs.readFile(file, 'utf8'));
  } catch {
    return fallback;
  }
}

async function writeJson(file, value) {
  await fs.mkdir(path.dirname(file), { recursive: true });
  await fs.writeFile(file, JSON.stringify(value, null, 2));
}
