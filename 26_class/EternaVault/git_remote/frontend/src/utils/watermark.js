const BLOCK_SIZE = 8;
const WATERMARK_STRENGTH = 8;
const ADDRESS_BITS = 160;
const TARGET_U = 4;
const TARGET_V = 4;

export async function embedHeirWatermark(imageBlob, heirAddress) {
  const bits = hexToBits(normalizeAddressHex(heirAddress));
  const img = await blobToImageElement(imageBlob);
  const canvas = document.createElement('canvas');
  canvas.width = img.naturalWidth || img.width;
  canvas.height = img.naturalHeight || img.height;
  const ctx = canvas.getContext('2d', { willReadFrequently: true });
  ctx.drawImage(img, 0, 0);

  const blockCapacity = Math.floor(canvas.width / BLOCK_SIZE) * Math.floor(canvas.height / BLOCK_SIZE);
  if (blockCapacity < bits.length) {
    throw new Error('Image is too small for a 160-bit heir watermark.');
  }

  const imageData = ctx.getImageData(0, 0, canvas.width, canvas.height);
  const pixels = imageData.data;
  let bitIndex = 0;

  for (let y = 0; y <= canvas.height - BLOCK_SIZE && bitIndex < bits.length; y += BLOCK_SIZE) {
    for (let x = 0; x <= canvas.width - BLOCK_SIZE && bitIndex < bits.length; x += BLOCK_SIZE) {
      const block = extractBlock(pixels, x, y, canvas.width);
      const dctBlock = dct2d(block);
      dctBlock[TARGET_U][TARGET_V] = encodeBitInCoefficient(dctBlock[TARGET_U][TARGET_V], bits[bitIndex]);
      const restoredBlock = idct2d(dctBlock);
      writeBlock(pixels, restoredBlock, x, y, canvas.width);
      bitIndex++;
    }
  }

  ctx.putImageData(imageData, 0, 0);
  URL.revokeObjectURL(img.src);

  return new Promise((resolve, reject) => {
    canvas.toBlob(
      (blob) => {
        if (blob) resolve(blob);
        else reject(new Error('Unable to encode watermarked image.'));
      },
      'image/jpeg',
      0.92
    );
  });
}

export async function extractHeirWatermark(imageBlob) {
  const img = await blobToImageElement(imageBlob);
  const canvas = document.createElement('canvas');
  canvas.width = img.naturalWidth || img.width;
  canvas.height = img.naturalHeight || img.height;
  const ctx = canvas.getContext('2d', { willReadFrequently: true });
  ctx.drawImage(img, 0, 0);

  const imageData = ctx.getImageData(0, 0, canvas.width, canvas.height);
  const pixels = imageData.data;
  const bits = [];

  for (let y = 0; y <= canvas.height - BLOCK_SIZE && bits.length < ADDRESS_BITS; y += BLOCK_SIZE) {
    for (let x = 0; x <= canvas.width - BLOCK_SIZE && bits.length < ADDRESS_BITS; x += BLOCK_SIZE) {
      const block = extractBlock(pixels, x, y, canvas.width);
      const dctBlock = dct2d(block);
      bits.push(decodeBitFromCoefficient(dctBlock[TARGET_U][TARGET_V]));
    }
  }

  URL.revokeObjectURL(img.src);
  if (bits.length < ADDRESS_BITS) throw new Error('Image is too small to contain a MemCap heir watermark.');
  return '0x' + bitsToHex(bits);
}

function encodeBitInCoefficient(coeff, bit) {
  let bucket = Math.round(coeff / WATERMARK_STRENGTH);
  const parity = Math.abs(bucket) % 2;
  if (parity !== bit) bucket += bucket >= 0 ? 1 : -1;
  return bucket * WATERMARK_STRENGTH;
}

function decodeBitFromCoefficient(coeff) {
  return Math.abs(Math.round(coeff / WATERMARK_STRENGTH)) % 2;
}

