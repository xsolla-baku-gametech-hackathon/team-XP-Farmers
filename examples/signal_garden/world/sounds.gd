extends RefCounted
## Host-owned procedural sounds. No files from the first demo are used.

const RATE: int = 22050


static func melody(replacement: bool) -> AudioStreamWAV:
	var notes := PackedFloat64Array([261.63, 329.63, 392.0, 523.25] if replacement else [220.0, 261.63, 329.63, 293.66, 220.0, 392.0, 329.63, 261.63])
	var seconds := 4.0
	var count := int(seconds * RATE)
	var data := PackedByteArray()
	data.resize(count * 2)
	var note_length := seconds / notes.size()
	for index in range(count):
		var time := float(index) / RATE
		var note_index := mini(int(time / note_length), notes.size() - 1)
		var local := fmod(time, note_length)
		var envelope := minf(1.0, local / 0.02) * exp(-local * (3.0 if replacement else 6.0))
		var sample := sin(TAU * notes[note_index] * time) * envelope * 0.25
		data.encode_s16(index * 2, int(sample * 32767.0))
	return _stream(data, true)


static func chime() -> AudioStreamWAV:
	var count := int(RATE * 0.15)
	var data := PackedByteArray()
	data.resize(count * 2)
	for index in range(count):
		var time := float(index) / RATE
		var envelope := minf(1.0, time / 0.005) * exp(-time * 30.0)
		data.encode_s16(index * 2, int(sin(TAU * 880.0 * time) * envelope * 4500))
	return _stream(data, false)


static func _stream(data: PackedByteArray, loop: bool) -> AudioStreamWAV:
	var result := AudioStreamWAV.new()
	result.mix_rate = RATE
	result.format = AudioStreamWAV.FORMAT_16_BITS
	result.data = data
	if loop:
		result.loop_mode = AudioStreamWAV.LOOP_FORWARD
		result.loop_end = data.size() / 2
	return result
