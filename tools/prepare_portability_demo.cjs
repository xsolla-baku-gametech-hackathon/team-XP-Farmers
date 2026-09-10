// Build a separate project using an exact copy of the addon and a new host game.
// No packages needed. Node.js is only used to copy files, not to run the game.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const root = path.resolve(__dirname, '..');
const destination = path.resolve(process.argv[2] || path.join(root, '.artifacts', 'signal-garden-' + Date.now()));
if (fs.existsSync(destination) && fs.readdirSync(destination).length) {
  throw new Error('Choose an empty destination; existing project files will not be overwritten.');
}
const source = path.join(root, 'addons', 'streamer_mode');
const example = path.join(root, 'examples', 'signal_garden');
for (const protectedRoot of [source, example]) {
  const relative = path.relative(protectedRoot, destination);
  if (!relative || (!relative.startsWith('..' + path.sep) && relative !== '..' && !path.isAbsolute(relative))) {
    throw new Error('Destination must be outside the source folders.');
  }
}
fs.mkdirSync(destination, { recursive: true });
function copyTree(from, to) {
  fs.mkdirSync(to, { recursive: true });
  for (const entry of fs.readdirSync(from, { withFileTypes: true })) {
    if (['.godot', '.artifacts'].includes(entry.name)) continue;
    const input = path.join(from, entry.name);
    const output = path.join(to, entry.name);
    if (entry.isSymbolicLink()) throw new Error('Symlinks are not permitted in a standalone package.');
    if (entry.isDirectory()) copyTree(input, output);
    else fs.copyFileSync(input, output, fs.constants.COPYFILE_EXCL);
  }
}
copyTree(example, destination);
const addonDestination = path.join(destination, 'addons', 'streamer_mode');
copyTree(source, addonDestination);
const hashes = {};
function verify(from, to) {
  for (const entry of fs.readdirSync(from, { withFileTypes: true })) {
    const input = path.join(from, entry.name);
    const output = path.join(to, entry.name);
    if (entry.isDirectory()) verify(input, output);
    else {
      const copied = fs.readFileSync(input);
      const original = fs.readFileSync(output);
      if (!copied.equals(original)) throw new Error('Addon copy differs: ' + entry.name);
      const relative = path.relative(addonDestination, input).split(path.sep).join('/');
      hashes[relative] = crypto.createHash('sha256').update(copied).digest('hex');
      if (/\.(gd|tscn|tres)$/.test(entry.name) && /res:\/\/demo\//.test(copied.toString('utf8'))) {
        throw new Error('Addon depends on the first demo: ' + relative);
      }
    }
  }
}
verify(addonDestination, source);
fs.writeFileSync(path.join(destination, 'addon-manifest.json'), JSON.stringify({ algorithm: 'sha256', files: hashes }, null, 2) + '\n');
console.log('Independent project prepared: ' + destination);
console.log('Verified unchanged addon files: ' + Object.keys(hashes).length);
