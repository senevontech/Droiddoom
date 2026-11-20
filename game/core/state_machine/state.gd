class_name State
extends RefCounted
## One state of a StateMachine. Override what you need. States are plain
## objects (not nodes), so dozens of enemies stay cheap, and the owner decides
## how often to tick (AI LOD, P1-08).
##
## The link back to the machine is a weak reference: the machine owns its
## states, and a strong reference both ways would be a RefCounted cycle that
## is never freed (one leaked brain per dead enemy).

## The machine running this state. Set by `StateMachine.add()`.
var machine: StateMachine:
	get:
		return _machine_ref.get_ref() as StateMachine if _machine_ref != null else null
	set(value):
		_machine_ref = weakref(value) if value != null else null
## The actor the machine belongs to.
var actor: Node

var _machine_ref: WeakRef


func enter(_previous: StringName) -> void:
	pass


func exit(_next: StringName) -> void:
	pass


## Called by `StateMachine.update()` at the owner's AI tick rate.
func update(_delta: float) -> void:
	pass
