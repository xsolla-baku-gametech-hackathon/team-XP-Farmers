export function studioOrigin(value) {
  if (typeof value !== 'string' || value.length > 2048) throw new Error('Enter the Chat Studio address.');
  let url;
  try { url = new URL(value.trim()); } catch { throw new Error('Enter a valid Chat Studio address.'); }
  if (url.username || url.password || !['', '/'].includes(url.pathname) || url.search || url.hash ||
      !(url.protocol === 'https:' || (url.protocol === 'http:' && ['localhost', '127.0.0.1'].includes(url.hostname)))) {
    throw new Error('Use an HTTPS studio address without a path. HTTP localhost is allowed for development.');
  }
  return url.origin;
}

export function overlayAddress(value) {
  if (typeof value !== 'string' || value.length > 4096) throw new Error('Paste your private overlay link from Chat Studio.');
  let url;
  try { url = new URL(value.trim()); } catch { throw new Error('Paste a valid overlay link from Chat Studio.'); }
  studioOrigin(url.origin);
  if (url.username || url.password || url.pathname !== '/overlay' || url.search || !/^#[A-Za-z0-9_-]{43}$/.test(url.hash)) {
    throw new Error('Paste the complete overlay link, including its private key.');
  }
  return url.href;
}

export function fromDeepLink(value) {
  if (typeof value !== 'string' || value.length > 4096) throw new Error('Invalid desktop link.');
  const url = new URL(value);
  if (url.protocol !== 'xp-farmers-chat:' || url.hostname !== 'overlay' || url.pathname || url.username || url.password || url.port ||
      [...url.searchParams.keys()].length !== 1 || !url.searchParams.has('origin')) throw new Error('Invalid desktop link.');
  return overlayAddress(`${studioOrigin(url.searchParams.get('origin'))}/overlay${url.hash}`);
}

export function overlayOptions(bounds) {
  return { ...bounds, frame: false, transparent: true, backgroundColor: '#00000000',
    alwaysOnTop: true, focusable: false, resizable: false, movable: false, hasShadow: false,
    skipTaskbar: true, show: false, fullscreenable: false,
    webPreferences: { nodeIntegration: false, contextIsolation: true, sandbox: true, backgroundThrottling: false, devTools: false },
  };
}
