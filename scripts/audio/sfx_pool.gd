class_name SfxPool
extends Node3D
## Plays SoundBank events (M9b). A fixed pool of positional voices on the SFX bus, so impacts
## don't cut each other off; when every voice is busy, the one that started longest ago is
## stolen. play_2d() is for UI sounds: a non-positional player on the UI bus that keeps working
## while the tree is paused. One per scene (group "sfx_pool", SfxPool.find()).

@export var bank: SoundBank
@export var voices := 8
@export var bus := &"SFX"
@export var ui_bus := &"UI"
## AudioStreamPlayer3D attenuation.
@export var unit_size := 8.0
@export var max_distance := 70.0

var _voices: Array[AudioStreamPlayer3D] = []
var _started_msec: Array[int] = []
var _ui: AudioStreamPlayer


func _ready() -> void:
	add_to_group(&"sfx_pool")
	for i in voices:
		var voice := AudioStreamPlayer3D.new()
		voice.name = "Voice%d" % i
		voice.bus = bus
		voice.unit_size = unit_size
		voice.max_distance = max_distance
		voice.top_level = true
		add_child(voice)
		_voices.append(voice)
		_started_msec.append(0)
	_ui = AudioStreamPlayer.new()
	_ui.name = "UI"
	_ui.bus = ui_bus
	_ui.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_ui)


## The SfxPool in `tree`'s scene, or null.
static func find(tree: SceneTree) -> SfxPool:
	return tree.get_first_node_in_group(&"sfx_pool") as SfxPool if tree else null


## Plays `event` at `at`. Returns the voice used, or null when the bank has no such event.
func play(event: StringName, at: Vector3, volume_db := 0.0, pitch := 1.0) -> AudioStreamPlayer3D:
	var stream := bank.get_sound(event) if bank else null
	if stream == null:
		return null
	var index := _free_voice()
	var voice := _voices[index]
	voice.stream = stream
	voice.volume_db = volume_db
	voice.pitch_scale = pitch
	voice.global_position = at
	voice.play()
	_started_msec[index] = Time.get_ticks_msec()
	return voice


## Plays `event` without position on the UI bus (menus; works while paused).
func play_2d(event: StringName, volume_db := 0.0) -> void:
	var stream := bank.get_sound(event) if bank else null
	if stream == null:
		return
	_ui.stream = stream
	_ui.volume_db = volume_db
	_ui.play()


## Voices currently playing.
func busy_voices() -> int:
	return _voices.filter(func(voice: AudioStreamPlayer3D) -> bool: return voice.playing).size()


func _free_voice() -> int:
	var oldest := 0
	for i in _voices.size():
		if not _voices[i].playing:
			return i
		if _started_msec[i] < _started_msec[oldest]:
			oldest = i
	return oldest                                            # every voice is busy: steal the oldest
