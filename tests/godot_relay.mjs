// Local fixture verifies Godot's actual HTTP/Bearer path; no platform credentials.
import { createServer } from 'node:http';
import { spawn } from 'node:child_process';
const key = 'a'.repeat(43);
let requests = 0, invalid = 0;
const server = createServer((req, res) => {
  if (req.url !== '/api/overlay' || req.headers.authorization !== `Bearer ${key}`) {
    invalid++; res.writeHead(401).end(); return;
  }
  requests++;
  res.setHeader('Content-Type', 'application/json');
  res.end(JSON.stringify({ provider: 'twitch', state: 'connected', settings: { enabled: true },
    messages: requests === 1 ? [] : [{ id: 'http-1', author: 'HTTP_User', text: 'Network delivery' }] }));
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const child = spawn(process.env.GODOT || 'godot', ['--headless', '--path', '.', '--script', 'tests/test_chat_http.gd'], {
  stdio: 'inherit', env: { ...process.env, CHAT_TEST_LINK: `http://127.0.0.1:${server.address().port}/overlay#${key}` }
});
const timeout = setTimeout(() => child.kill(), 15000);
child.on('error', error => { console.error(error.message); server.close(); clearTimeout(timeout); process.exitCode = 1; });
child.on('exit', code => { server.close(); clearTimeout(timeout); process.exitCode = code === 0 && requests >= 2 && !invalid ? 0 : 1; });
