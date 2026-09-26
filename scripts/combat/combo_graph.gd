class_name ComboGraph
extends Resource
## A weapon's whole move list: the neutral openers and the quick-draw openers used while the
## weapon is sheathed. Both roots live in one resource so their branches can share nodes.

@export var root: ComboNode
## Openers when attacking from sheathed (null = use `root`).
@export var draw_root: ComboNode