function extractBlock(pixels, startX, startY, width) {
  const block = Array.from({ length: BLOCK_SIZE }, () => Array(BLOCK_SIZE).fill(0));
  for (let y = 0; y < BLOCK_SIZE; y++) {
    for (let x = 0; x < BLOCK_SIZE; x++) {
      const idx = ((startY + y) * width + startX + x) * 4;
      const r = pixels[idx];
      const g = pixels[idx + 1];
      const b = pixels[idx + 2];
      block[y][x] = 0.299 * r + 0.587 * g + 0.114 * b - 128;
    }
  }
  return block;
}

function writeBlock(pixels, block, startX, startY, width) {
  for (let y = 0; y < BLOCK_SIZE; y++) {
    for (let x = 0; x < BLOCK_SIZE; x++) {
      const idx = ((startY + y) * width + startX + x) * 4;
      const originalLuma = 0.299 * pixels[idx] + 0.587 * pixels[idx + 1] + 0.114 * pixels[idx + 2];
      const nextLuma = clamp(block[y][x] + 128);
      const delta = nextLuma - originalLuma;
      pixels[idx] = clamp(pixels[idx] + delta);
      pixels[idx + 1] = clamp(pixels[idx + 1] + delta);
      pixels[idx + 2] = clamp(pixels[idx + 2] + delta);
    }
  }
}

function dct2d(block) {
  const result = Array.from({ length: BLOCK_SIZE }, () => Array(BLOCK_SIZE).fill(0));
  for (let u = 0; u < BLOCK_SIZE; u++) {
    for (let v = 0; v < BLOCK_SIZE; v++) {
      let sum = 0;
      for (let x = 0; x < BLOCK_SIZE; x++) {
        for (let y = 0; y < BLOCK_SIZE; y++) {
          sum +=
            block[x][y] *
            Math.cos(((2 * x + 1) * u * Math.PI) / 16) *
            Math.cos(((2 * y + 1) * v * Math.PI) / 16);
        }
      }
      result[u][v] = 0.25 * alpha(u) * alpha(v) * sum;
    }
  }
  return result;
}

function idct2d(block) {
  const result = Array.from({ length: BLOCK_SIZE }, () => Array(BLOCK_SIZE).fill(0));
  for (let x = 0; x < BLOCK_SIZE; x++) {
    for (let y = 0; y < BLOCK_SIZE; y++) {
      let sum = 0;
      for (let u = 0; u < BLOCK_SIZE; u++) {
        for (let v = 0; v < BLOCK_SIZE; v++) {
          sum +=
            alpha(u) *
            alpha(v) *
            block[u][v] *
            Math.cos(((2 * x + 1) * u * Math.PI) / 16) *
            Math.cos(((2 * y + 1) * v * Math.PI) / 16);
        }
      }
      result[x][y] = 0.25 * sum;
    }
  }
  return result;
}

function alpha(index) {
  return index === 0 ? 1 / Math.sqrt(2) : 1;
}

function normalizeAddressHex(address) {
  const hex = String(address || '').toLowerCase().replace(/^0x/, '');
  if (!/^[0-9a-f]{40}$/.test(hex)) throw new Error('Expected a 20-byte Ethereum address.');
  return hex;
}

function hexToBits(hex) {
  const bits = [];
  for (const char of hex) {
    const nibble = Number.parseInt(char, 16);
    bits.push((nibble >> 3) & 1, (nibble >> 2) & 1, (nibble >> 1) & 1, nibble & 1);
  }
  return bits;
}

function bitsToHex(bits) {
  let hex = '';
  for (let i = 0; i < bits.length; i += 4) {
    const nibble = (bits[i] << 3) | (bits[i + 1] << 2) | (bits[i + 2] << 1) | bits[i + 3];
    hex += nibble.toString(16);
  }
  return hex.padEnd(40, '0').slice(0, 40);
}

function clamp(value) {
  return Math.max(0, Math.min(255, Math.round(value)));
}

function blobToImageElement(blob) {
  return new Promise((resolve, reject) => {
    const img = new Image();
    img.onload = () => resolve(img);
    img.onerror = reject;
    img.src = URL.createObjectURL(blob);
  });
}
