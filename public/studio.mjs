import { defaults, safeSettings, renderChat, request } from './chat.mjs';

const providerNames = { kick: 'Kick', twitch: 'Twitch', youtube: 'YouTube' };
const $ = id => document.getElementById(id);
const samples = [{ author: 'azra_gg', color: '#bcf478', text: 'That was so close!' }, { author: 'pixelpilot', color: '#c487ff', text: 'One more round?' }, { author: 'nova', color: '#ffae8c', text: "Let's go!" }];
let settings = { ...defaults }, provider = 'kick', session = null, available = {}, ready = false, busy = false, dirty = false, saveTimer, generation = 0;
let saves = Promise.resolve();
try { settings = safeSettings(JSON.parse(localStorage.getItem('xp-chat-settings'))); } catch { /* Preferences are optional. */ }
const persistLocal = () => { try { localStorage.setItem('xp-chat-settings', JSON.stringify(settings)); } catch { /* Private browsing */ } };
function error(message = '') { $('error').textContent = message; $('error').hidden = !message; }
function paint() {
  for (const name of Object.keys(providerNames)) {
    $(name).classList.toggle('selected', provider === name);
    $(name).setAttribute('aria-pressed', String(provider === name));
    $(name).disabled = Boolean(session) || busy;
  }
  $('connect').textContent = busy ? 'Connecting…' : `Connect ${providerNames[provider]}`;
  $('connect').hidden = Boolean(session); $('connect').disabled = busy || !ready;
  $('disconnect').hidden = !session; $('disconnect').disabled = busy;
  $('connection-status').dataset.state = session?.state || 'disconnected';
  $('connection-detail').textContent = session ? `${session.channel ? `${session.channel} · ` : ''}${session.detail}` : 'No channel connected';
  $('opacity').value = settings.opacity; $('opacity-value').textContent = `${settings.opacity}%`;
  $('opacity').setAttribute('aria-valuetext', `${settings.opacity}% background opacity`);
  $('font-size').value = settings.fontSize; $('position').value = settings.position;
  $('mode').setAttribute('aria-checked', String(settings.enabled));
  const connected = session?.state === 'connected';
  $('preview-label').textContent = !settings.enabled ? 'Streamer Mode off' : session ? (connected ? 'Live chat' : session.state === 'waiting' ? 'Waiting for live stream' : 'Waiting for connection') : 'Sample preview';
  $('preview-caption').textContent = !settings.enabled ? 'Your overlay is hidden. Turn on Streamer Mode to show new messages.' : session
    ? (connected ? 'Live messages from your channel. Each message includes the sender’s username.' : 'Your overlay stays clear until the channel is connected.')
    : 'Sample messages only. Your live chat appears after connection.';
  renderChat($('preview-chat'), $('preview-canvas'), session ? (connected ? session.messages : []) : samples, settings);
  const url = session?.overlayURL;
  $('overlay-url').value = url || ''; $('copy').disabled = !url; $('rotate').disabled = busy || dirty;
  for (const id of ['opacity', 'font-size', 'position', 'mode']) $(id).disabled = busy;
  $('open-overlay').setAttribute('aria-disabled', String(!url));
  if (url) $('open-overlay').href = url; else $('open-overlay').removeAttribute('href');
  $('link-tools').hidden = !url;
}
async function refresh() {
  const version = generation;
  try {
    const next = await request('/api/session');
    if (busy || version !== generation) return;
    session = next; provider = next.provider;
    if (!dirty) { settings = safeSettings(next.settings); persistLocal(); }
    paint();
  } catch (failure) {
    if (busy || version !== generation) return;
    if (failure.status === 401) { session = null; paint(); }
    else if (session) { session.state = 'error'; session.detail = 'Connection to Chat Studio interrupted. Retrying…'; paint(); }
  }
}
function change(patch) {
  settings = safeSettings({ ...settings, ...patch }); persistLocal(); paint();
  if (!session) return;
  dirty = true; clearTimeout(saveTimer);
  const version = ++generation;
  saveTimer = setTimeout(() => {
    const body = JSON.stringify(settings);
    saves = saves.then(async () => {
      try {
        const next = await request('/api/settings', { method: 'PATCH', body });
        if (version === generation) { session = next; dirty = false; error(); paint(); }
      } catch { if (version === generation) { dirty = false; error('Could not save your settings. Check the connection and try again.'); paint(); } }
    });
  }, 120);
}
for (const name of Object.keys(providerNames)) $(name).addEventListener('click', () => { provider = name; error(); paint(); });
$('connect').addEventListener('click', async () => {
  error();
  if (!available[provider]) { error(`${providerNames[provider]} connections are not available on this server yet. Contact the service owner.`); return; }
  busy = true; generation++; paint();
  try {
    const result = await request('/api/session', { method: 'POST', body: JSON.stringify({ provider, settings }) });
    const address = new URL(result.authorizeURL);
    if (!['id.kick.com', 'id.twitch.tv', 'accounts.google.com'].includes(address.hostname) || address.protocol !== 'https:') throw new Error('Invalid sign-in address');
    window.location.assign(address.href);
  } catch (failure) { error(failure.message); busy = false; paint(); }
});
$('disconnect').addEventListener('click', async () => {
  busy = true; ++generation; clearTimeout(saveTimer); dirty = false; error(); paint();
  try { await saves; await request('/api/session', { method: 'DELETE' }); session = null; $('copy-status').textContent = ''; }
  catch (failure) { error(failure.message); }
  finally { busy = false; paint(); }
});
$('opacity').addEventListener('input', e => change({ opacity: Number(e.target.value) }));
$('font-size').addEventListener('change', e => change({ fontSize: Number(e.target.value) }));
$('position').addEventListener('change', e => change({ position: e.target.value }));
$('mode').addEventListener('click', () => change({ enabled: !settings.enabled }));
$('copy').addEventListener('click', async () => {
  try { await navigator.clipboard.writeText($('overlay-url').value); $('copy-status').textContent = 'Overlay link copied. Paste it into OBS → Sources → Browser.'; }
  catch { $('overlay-url').focus(); $('overlay-url').select(); $('copy-status').textContent = 'Select and copy the link above with Ctrl+C or Command+C.'; }
});
$('rotate').addEventListener('click', async () => {
  busy = true; generation++; error(); paint();
  try {
    session = await request('/api/overlay/rotate', { method: 'POST' });
    $('copy-status').textContent = 'New link created. Replace the old Browser Source URL in OBS.';
  } catch (failure) { error(failure.message); }
  finally { busy = false; paint(); }
});
paint();
try {
  const config = await request('/api/config'); available = config.providers;
  provider = Object.keys(providerNames).find(name => available[name]) || 'kick';
  await refresh(); ready = true; paint();
} catch { error('Chat Studio could not load. Refresh the page to try again.'); }
async function poll() { await refresh(); setTimeout(poll, 1500); }
setTimeout(poll, 1500);
