import { app, BrowserWindow, ipcMain, Menu, screen, session as electronSession, shell } from 'electron';
import { fileURLToPath } from 'node:url';
import { studioOrigin, overlayAddress, fromDeepLink, overlayOptions } from './policy.mjs';

app.setName('XP Farmers Chat');
const controlURL = new URL('./index.html', import.meta.url).href;
let control, overlay, pendingLink, address = '', visible = false, displayId, quitting = false;
let detail = 'Connect your channel in Chat Studio, then open your overlay here.';
const snapshot = () => ({ address, visible, detail,
  displays: screen.getAllDisplays().map((display, index) => ({ id: String(display.id), label: display.label || `Display ${index + 1}` })),
  displayId: String(displayId ?? screen.getPrimaryDisplay().id),
});
function publish() { if (control && !control.isDestroyed()) control.webContents.send('desktop:state', snapshot()); }
function showControl() {
  if (!control || control.isDestroyed()) createControl();
  if (control.isMinimized()) control.restore();
  control.show(); control.focus();
}
function stopOverlay() {
  if (overlay && !overlay.isDestroyed()) overlay.destroy();
  overlay = null; visible = false; detail = 'Desktop overlay stopped.'; publish();
}
function receiveLink(value) {
  try { address = fromDeepLink(value); detail = 'Your link is ready. Choose a display and start the overlay.'; }
  catch { detail = 'The desktop link is invalid. Copy a fresh overlay link from Chat Studio.'; }
  showControl(); publish();
}
app.on('open-url', (event, value) => { event.preventDefault(); if (app.isReady()) receiveLink(value); else pendingLink = value; });
if (!app.requestSingleInstanceLock()) app.quit();
else {
  app.on('second-instance', (event, args) => {
    const value = args.find(arg => arg.startsWith('xp-farmers-chat://'));
    if (value) receiveLink(value); else showControl();
  });
  app.whenReady().then(() => {
    // Development does not alter OS-wide URL associations.
    if (app.isPackaged) app.setAsDefaultProtocolClient('xp-farmers-chat');
    Menu.setApplicationMenu(Menu.buildFromTemplate([
      { label: 'XP Farmers Chat', submenu: [
        { label: 'Show controls', click: showControl },
        { label: 'Stop overlay', accelerator: 'CmdOrCtrl+Shift+H', click: stopOverlay },
        { type: 'separator' }, { role: 'quit' },
      ] },
      { label: 'Edit', submenu: [{ role: 'undo' }, { role: 'redo' }, { type: 'separator' }, { role: 'cut' }, { role: 'copy' }, { role: 'paste' }, { role: 'selectAll' }] },
    ]));
    createControl();
    const value = pendingLink || process.argv.find(arg => arg.startsWith('xp-farmers-chat://'));
    if (value) receiveLink(value);
    const updateDisplay = () => {
      const display = screen.getAllDisplays().find(item => String(item.id) === String(displayId)) || screen.getPrimaryDisplay();
      displayId = display.id;
      if (overlay && !overlay.isDestroyed()) overlay.setBounds(display.bounds);
      publish();
    };
    for (const event of ['display-added', 'display-removed', 'display-metrics-changed']) screen.on(event, updateDisplay);
  }).catch(() => { console.error('Chat desktop could not start.'); app.quit(); });
}
app.on('activate', showControl);
app.on('before-quit', () => { quitting = true; stopOverlay(); });
app.on('window-all-closed', () => app.quit());

function createControl() {
  control = new BrowserWindow({ width: 560, height: Math.min(820, screen.getPrimaryDisplay().workAreaSize.height), minWidth: 420, minHeight: 540,
    title: 'XP Farmers Chat', backgroundColor: '#101210', autoHideMenuBar: true,
    webPreferences: { preload: fileURLToPath(new URL('./preload.cjs', import.meta.url)), nodeIntegration: false, contextIsolation: true, sandbox: true },
  });
  control.webContents.setWindowOpenHandler(() => ({ action: 'deny' }));
  control.webContents.on('will-navigate', event => event.preventDefault());
  control.webContents.session.setPermissionRequestHandler((contents, permission, callback) => callback(false));
  control.webContents.session.setPermissionCheckHandler(() => false);
  control.on('close', event => {
    // Minimize instead of leaving an invisible app with no way to stop its overlay.
    if (!quitting && overlay && !overlay.isDestroyed()) { event.preventDefault(); control.minimize(); }
  });
  control.loadURL(controlURL).catch(() => { detail = 'Could not open desktop controls.'; });
}
function trusted(event) { return control && event.sender === control.webContents && event.senderFrame?.url === controlURL; }
ipcMain.handle('desktop:state', event => { if (!trusted(event)) throw new Error('Unknown sender'); return snapshot(); });
ipcMain.handle('desktop:studio', async (event, value) => {
  if (!trusted(event)) throw new Error('Unknown sender');
  try { await shell.openExternal(studioOrigin(value)); return { ok: true }; }
  catch (error) { return { error: error.message || 'Could not open Chat Studio.' }; }
});
ipcMain.handle('desktop:stop', event => { if (!trusted(event)) throw new Error('Unknown sender'); stopOverlay(); return snapshot(); });
ipcMain.handle('desktop:start', async (event, values) => {
  if (!trusted(event)) throw new Error('Unknown sender');
  let current;
  try {
    const next = overlayAddress(values?.address);
    const display = screen.getAllDisplays().find(item => String(item.id) === values?.displayId);
    if (!display) throw new Error('Choose an available display.');
    stopOverlay(); address = next; displayId = display.id;
    const url = new URL(next), isolated = electronSession.fromPartition('chat-overlay');
    isolated.setPermissionRequestHandler((contents, permission, callback) => callback(false));
    isolated.setPermissionCheckHandler(() => false);
    isolated.removeAllListeners('will-download');
    isolated.on('will-download', event => event.preventDefault());
    isolated.webRequest.onBeforeRequest((details, callback) => {
      try { const target = new URL(details.url); callback({ cancel: target.origin !== url.origin }); }
      catch { callback({ cancel: true }); }
    });
    const options = overlayOptions(display.bounds);
    overlay = new BrowserWindow({ ...options, webPreferences: { ...options.webPreferences, session: isolated } });
    current = overlay;
    current.setIgnoreMouseEvents(true);
    current.setAlwaysOnTop(true, 'screen-saver');
    if (process.platform === 'darwin') current.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true });
    current.webContents.setWindowOpenHandler(() => ({ action: 'deny' }));
    current.webContents.on('will-navigate', event => event.preventDefault());
    current.webContents.on('will-redirect', event => event.preventDefault());
    current.webContents.on('render-process-gone', () => { if (overlay === current) { stopOverlay(); detail = 'Overlay interrupted. Start it again to reconnect.'; publish(); } });
    let deadline;
    try {
      await Promise.race([current.loadURL(next), new Promise((resolve, reject) => {
        deadline = setTimeout(() => reject(new Error('Overlay connection timed out. Check the studio address.')), 15000);
      })]);
    } finally { clearTimeout(deadline); }
    if (overlay !== current || current.isDestroyed()) return snapshot();
    current.showInactive(); visible = true;
    detail = 'Overlay running. Chat appears when your channel is connected and Streamer Mode is on.';
    publish(); return snapshot();
  } catch (error) {
    if (current && overlay !== current) return snapshot();
    if (current) stopOverlay();
    detail = 'Could not start the overlay. Check the link and the studio connection.'; publish();
    return { error: error.message?.startsWith('ERR_') ? detail : error.message || detail };
  }
});
