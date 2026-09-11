import { randomBytes } from 'node:crypto';

export const random = () => randomBytes(32).toString('base64url');
export const defaults = Object.freeze({ enabled: true, opacity: 35, fontSize: 20, position: 'bottom-right' });
export function settingsPatch(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error('Invalid settings');
  const result = {};
  for (const [key, item] of Object.entries(value)) {
    if (key === 'enabled' && typeof item === 'boolean') result[key] = item;
    else if (key === 'opacity' && Number.isInteger(item) && item >= 0 && item <= 100) result[key] = item;
    else if (key === 'fontSize' && [16, 20, 24, 28, 32].includes(item)) result[key] = item;
    else if (key === 'position' && ['bottom-right', 'bottom-left', 'top-right', 'top-left'].includes(item)) result[key] = item;
    else throw new Error('Invalid settings');
  }
  return result;
}
export const literal = (value, max) => typeof value === 'string' ? value.replace(/[\u0000-\u0008\u000b-\u001f\u007f]/g, '').slice(0, max) : '';
export function addMessage(session, message) {
  if (!message?.id || session.messages.some(item => item.id === message.id)) return;
  session.messages.push({ ...message, receivedAt: Date.now() });
  if (session.messages.length > 100) session.messages.shift();
}
export async function jsonRequest(fetchImpl, url, options = {}) {
  const reply = await fetchImpl(url, { ...options, signal: AbortSignal.timeout(10000) });
  if (!reply.ok) throw new Error(`Provider request failed (${reply.status})`);
  return reply.json();
}
