// Local fixture exercises Godot's pairing HTTP and disconnect; no live account.
import { createServer } from 'node:http';
import { spawn } from 'node:child_process';
let created = false, polled = false, removed = false;
const token = 'a'.repeat(43);
const server = createServer(async (req, res) => {
  res.setHeader('Content-Type', 'application/json');
  if (req.url !== '/api/device' || req.headers['x-chat-studio'] !== '1') return res.writeHead(404).end('{}');
  if (req.method === 'POST') {
    let body = ''; for await (const chunk of req) body += chunk;
    created = JSON.parse(body).provider === 'kick';
    return res.writeHead(201).end(JSON.stringify({ token, browserURL: `http://127.0.0.1:${server.address().port}/connect#${'c'.repeat(43)}` }));
  }
  if (req.headers.authorization !== `Bearer ${token}`) return res.writeHead(401).end('{}');
  if (req.method === 'DELETE') { removed = true; return res.end('{"ok":true}'); }
  polled = true;
  res.end(JSON.stringify({ state: 'connected', channel: 'Fixture channel', overlayURL: `http://127.0.0.1:${server.address().port}/overlay#${'b'.repeat(43)}` }));
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const child = spawn(process.env.GODOT || 'godot', [...(process.env.CHAT_TEST_LOG ? ['--log-file', process.env.CHAT_TEST_LOG] : []), '--headless', '--path', '.', '--script', 'tests/test_pairing.gd'], {
  stdio: 'inherit', env: { ...process.env, CHAT_TEST_ORIGIN: `http://127.0.0.1:${server.address().port}` }
});
const timeout = setTimeout(() => child.kill(), 15000);
child.on('error', error => { console.error(error.message); server.close(); clearTimeout(timeout); process.exitCode = 1; });
child.on('exit', code => { server.close(); clearTimeout(timeout); process.exitCode = code === 0 && created && polled && removed ? 0 : 1; });
