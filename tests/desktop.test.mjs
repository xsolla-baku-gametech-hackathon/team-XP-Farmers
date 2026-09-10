import test from 'node:test';
import assert from 'node:assert/strict';
import { studioOrigin, overlayAddress, fromDeepLink, overlayOptions } from '../desktop/policy.mjs';

const key = 'a'.repeat(43), origin = 'https://studio.example';
test('desktop links accept only studio origins and complete read-only overlay URLs', () => {
  assert.equal(studioOrigin(`${origin}/`), origin);
  assert.equal(studioOrigin('http://localhost:8787'), 'http://localhost:8787');
  assert.equal(overlayAddress(`${origin}/overlay#${key}`), `${origin}/overlay#${key}`);
  assert.equal(fromDeepLink(`xp-farmers-chat://overlay?origin=${encodeURIComponent(origin)}#${key}`), `${origin}/overlay#${key}`);
  for (const invalid of ['file:///etc/passwd', 'javascript:alert(1)', 'http://studio.example', 'https://user:pass@studio.example', `${origin}/other`, `${origin}?x=1`, `${origin}#secret`, null]) {
    assert.throws(() => studioOrigin(invalid));
  }
  for (const invalid of [`${origin}/overlay`, `${origin}/overlay#short`, `${origin}/overlay?key=${key}`, `${origin}/other#${key}`, `https://user:password@studio.example/overlay#${key}`, `file:///overlay#${key}`, `http://localhost.evil/overlay#${key}`]) {
    assert.throws(() => overlayAddress(invalid));
  }
  for (const invalid of [`xp-farmers-chat://other?origin=${origin}#${key}`, `xp-farmers-chat://overlay?origin=${origin}&origin=${origin}#${key}`, `xp-farmers-chat://overlay?origin=${origin}/other#${key}`, `${origin}/overlay#${key}`]) {
    assert.throws(() => fromDeepLink(invalid));
  }
});

test('native overlay preserves display bounds and isolates remote content from desktop privileges', () => {
  const options = overlayOptions({ x: -1920, y: 0, width: 1920, height: 1080 });
  assert.equal(options.x, -1920); assert.equal(options.width, 1920);
  assert.equal(options.transparent, true); assert.equal(options.frame, false);
  assert.equal(options.alwaysOnTop, true); assert.equal(options.focusable, false);
  assert.equal(options.show, false); assert.equal(options.backgroundColor, '#00000000');
  assert.deepEqual(options.webPreferences, { nodeIntegration: false, contextIsolation: true, sandbox: true, backgroundThrottling: false, devTools: false });
  assert.equal('preload' in options.webPreferences, false);
});
