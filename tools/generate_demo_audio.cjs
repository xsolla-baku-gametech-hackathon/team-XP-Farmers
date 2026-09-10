// Deterministic synthesized demo sounds; no recordings, samples or external packages.
// Run with Node.js: node tools/generate_demo_audio.cjs
const fs = require('node:fs');
const path = require('node:path');
const rate = 22050;
const dir = path.join(__dirname, '../demo/assets/audio');
fs.mkdirSync(dir, { recursive: true });
const hz = midi => 440 * Math.pow(2, (midi - 69) / 12);
const sine = (f, t) => Math.sin(2 * Math.PI * f * t);
function write(name, duration, sample) {
  const count = Math.round(rate * duration);
  const buffer = Buffer.alloc(44 + count * 2);
  buffer.write('RIFF', 0); buffer.writeUInt32LE(36 + count * 2, 4);
  buffer.write('WAVEfmt ', 8); buffer.writeUInt32LE(16, 16);
  buffer.writeUInt16LE(1, 20); buffer.writeUInt16LE(1, 22);
  buffer.writeUInt32LE(rate, 24); buffer.writeUInt32LE(rate * 2, 28);
  buffer.writeUInt16LE(2, 32); buffer.writeUInt16LE(16, 34);
  buffer.write('data', 36); buffer.writeUInt32LE(count * 2, 40);
  for (let i = 0; i < count; i++) {
    const value = Math.max(-0.9, Math.min(0.9, sample(i / rate)));
    buffer.writeInt16LE(Math.round(value * 32767), 44 + i * 2);
  }
  fs.writeFileSync(path.join(dir, name + '.wav'), buffer);
}
const lead = [64, 67, 71, 76, 71, 67, 62, 67, 60, 64, 67, 72, 67, 64, 62, 59];
write('neon_run', 8, t => {
  const step = Math.floor(t / 0.25);
  const local = t % 0.25;
  const f = hz(lead[step % lead.length]);
  const env = Math.min(1, local / 0.008) * Math.exp(-local * 10);
  const melody = (sine(f, t) + 0.24 * sine(f * 2, t)) * env * 0.25;
  const bass = sine(hz([40, 43, 36, 38][Math.floor(t / 2)]), t) * 0.13;
  const beat = t % 0.5;
  const kick = sine(65, beat) * Math.exp(-beat * 35) * 0.2;
  return (melody + bass + kick) * Math.min(1, t / 0.01, (8 - t) / 0.01);
});
const chords = [[60, 64, 67, 71], [57, 60, 64, 67], [53, 57, 60, 64], [55, 59, 62, 67]];
write('quiet_orbit', 12, t => {
  const chord = chords[Math.floor(t / 3)];
  const segment = t % 3;
  const envelope = Math.min(1, segment / 0.1, (3 - segment) / 0.18);
  let value = chord.reduce((sum, note) => sum + sine(hz(note), t) * 0.055, 0) * envelope;
  const local = t % 0.5;
  const note = chord[Math.floor(segment / 0.5) % 4] + 12;
  value += sine(hz(note), t) * Math.exp(-local * 8) * Math.min(1, local / 0.01) * 0.13;
  return value;
});
write('collect', 0.22, t => {
  const f = t < 0.08 ? hz(83) : hz(88);
  return sine(f, t) * Math.exp(-t * 16) * Math.min(1, t / 0.003) * Math.min(1, (0.22 - t) / 0.01) * 0.45;
});
console.log('Generated 3 mono PCM demo sounds at ' + rate + ' Hz.');
