class_name MusicDirector
extends Node
## Music, ambience and reverb per beat (M9b), driven by GameManager.state_changed.
##
##   START_MENU, EXPLORATION → `exploration` (none yet: the valley has only its wind)
##   COURTYARD_AMBUSH        → `combat`
##   SANCTUM_GATEKEEPER      → `boss`
##   VICTORY_SCREEN          → `victory` (plays once)
## Cues cross-fade over `crossfade_time` on the Music bus. `ambience` loops on the Ambience bus
## throughout. The SFX bus's reverb (default_bus_layout.tres) is on while the player is in the
## night beat (GameManager.beat 2, the sanctum). Runs while the tree is paused, so the title and
## the victory screen keep their sound.

@export var game: GameManager
@export var ambience: AudioStream
@export var exploration: AudioStream
@export var combat: AudioStream
@export var boss: AudioStream
@export var victory: AudioStream
@export var crossfade_time := 1.5
@export var music_db := -8.0
@export var ambience_db := -14.0
@export var music_bus := &"Music"
@export var ambience_bus := &"Ambience"
## The bus whose first effect is the sanctum reverb.
@export var reverb_bus := &"SFX"

## The cue playing (or fading in), or null.
var current: AudioStream
var _players: Array[AudioStreamPlayer] = []
var _active := 0
var _ambience: AudioStreamPlayer
var _fade: Tween


func _ready() -> void:
	# Also set in main.tscn: it has to be ALWAYS before GameManager pauses the tree for the
	# title, or the ambience's playback is left registered when the game quits from there.
	process_mode = Node.PROCESS_MODE_ALWAYS
	for stream in [ambience, exploration, combat, boss]:
		_set_loop(stream)
	for i in 2:
		var player := AudioStreamPlayer.new()
		player.name = "Music%d" % i
		player.bus = music_bus
		player.volume_db = -80.0
		add_child(player)
		_players.append(player)
	_ambience = AudioStreamPlayer.new()
	_ambience.name = "Ambience"
	_ambience.bus = ambience_bus
	_ambience.volume_db = ambience_db
	_ambience.stream = ambience
	add_child(_ambience)
	if ambience:
		_ambience.play()
	if game:
		game.state_changed.connect(_on_state_changed)
		play_cue(cue_for(game.state))
	set_reverb(false)


## The cue for a GameManager state.
func cue_for(state: GameManager.GameState) -> AudioStream:
	match state:
		GameManager.GameState.COURTYARD_AMBUSH:
			return combat
		GameManager.GameState.SANCTUM_GATEKEEPER:
			return boss
		GameManager.GameState.VICTORY_SCREEN:
			return victory
	return exploration


## Cross-fades to `stream` (null fades the music out).
func play_cue(stream: AudioStream) -> void:
	if stream == current:
		return
	current = stream
	var outgoing := _players[_active]
	_active = 1 - _active
	var incoming := _players[_active]
	if _fade and _fade.is_valid():
		_fade.kill()
	_fade = create_tween().set_parallel()
	if outgoing.playing:
		_fade.tween_property(outgoing, ^"volume_db", -80.0, crossfade_time)
		_fade.chain().tween_callback(outgoing.stop)
	if stream:
		incoming.stream = stream
		incoming.volume_db = -40.0
		incoming.play()
		_fade.tween_property(incoming, ^"volume_db", music_db, crossfade_time)


## Turns the sanctum reverb on the SFX bus on or off.
func set_reverb(on: bool) -> void:
	var bus := AudioServer.get_bus_index(reverb_bus)
	if bus >= 0 and AudioServer.get_bus_effect_count(bus) > 0:
		AudioServer.set_bus_effect_enabled(bus, 0, on)


func is_reverb_on() -> bool:
	var bus := AudioServer.get_bus_index(reverb_bus)
	return bus >= 0 and AudioServer.get_bus_effect_count(bus) > 0 and AudioServer.is_bus_effect_enabled(bus, 0)


func _on_state_changed(_previous: GameManager.GameState, state: GameManager.GameState) -> void:
	play_cue(cue_for(state))
	set_reverb(game.beat >= 2)


func _exit_tree() -> void:
	set_reverb(false)                                        # the bus layout outlives the scene
	for player in _players + [_ambience]:
		player.stop()                                        # a playing stream would outlive the quit
		player.stream = null


static func _set_loop(stream: AudioStream) -> void:
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	elif stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
		(stream as AudioStreamWAV).loop_end = int((stream as AudioStreamWAV).get_length() * (stream as AudioStreamWAV).mix_rate)

