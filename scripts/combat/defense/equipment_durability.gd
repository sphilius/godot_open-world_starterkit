class_name EquipmentDurability
extends Node
## Weapon and armour integrity (Phase C, decisions D17 and D18: sword-only, no shield).
##
## Blocked hits are absorbed by the gear (GuardComponent calls absorb() with the hit's damage):
## the weapon takes `weapon_share`, the armour the rest. Gear that runs out of integrity cracks
## (item_cracked). Each cracked item halves blocking: block_effectiveness() is 1, 0.5 or 0.25,
## and GuardComponent lets the missing share through as chip damage and multiplies the posture
## damage by its inverse. Cracked gear stays cracked until repair() (a checkpoint shrine; a
## blacksmith comes after the slice).

signal item_cracked(item: StringName)
signal integrity_changed
signal repaired

const WEAPON := &"weapon"
const ARMOR := &"armor"

@export var weapon_integrity := 100.0
@export var armor_integrity := 140.0
## Share of a blocked hit's damage the weapon absorbs; the armour takes the rest.
@export_range(0.0, 1.0) var weapon_share := 0.5
## Multiplies the damage absorbed (tuning: higher wears gear out faster).
@export var wear_scale := 1.0

var weapon := 0.0
var armor := 0.0


func _ready() -> void:
	weapon = weapon_integrity
	armor = armor_integrity


## Spreads `damage` over the weapon and the armour; cracked gear absorbs nothing more.
func absorb(damage: float) -> void:
	var amount := damage * wear_scale
	if amount <= 0.0:
		return
	var weapon_part := amount * weapon_share if weapon > 0.0 else 0.0
	var armor_part := amount - weapon_part if armor > 0.0 else 0.0
	if weapon > 0.0:
		weapon = maxf(weapon - weapon_part, 0.0)
		if weapon <= 0.0:
			item_cracked.emit(WEAPON)
	if armor > 0.0:
		armor = maxf(armor - armor_part, 0.0)
		if armor <= 0.0:
			item_cracked.emit(ARMOR)
	integrity_changed.emit()


func is_cracked(item: StringName) -> bool:
	return (weapon if item == WEAPON else armor) <= 0.0


## 1 with sound gear, halved for each cracked item.
func block_effectiveness() -> float:
	var effectiveness := 1.0
	for item in [WEAPON, ARMOR]:
		if is_cracked(item):
			effectiveness *= 0.5
	return effectiveness


## Integrity of `item` as a share of its maximum.
func ratio(item: StringName) -> float:
	if item == WEAPON:
		return weapon / weapon_integrity if weapon_integrity > 0.0 else 0.0
	return armor / armor_integrity if armor_integrity > 0.0 else 0.0


## Mends everything (a checkpoint shrine, a respawn, an encounter reset).
func repair() -> void:
	weapon = weapon_integrity
	armor = armor_integrity
	integrity_changed.emit()
	repaired.emit()


static func find_on(node: Node) -> EquipmentDurability:
	if node == null:
		return null
	for child in node.get_children():
		if child is EquipmentDurability:
			return child
	return null
