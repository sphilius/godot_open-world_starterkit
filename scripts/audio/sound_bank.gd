class_name SoundBank
extends Resource
## Event name → sound. Each entry is usually an AudioStreamRandomizer holding the variants (so
## repeats vary in take and pitch). Swapping the placeholder audio for sourced audio means
## pointing these entries at the new files; the event names stay the same.
##
## Events: whoosh_light, whoosh_heavy, hit, hit_heavy, block, parry, posture_break,
## step_grass, step_gravel, step_stone, step_wood, glint_gold, glint_red, shrine_ignite, gate, roar,
## ui_confirm, ui_back.

@export var sounds: Dictionary[StringName, AudioStream] = {}


func get_sound(event: StringName) -> AudioStream:
	return sounds.get(event)


func has_sound(event: StringName) -> bool:
	return sounds.has(event)
