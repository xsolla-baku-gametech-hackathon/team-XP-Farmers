import { createCipheriv, createDecipheriv, randomBytes } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, renameSync, writeFileSync } from 'node:fs';
import { dirname } from 'node:path';

// Single-process encrypted persistence. Chat contents and pending OAuth are never saved.
export function createStorage(path, secret) {
  if (!path) return { load: () => [], save: () => {} };
  if (!/^[a-fA-F0-9]{64}$/.test(secret || '')) throw new Error('SESSION_SECRET must be 64 hexadecimal characters when DATA_FILE is configured');
  const key = Buffer.from(secret, 'hex');
  mkdirSync(dirname(path), { recursive: true, mode: 0o700 });
  return {
    load() {
      if (!existsSync(path)) return [];
      const bytes = readFileSync(path);
      const decipher = createDecipheriv('aes-256-gcm', key, bytes.subarray(0, 12));
      decipher.setAuthTag(bytes.subarray(12, 28));
      return JSON.parse(Buffer.concat([decipher.update(bytes.subarray(28)), decipher.final()]).toString());
    },
    save(sessions) {
      const data = [...sessions].filter(([, s]) => s.tokens).map(([id, s]) => [id, {
        provider: s.provider, user: s.user, channel: s.channel, tokens: s.tokens,
        settings: s.settings, overlayKey: s.overlayKey, touched: s.touched,
      }]);
      const iv = randomBytes(12), cipher = createCipheriv('aes-256-gcm', key, iv);
      const encrypted = Buffer.concat([cipher.update(JSON.stringify(data)), cipher.final()]);
      writeFileSync(`${path}.tmp`, Buffer.concat([iv, cipher.getAuthTag(), encrypted]), { mode: 0o600 });
      renameSync(`${path}.tmp`, path);
    },
  };
}
