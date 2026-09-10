// Verify, export, and launch the packaged Windows application once headlessly.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const cp = require('node:child_process');
const { verify, runChecked, inspectOutput } = require('./verify.cjs');
const root = path.resolve(__dirname, '..');
const godot = process.argv[2] || process.env.GODOT_BIN || 'godot';
const destination = path.resolve(process.argv[3] || path.join(root, 'builds', 'windows', String(Date.now())));
function main() {
  if (fs.existsSync(destination) && fs.readdirSync(destination).length) {
    throw new Error('Choose an empty build directory; existing files will not be overwritten.');
  }
  fs.mkdirSync(destination, { recursive: true });
  const checks = verify(godot);
  const executable = path.join(destination, 'StreamerMode.exe');
  console.log('Exporting Windows Demo...');
  runChecked(godot, ['--headless', '--path', root, '--export-release', 'Windows Demo', executable,
    '--log-file', path.join(checks.directory, 'export.log')], {
    log: path.join(checks.directory, 'export.log'), timeout: 180000,
  });
  if (!fs.existsSync(executable) || fs.statSync(executable).size < 1024 * 1024) {
    throw new Error('The exported executable is missing or unexpectedly small.');
  }
  // Run outside the source project so the embedded package must supply resources.
  const smokeLog = path.join(checks.directory, 'export-smoke.log');
  console.log('Launching exported application for smoke check...');
  runChecked(executable, ['--headless', '--quit-after', '60', '--log-file', smokeLog], {
    cwd: destination, log: path.join(checks.directory, 'export-smoke-console.log'), timeout: 30000,
  });
  if (!fs.existsSync(smokeLog)) throw new Error('Export did not produce its runtime log.');
  const runtimeLog = fs.readFileSync(smokeLog, 'utf8');
  const issues = inspectOutput(runtimeLog);
  if (!runtimeLog.includes('Godot Engine v4.7.2') || issues.errors.length) {
    throw new Error('Packaged runtime check failed. See ' + smokeLog);
  }
  runChecked(godot, ["--headless", "--path", root, "--script", "res://tools/export_licenses.gd", "--log-file", path.join(checks.directory, "licenses.log"), "--", path.join(destination, "THIRD-PARTY-NOTICES.txt")], {log: path.join(checks.directory, "licenses.log"), marker: "Engine notices exported"});
  const revision = cp.spawnSync('git', ['rev-parse', 'HEAD'], { cwd: root, encoding: 'utf8', windowsHide: true }).stdout?.trim() || 'unknown';
  const dirty = cp.spawnSync('git', ['status', '--porcelain'], { cwd: root, encoding: 'utf8', windowsHide: true }).stdout?.trim();
  const manifest = {
    revision, working_tree_changes: Boolean(dirty), verified: true, godot: checks.report.godot,
    files: {}, pending: checks.report.pending,
  };
  for (const entry of fs.readdirSync(destination, { withFileTypes: true })) {
    if (entry.isFile()) manifest.files[entry.name] = crypto.createHash('sha256').update(fs.readFileSync(path.join(destination, entry.name))).digest('hex');
  }
  fs.writeFileSync(path.join(destination, 'build-manifest.json'), JSON.stringify(manifest, null, 2) + '\n');
  console.log('Windows build ready: ' + executable);
  console.log('Gameplay/UI integration suites passed; OBS and physical audio still need a manual check.');
}
try { main(); } catch (error) { console.error(error.message); process.exitCode = 1; }
