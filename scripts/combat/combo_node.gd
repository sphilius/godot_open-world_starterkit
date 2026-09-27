class_name ComboNode
extends Resource
## One node of a combo graph. `attack` is the strike this node plays (null for a root), and
## `next` maps an input action (&"attack_light", &"attack_heavy") to the node it chains into.
## A node with no entry for an action ends the chain for that action.

@export var attack: AttackData
## Values are ComboNodes. (Typed as Resource: a script whose container type names itself keeps
## itself alive, which leaks the script at exit.)
@export var next: Dictionary[StringName, Resource] = {}


## The node `action` chains into, or null.
func follow(action: StringName) -> ComboNode:
	return next.get(action) as ComboNode
