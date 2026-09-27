class_name EnemyCombo
extends Resource
## A string of strikes an enemy plays back to back while holding one attack token (the
## Gatekeeper's phase-2 unblockable combo, for example).

@export var strikes: Array[AttackData] = []
