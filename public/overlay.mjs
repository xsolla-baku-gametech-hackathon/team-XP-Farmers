import { renderChat } from './chat.mjs';

const key = location.hash.slice(1), panel = document.getElementById('live-chat'), stage = document.getElementById('overlay-stage');
// Replacing just the fragment in an open browser tab does not reload the page.
// Start a fresh read-only connection instead of continuing to poll a revoked key.
window.addEventListener('hashchange', () => location.reload());
let failures = 0;
async function poll() {
  try {
    const reply = await fetch('/api/overlay', { headers: { Authorization: `Bearer ${key}` }, cache: 'no-store', credentials: 'omit', signal: AbortSignal.timeout(5000) });
    if (!reply.ok) throw new Error('Overlay unavailable');
    const data = await reply.json();
    renderChat(panel, stage, data.state === 'connected' ? data.messages : [], data.settings);
    failures = 0;
  } catch {
    // A read-only preview must never show login forms, sample messages or error chrome.
    panel.hidden = true; panel.replaceChildren(); delete panel.dataset.signature; failures++;
  }
  setTimeout(poll, Math.min(10000, 1000 * 2 ** Math.min(failures, 4)));
}
if (/^[A-Za-z0-9_-]{43}$/.test(key)) poll();
