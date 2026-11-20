extends GutTest
## P1-06: StateMachine enter/exit order, transitions from inside update, ticks.


class LogState:
	extends State
	var label: String
	var log: Array[String]
	var next: StringName = &""
	var ticks: int = 0

	func _init(p_label: String, p_log: Array[String]) -> void:
		label = p_label
		log = p_log

	func enter(previous: StringName) -> void:
		log.append("enter %s from %s" % [label, previous])

	func exit(next_state: StringName) -> void:
		log.append("exit %s to %s" % [label, next_state])

	func update(_delta: float) -> void:
		ticks += 1
		if next != &"":
			machine.change(next)


var _log: Array[String] = []
var _machine: StateMachine
var _idle: LogState
var _chase: LogState


func before_each() -> void:
	_log.clear()
	_machine = StateMachine.new(self)
	_idle = _machine.add(&"idle", LogState.new("idle", _log)) as LogState
	_chase = _machine.add(&"chase", LogState.new("chase", _log)) as LogState


func test_states_get_machine_and_actor() -> void:
	assert_eq(_idle.machine, _machine)
	assert_eq(_idle.actor, self)


func test_start_enters_first_state() -> void:
	_machine.start(&"idle")
	assert_eq(_machine.get_current(), &"idle")
	assert_eq(_log, ["enter idle from "] as Array[String])


func test_change_exits_then_enters_and_emits() -> void:
	_machine.start(&"idle")
	watch_signals(_machine)
	_machine.change(&"chase")
	assert_eq(
		_log, ["enter idle from ", "exit idle to chase", "enter chase from idle"] as Array[String]
	)
	assert_signal_emitted_with_parameters(_machine, "state_changed", [&"idle", &"chase"])


func test_change_to_same_state_is_ignored() -> void:
	_machine.start(&"idle")
	_machine.change(&"idle")
	assert_eq(_log.size(), 1)


func test_transition_requested_inside_update() -> void:
	_machine.start(&"idle")
	_idle.next = &"chase"
	_machine.update(0.1)
	assert_eq(_machine.get_current(), &"chase")
	_machine.update(0.1)
	assert_eq(_chase.ticks, 1, "only the new state ticks next time")
	assert_eq(_idle.ticks, 1)


func test_machine_and_states_are_freed_when_dropped() -> void:
	# Regression (P1-08): State -> machine was a strong reference, a RefCounted
	# cycle that leaked one brain per dead enemy.
	var machine: StateMachine = StateMachine.new()
	var state: State = State.new()
	machine.add(&"a", state)
	machine.start(&"a")
	assert_eq(state.machine, machine, "the state still reaches its machine")
	var machine_ref: WeakRef = weakref(machine)
	var state_ref: WeakRef = weakref(state)
	machine = null
	state = null
	assert_null(machine_ref.get_ref(), "machine freed")
	assert_null(state_ref.get_ref(), "state freed")
