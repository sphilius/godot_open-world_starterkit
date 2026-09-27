extends "res://tests/test_case.gd"
## Data consistency, no world needed. Attack timings must be sane, and the generated animation
## clips must match them (a stale rig build fails here: re-run tools/build_placeholder_rigs.gd).

const COMBO := [
	"res://resources/combat/attack_1.tres",
	"res://resources/combat/attack_2.tres",
	"res://resources/combat/attack_3.tres",
	"res://resources/combat/heavy_1.tres",
	"res://resources/combat/heavy_2.tres",
	"res://resources/combat/heavy_finisher.tres",
	"res://resources/combat/draw_attack.tres",
	"res://resources/combat/execution.tres",
]
## Humanoid enemy strikes (M6) and their shared clip library.
const ENEMY_ATTACKS := [
	"res://resources/combat/enemies/grunt_slash.tres",
	"res://resources/combat/enemies/grunt_cut.tres",
	"res://resources/combat/enemies/brute_slam.tres",
	"res://resources/combat/enemies/brute_sweep.tres",
	"res://resources/combat/enemies/brute_thrust.tres",
	"res://resources/combat/enemies/gatekeeper_red_sweep.tres",
]
const ENEMY_CLIPS := "res://assets/characters/enemy/enemy_animations.tres"
const ENEMY_SCENES := ["res://scenes/mobs/enemy_grunt.tscn", "res://scenes/mobs/enemy_brute.tscn",
		"res://scenes/mobs/enemy_gatekeeper.tscn"]
const DODGES := ["dodge_f", "dodge_b", "dodge_l", "dodge_r"]
## Guard and hit-reaction clips (M5); every stagger type's clip must be among them.
const DEFENSE_CLIPS := ["guard_idle", "guard_hit", "parry_1", "parry_2",
		"hurt_f", "hurt_b", "hurt_l", "hurt_r", "hurt_heavy", "knockdown", "guard_break"]
const PLAYER_SCENE := "res://scenes/player/player.tscn"
const SWORD_COMBO := "res://resources/combat/sword_combo.tres"
const WOLF_BITE := "res://resources/combat/wolf_bite.tres"
const SAMURAI_CLIPS := "res://assets/characters/samurai/samurai_animations.tres"
const WOLF_CLIPS := "res://assets/characters/wolf/wolf_animations.tres"
const SAMURAI_STATE_MACHINE := "res://assets/characters/samurai/samurai_state_machine.tres"


func test_attack_timings_are_consistent() -> void:
	for path: String in COMBO + ENEMY_ATTACKS + [WOLF_BITE]:
		var attack := load(path) as AttackData
		var file := path.get_file()
		# The execution deals its damage through execute(), not a hitbox.
		check(attack.damage > 0.0 or file == "execution.tres", "%s: damage must be positive" % file)
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
	for clip: String in ["idle", "run", "death"] + DEFENSE_CLIPS:
		check(samurai.has_animation(clip), "samurai clip '%s' is missing" % clip)
	for type: StringName in CombatStateMachine.STAGGER_CLIPS:
		check(String(CombatStateMachine.stagger_clip(type)) in DEFENSE_CLIPS, "stagger '%s' has no clip" % type)
	var fsm := CombatStateMachine.new()
	for clip: String in DODGES:
		if check(samurai.has_animation(clip), "samurai clip '%s' is missing" % clip):
			check(is_equal_approx(samurai.get_animation(clip).length, fsm.dodge_duration),
					"clip '%s' doesn't match CombatStateMachine.dodge_duration (rebuild the rigs)" % clip)
	fsm.free()

	var wolf_clips := load(WOLF_CLIPS) as AnimationLibrary
	for clip: String in ["idle", "walk", "run", "bite", "hurt", "death"]:
		check(wolf_clips.has_animation(clip), "wolf clip '%s' is missing" % clip)
	var bite := load(WOLF_BITE) as AttackData
	if wolf_clips.has_animation(bite.animation):
		check(is_equal_approx(wolf_clips.get_animation(bite.animation).length, bite.duration),
				"wolf bite clip length doesn't match wolf_bite.tres (rebuild the rigs)")


func test_state_machine_has_every_combat_state() -> void:
	var machine := load(SAMURAI_STATE_MACHINE) as AnimationNodeStateMachine
	var states: Array[String] = ["idle", "run", "death"]
	states.append_array(DEFENSE_CLIPS)
	states.append_array(DODGES)
	for path: String in COMBO:
		states.append(String((load(path) as AttackData).animation))
	for state in states:
		check(machine.has_node(state), "AnimationTree state '%s' is missing" % state)


func test_combo_graph_is_playable() -> void:
	var graph := load(SWORD_COMBO) as ComboGraph
	var samurai := load(SAMURAI_CLIPS) as AnimationLibrary
	check(graph.root != null and graph.draw_root != null, "sword_combo needs both roots")
	var seen := {}
	var queue: Array[ComboNode] = [graph.root, graph.draw_root]
	while not queue.is_empty():
		var node: ComboNode = queue.pop_back()
		if node == null or seen.has(node):
			continue
		seen[node] = true
		if node.attack:
			check(samurai.has_animation(node.attack.animation), "combo strike '%s' has no clip" % node.attack.animation)
			for action in node.attack.cancel_into:
				check(action in CombatStateMachine.ALL_ACTIONS, "%s cancels into unknown action '%s'" % [node.attack.animation, action])
		for action: StringName in node.next:
			check(action == ComboManager.LIGHT or action == ComboManager.HEAVY, "unknown combo action '%s'" % action)
			check(node.follow(action) != null, "branch '%s' isn't a ComboNode" % action)
			queue.append(node.follow(action))
	check(seen.size() >= 9, "combo graph looks truncated (%d nodes)" % seen.size())


func test_enemy_clips_match_their_attacks_and_reactions() -> void:
	var clips := load(ENEMY_CLIPS) as AnimationLibrary
	for path: String in ENEMY_ATTACKS:
		var attack := load(path) as AttackData
		if check(clips.has_animation(attack.animation), "enemy clip '%s' is missing" % attack.animation):
			check(is_equal_approx(clips.get_animation(attack.animation).length, attack.duration),
					"enemy clip '%s' doesn't match %s (rebuild the rigs)" % [attack.animation, path.get_file()])
		check(attack.active_start >= 0.4, "%s: the wind-up is shorter than the 0.4 s glint lead" % path.get_file())
	for clip: StringName in EnemyCombatController.STAGGER_CLIPS.values():
		check(clips.has_animation(clip), "enemy reaction clip '%s' is missing" % clip)
	for clip: String in ["idle", "walk", "run", "strafe_l", "strafe_r", "death"]:
		check(clips.has_animation(clip), "enemy clip '%s' is missing" % clip)
	for path: String in ENEMY_SCENES:
		var enemy := (load(path) as PackedScene).instantiate() as EnemyCombatController
		check(not enemy.attacks.is_empty(), "%s has no attacks" % path.get_file())
		for attack in enemy.attacks:
			check(clips.has_animation(attack.animation), "%s: no clip for '%s'" % [path.get_file(), attack.animation])
		enemy.free()
