extends "res://tests/test_case.gd"
## Data consistency, no world needed. Attack timings must be sane, and the generated animation
## clips must match them (a stale rig build fails here: re-run tools/build_placeholder_rigs.gd).

const COMBO := [
	"res://resources/combat/attack_1.tres",
	"res://resources/combat/attack_2.tres",
	"res://resources/combat/attack_3.tres",
]
const WOLF_BITE := "res://resources/combat/wolf_bite.tres"
const SAMURAI_CLIPS := "res://assets/characters/samurai/samurai_animations.tres"
const WOLF_CLIPS := "res://assets/characters/wolf/wolf_animations.tres"
const SAMURAI_STATE_MACHINE := "res://assets/characters/samurai/samurai_state_machine.tres"


func test_attack_timings_are_consistent() -> void:
	for path: String in COMBO + [WOLF_BITE]:
		var attack := load(path) as AttackData
		var file := path.get_file()
		check(attack.damage > 0.0, "%s: damage must be positive" % file)
		check(attack.active_start < attack.active_end, "%s: active window is empty" % file)
		check(attack.active_end <= attack.duration, "%s: active window runs past the end" % file)
		check(attack.lunge_delay + attack.lunge_duration <= attack.duration, "%s: lunge runs past the end" % file)


func test_clips_match_their_attack_data() -> void:
	var samurai := load(SAMURAI_CLIPS) as AnimationLibrary
	for path: String in COMBO:
		var attack := load(path) as AttackData
		if check(samurai.has_animation(attack.animation), "samurai clip '%s' is missing" % attack.animation):
			var length := samurai.get_animation(attack.animation).length
			check(is_equal_approx(length, attack.duration),
					"clip '%s' is %.2f s but %s says %.2f s (rebuild the rigs)" % [attack.animation, length, path.get_file(), attack.duration])
	for clip: String in ["idle", "run", "hurt", "death"]:
		check(samurai.has_animation(clip), "samurai clip '%s' is missing" % clip)

	var wolf_clips := load(WOLF_CLIPS) as AnimationLibrary
	for clip: String in ["idle", "walk", "run", "bite", "hurt", "death"]:
		check(wolf_clips.has_animation(clip), "wolf clip '%s' is missing" % clip)
	var bite := load(WOLF_BITE) as AttackData
	if wolf_clips.has_animation(bite.animation):
		check(is_equal_approx(wolf_clips.get_animation(bite.animation).length, bite.duration),
				"wolf bite clip length doesn't match wolf_bite.tres (rebuild the rigs)")


func test_state_machine_has_every_combat_state() -> void:
	var machine := load(SAMURAI_STATE_MACHINE) as AnimationNodeStateMachine
	for state: String in ["idle", "run", "attack_1", "attack_2", "attack_3", "hurt", "death"]:
		check(machine.has_node(state), "AnimationTree state '%s' is missing" % state)
