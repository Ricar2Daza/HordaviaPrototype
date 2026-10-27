## AudioManager — SFX + música sintetizados al vuelo (roadmap 1.5).
## Autoload. Cero assets binarios: todas las ondas se generan aquí en _ready
## (licencias limpias: contenido propio). Buses SFX/Music para opciones futuras.
extends Node

const RATE := 22050
const POOL_SIZE := 12

var _players: Array[AudioStreamPlayer] = []
var _next_player := 0
var _streams := {}   # nombre -> AudioStreamWAV
var _music: AudioStreamPlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # la música sigue en pausas (cartas)
	_ensure_bus("SFX")
	_ensure_bus("Music")
	set_music_volume(int(SaveManager.settings.get("music_vol", 70)))
	set_sfx_volume(int(SaveManager.settings.get("sfx_vol", 85)))

	_streams["shoot"] = _tone(0.10, 900.0, 320.0, "square", 0.40)
	_streams["hit"] = _mix(_tone(0.12, 240.0, 80.0, "sine", 0.6), _noise(0.09, 0.35, 0.25))
	_streams["pickup"] = _tone(0.09, 700.0, 1250.0, "sine", 0.45)
	_streams["jump"] = _tone(0.16, 320.0, 700.0, "tri", 0.5)
	_streams["dash"] = _mix(_tone(0.20, 340.0, 110.0, "saw", 0.30), _noise(0.20, 0.30, 0.10))
	_streams["boom"] = _mix(_tone(0.38, 190.0, 50.0, "sine", 0.7), _noise(0.30, 0.45, 0.12))
	_streams["zap"] = _tone(0.12, 1400.0, 220.0, "saw", 0.40)
	_streams["levelup"] = _seq([
		[_tone(0.14, 523.0, 523.0, "tri", 0.5), 0.0],
		[_tone(0.14, 659.0, 659.0, "tri", 0.5), 0.12],
		[_tone(0.30, 784.0, 784.0, "tri", 0.5), 0.24],
	])
	_streams["gameover"] = _seq([
		[_tone(0.26, 392.0, 392.0, "tri", 0.5), 0.0],
		[_tone(0.26, 311.0, 311.0, "tri", 0.5), 0.28],
		[_tone(0.50, 233.0, 180.0, "tri", 0.55), 0.56],
	])

	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_players.append(p)

	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	_music.volume_db = -14.0
	_music.stream = _build_music()
	add_child(_music)
	_music.play()


func play_sfx(sfx_name: String, pitch: float = 1.0) -> void:
	if not _streams.has(sfx_name):
		return
	var now := Time.get_ticks_msec()
	if now - _last_play < 25:
		return
	_last_play = now
	var p := _players[_next_player]
	_next_player = (_next_player + 1) % POOL_SIZE
	p.stream = _streams[sfx_name]
	p.pitch_scale = clampf(pitch, 0.3, 3.0)
	p.play()

var _last_play := 0


# ---------------- síntesis ----------------

func _tone(dur: float, f0: float, f1: float, wave: String, vol: float) -> AudioStreamWAV:
	return _stream_from(_tone_buf(dur, f0, f1, wave, vol))


