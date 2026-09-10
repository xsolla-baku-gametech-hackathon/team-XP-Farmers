const $ = id => document.getElementById(id), api = window.chatDesktop;
let busy = false, current, lastAddress;
function error(message = '') { $('error').textContent = message; $('error').hidden = !message; }
function paint(state) {
  if (state.error) { error(state.error); return; }
  current = state;
  if (state.address !== lastAddress) { $('link').value = state.address; lastAddress = state.address; }
  if (state.address && !$('studio').value) $('studio').value = new URL(state.address).origin;
  const selected = $('display').value || state.displayId;
  $('display').replaceChildren(...state.displays.map(display => {
    const option = document.createElement('option'); option.value = display.id; option.textContent = display.label; return option;
  }));
  $('display').value = state.displays.some(display => display.id === selected) ? selected : state.displayId;
  $('status').textContent = state.detail;
  $('start').textContent = state.visible ? 'Restart overlay' : 'Start overlay';
  $('start').disabled = busy; $('stop').disabled = busy || !state.visible;
}
api.onState(paint);
$('open-studio').addEventListener('click', async () => {
  error();
  try { const reply = await api.openStudio($('studio').value); if (reply.error) error(reply.error); }
  catch { error('Could not open the browser. Try again.'); }
});
$('start').addEventListener('click', async () => {
  const values = { address: $('link').value, displayId: $('display').value };
  busy = true; error(); if (current) paint(current);
  try { paint(await api.start(values)); }
  catch { error('Could not start the overlay. Try again.'); }
  finally { busy = false; if (current) paint(current); }
});
$('stop').addEventListener('click', async () => { error(); try { paint(await api.stop()); } catch { error('Could not stop the overlay. Close the desktop app to stop it.'); } });
try { paint(await api.state()); } catch { error('Desktop controls are unavailable. Restart the application.'); }
