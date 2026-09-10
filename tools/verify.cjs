// Run the reviewed suites and isolate the second host. No shell interpolation.
const fs = require('node:fs');
const path = require('node:path');
const cp = require('node:child_process');
const root = path.resolve(__dirname, '..');
const environmentDiagnostics = [
  /^ERROR: Failed to read the root certificate store\.$/,
  /^ERROR: Could not (?:open 'user:\/\/' directory: 'user:\/\/'.|create ObjectDB Snapshots directory: user:\/\/)$/,
  /^ERROR: Can't create shader cache folder, no shader caching will happen: user:\/\/$/,
];
function clean(text) { return text.replace(/\x1b\[[0-9;]*m/g, ''); }
function inspectOutput(output) {
  const lines = clean(output).split(/\r?\n/);
  const errors = lines.filter(line => /^\s*(?:SCRIPT ERROR:|ERROR:|Parse Error:)/.test(line))
    .filter(line => !environmentDiagnostics.some(pattern => pattern.test(line.trim())));
  return { errors, diagnostics: lines.filter(line => environmentDiagnostics.some(pattern => pattern.test(line.trim()))) };
}
function runChecked(executable, args, options = {}) {
  const started = Date.now();
  const result = cp.spawnSync(executable, args, {
    cwd: options.cwd || root, encoding: 'utf8', windowsHide: true,
    timeout: options.timeout || 120000, maxBuffer: 16 * 1024 * 1024,
  });
  const output = (result.stdout || '') + (result.stderr || '');
  if (options.log) fs.writeFileSync(options.log, output);
  const review = inspectOutput(output);
  const missingMarker = options.marker && !clean(output).includes(options.marker);
  if (result.error || result.status !== 0 || review.errors.length || missingMarker) {
    throw new Error((result.error?.message || review.errors.join('\n') ||
      (missingMarker ? 'Expected success marker not found: ' + options.marker : 'Exit status: ' + result.status)) +
      (options.log ? '\nSee ' + options.log : ''));
  }
  return { elapsed_ms: Date.now() - started, diagnostics: review.diagnostics, output };
}
function verify(godot, options = {}) {
  const directory = options.directory || path.join(root, '.artifacts', 'verify-' + Date.now());
  fs.mkdirSync(directory, { recursive: true });
  const report = { passed: false, suites: [], pending: ['300-node scanner performance target (strict benchmark separate)', 'live Twitch integration', 'OBS recording and listening check'] };
  const save = () => fs.writeFileSync(path.join(directory, 'verification.json'), JSON.stringify(report, null, 2) + '\n');
  function stage(name, args, marker) {
    console.log('Checking ' + name + '...');
    const log = path.join(directory, name + '.log');
    const result = runChecked(godot, [...args, '--log-file', log], { log, marker });
    report.suites.push({ name, passed: true, elapsed_ms: result.elapsed_ms, diagnostics: result.diagnostics, log: path.basename(log) });
    save();
  }
  try {
    const version = runChecked(godot, ['--version']).output.trim();
    if (!/^4\.7\.2\./.test(version)) throw new Error('Use Godot 4.7.2 standard. Found: ' + version);
    report.godot = version;
    stage('import', ['--headless', '--path', root, '--editor', '--import', '--quit']);
    stage('foundation', ['--headless', '--path', root, '--script', 'res://tests/test_foundation.gd'], 'Foundation checks: PASS');
    stage('audio', ['--headless', '--path', root, '--script', 'res://tests/audio/test_audio.gd'], 'Audio checks: PASS');
    stage('music-bus', ['--headless', '--path', root, '--script', 'res://tests/audio/test_music_bus.gd'], 'Music bus checks: PASS');
    stage('panel', ['--headless', '--path', root, '--script', 'res://tests/ui/test_panel.gd'], 'Panel checks: PASS');
    for (const suffix of ['mask', 'engine', 'copy_field', 'engine_churn', 'control_panel', 'draw_tool', 'scan_accuracy']) {
      stage('privacy-' + suffix, ['--headless', '--path', root, '--script', 'res://tests/privacy/test_privacy_' + suffix + '.gd'],
        'Privacy ' + suffix.replaceAll('_', ' ') + ' checks: PASS');
    }
    const independent = path.join(directory, 'signal-garden');
    runChecked(process.execPath, [path.join(root, 'tools', 'prepare_portability_demo.cjs'), independent], {
      log: path.join(directory, 'prepare.log'), marker: 'Verified unchanged addon files:',
    });
    stage('independent-import', ['--headless', '--path', independent, '--editor', '--import', '--quit']);
    stage('independent-game', ['--headless', '--path', independent, '--script', 'res://check_integration.gd'], 'Independent project checks: PASS');
    report.passed = true;
    save();
    console.log('All 12 reviewed suites passed. Report: ' + path.join(directory, 'verification.json'));
    return { directory, report };
  } catch (error) {
    report.error = error.message;
    save();
    throw error;
  }
}
module.exports = { verify, runChecked, inspectOutput };
if (require.main === module) {
  try { verify(process.argv[2] || process.env.GODOT_BIN || 'godot'); }
  catch (error) { console.error(error.message); process.exitCode = 1; }
}