func _tone_buf(dur: float, f0: float, f1: float, wave: String, vol: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var ph := 0.0
	for i in n:
		var pr := float(i) / float(maxi(n, 1))
		var f := f0 + (f1 - f0) * pr
		ph += TAU * f / float(RATE)
		var s := 0.0
		match wave:
			"square":
				s = 1.0 if sin(ph) >= 0.0 else -1.0
			"saw":
				s = fmod(ph / TAU, 1.0) * 2.0 - 1.0
			"tri":
				s = 2.0 * absf(2.0 * fmod(ph / TAU, 1.0) - 1.0) - 1.0
			_:
				s = sin(ph)
		var env := pow(1.0 - pr, 1.5)
		if pr < 0.012:
			env = pr / 0.012
		buf[i] = s * env * vol
	return buf


func _noise(dur: float, vol: float, smooth: float) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var lp := 0.0
	for i in n:
		var x := randf_range(-1.0, 1.0)
		lp += smooth * (x - lp)
		var pr := float(i) / float(maxi(n, 1))
		buf[i] = lp * vol * pow(1.0 - pr, 1.2)
	return _stream_from(buf)


func _mix(a: AudioStreamWAV, b: AudioStreamWAV) -> AudioStreamWAV:
	var merged := _mix_buf(_wav_to_buf(a), _wav_to_buf(b))
	return _stream_from(merged)


func _wav_to_buf(s: AudioStreamWAV) -> PackedFloat32Array:
	var data := s.data
	var n := data.size() / 2
	var buf := PackedFloat32Array()
	buf.resize(n)
	for i in n:
		buf[i] = float(data.decode_s16(i * 2)) / 32000.0
	return buf


func _mix_buf(a: PackedFloat32Array, b: PackedFloat32Array) -> PackedFloat32Array:
	var n := maxi(a.size(), b.size())
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var va := a[i] if i < a.size() else 0.0
		var vb := b[i] if i < b.size() else 0.0
		out[i] = clampf(va + vb, -1.0, 1.0)
	return out


func _seq(items: Array) -> AudioStreamWAV:
	var n := 0
	for it in items:
		var off := int(float(it[1]) * RATE)
		var buf := _wav_to_buf(it[0])
		n = maxi(n, off + buf.size())
	var merged := PackedFloat32Array()
	merged.resize(n)
	for it in items:
		var off := int(float(it[1]) * RATE)
		var buf := _wav_to_buf(it[0])
		for j in buf.size():
			var idx := off + j
			merged[idx] = clampf(merged[idx] + buf[j], -1.0, 1.0)
	return _stream_from(merged)


# ---------------- música: loop ambient-synth ----------------

func _build_music() -> AudioStreamWAV:
	var bpm := 96.0
	var beat := 60.0 / bpm
	var bars := 8
	var n := int(beat * 4.0 * float(bars) * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)

	# Progresión A menor: Am - F - C - G (frecuencias base)
	var chords := [
		[110.0, 164.8, 220.0],   # Am
		[87.3, 130.8, 174.6],    # F
		[65.4, 130.8, 196.0],    # C
		[98.0, 146.8, 196.0],    # G
	]
	var arp_seq := [0, 1, 2, 1, 0, 2, 1, 2]
	var eighth := beat * 0.5

	for bar in bars:
		var chord: Array = chords[bar % chords.size()]
		var bar_start := float(bar) * beat * 4.0
		# bajo: una nota por beat (triangle, root)
		for b in 4:
			_add_into(buf, _tone_buf(0.45, chord[0] * 0.5, chord[0] * 0.5, "tri", 0.28),
				int((bar_start + beat * float(b)) * RATE))
		# arpegio de octavos
		for e in 8:
			var note := float(chord[arp_seq[e % arp_seq.size()]])
			_add_into(buf, _tone_buf(0.22, note * 2.0, note * 2.0, "sine", 0.14),
				int((bar_start + eighth * float(e)) * RATE))
		# kick en beats 1 y 3, hat en offbeats
		for b in [0, 2]:
			_add_into(buf, _tone_buf(0.11, 55.0, 40.0, "sine", 0.42),
				int((bar_start + beat * float(b)) * RATE))
		for e in range(1, 8, 2):
			_add_into(buf, _noise_buf(0.035, 0.08, 0.5),
				int((bar_start + eighth * float(e)) * RATE))
	return _stream_from(buf, true)


func _noise_buf(dur: float, vol: float, smooth: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var lp := 0.0
	for i in n:
		var x := randf_range(-1.0, 1.0)
		lp += smooth * (x - lp)
		var pr := float(i) / float(maxi(n, 1))
		buf[i] = lp * vol * pow(1.0 - pr, 1.2)
	return buf


func _add_into(buf: PackedFloat32Array, samples: PackedFloat32Array, start: int) -> void:
	for j in samples.size():
		var idx := start + j
		if idx >= buf.size():
			break
		buf[idx] = clampf(buf[idx] + samples[j], -1.0, 1.0)


# ---------------- infraestructura ----------------

func _stream_from(buf: PackedFloat32Array, loop: bool = false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(buf.size() * 2)
	for i in buf.size():
		var v := int(clampf(buf[i], -1.0, 1.0) * 32000.0)
		bytes.encode_s16(i * 2, v)
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = bytes
	if loop:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = buf.size()
	return s


func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) == -1:
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, bus_name)
		AudioServer.set_bus_send(i, "Master")


func set_music_volume(v: int) -> void:
	_set_bus_volume("Music", v)


func set_sfx_volume(v: int) -> void:
	_set_bus_volume("SFX", v)


func _set_bus_volume(bus_name: String, v: int) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	var clamped := clampi(v, 0, 100)
	AudioServer.set_bus_mute(idx, clamped <= 0)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(float(clamped) / 100.0, 0.0001)))
