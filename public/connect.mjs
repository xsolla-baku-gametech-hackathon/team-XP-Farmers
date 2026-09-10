const ticket = location.hash.slice(1);
history.replaceState(null, '', location.pathname);
const button = document.getElementById('continue');
button.addEventListener('click', async () => {
  button.disabled = true;
  try {
    const response = await fetch('/api/device/authorize', { method: 'POST', headers: { 'Content-Type': 'application/json', 'X-Chat-Studio': '1' }, body: JSON.stringify({ ticket }) });
    const data = await response.json();
    if (!response.ok) throw new Error(data.error || 'Connection failed. Start again in your game.');
    location.assign(data.authorizeURL);
  } catch (error) {
    document.getElementById('status').textContent = error.message;
    button.disabled = false;
  }
});
