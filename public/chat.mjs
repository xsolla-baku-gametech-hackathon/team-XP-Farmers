export const defaults = { enabled: true, opacity: 35, fontSize: 20, position: 'bottom-right' };
export function safeSettings(value) {
  return { enabled: typeof value?.enabled === 'boolean' ? value.enabled : defaults.enabled,
    opacity: Number.isInteger(value?.opacity) && value.opacity >= 0 && value.opacity <= 100 ? value.opacity : defaults.opacity,
    fontSize: [16, 20, 24, 28, 32].includes(value?.fontSize) ? value.fontSize : defaults.fontSize,
    position: ['bottom-right', 'bottom-left', 'top-right', 'top-left'].includes(value?.position) ? value.position : defaults.position };
}
const colors = ['#bcf478', '#c487ff', '#ffae8c', '#86d9f7', '#f5d878'];
export function renderChat(panel, stage, messages, settings) {
  const clean = safeSettings(settings);
  stage.dataset.position = clean.position;
  panel.style.backgroundColor = `rgba(0, 0, 0, ${clean.opacity / 100})`;
  panel.style.fontSize = `${clean.fontSize}px`;
  panel.hidden = !clean.enabled || !messages.length;
  const visible = messages.slice(-12);
  const signature = JSON.stringify(visible);
  if (panel.dataset.signature !== signature) {
    panel.dataset.signature = signature;
    panel.replaceChildren(...visible.map(message => {
      const row = document.createElement('p'); row.className = 'chat-row';
      const author = document.createElement('span'); author.className = 'chat-author';
      const name = String(message.author || 'Unknown user').slice(0, 100);
      author.textContent = `${name}: `;
      let hash = 0; for (const char of name) hash = ((hash << 5) - hash + char.codePointAt(0)) | 0;
      author.style.color = /^#[0-9a-f]{6}$/i.test(message.color || '') ? message.color : colors[Math.abs(hash) % colors.length];
      const text = document.createElement('span'); text.className = 'chat-text'; text.textContent = String(message.text || '').slice(0, 2000);
      row.append(author, text); return row;
    }));
  }
  // Keep the newest message visible when long messages fill a short OBS source.
  panel.scrollTop = panel.scrollHeight;
}
export async function request(path, options = {}) {
  const response = await fetch(path, { ...options, cache: 'no-store', signal: AbortSignal.timeout(10000),
    headers: { 'Content-Type': 'application/json', 'X-Chat-Studio': '1', ...options.headers } });
  const body = await response.json();
  if (!response.ok) throw Object.assign(new Error(body.error || 'Request failed'), { status: response.status });
  return body;
}
