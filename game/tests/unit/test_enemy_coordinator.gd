extends GutTest
## P1-08: EnemyCoordinator time slicing (budget, order, de-duplication,
## freed requesters) and the live enemy count.


class FakeRequester:
	extends RefCounted
	var label: String
	var log: Array[String]

	func _init(p_label: String, p_log: Array[String]) -> void:
		label = p_label
		log = p_log

	func run_path_query() -> void:
		log.append(label)


var _coord: EnemyCoordinator
var _log: Array[String] = []


func before_each() -> void:
	_log = []
	_coord = EnemyCoordinator.new()
	_coord.budget_override = 0  # keep its own physics tick from draining the queue
	add_child_autofree(_coord)


func test_runs_at_most_budget_per_call_oldest_first() -> void:
	var reqs: Array[FakeRequester] = []
	for label: String in ["a", "b", "c", "d", "e"]:
		var r: FakeRequester = FakeRequester.new(label, _log)
		reqs.append(r)
		_coord.request_path(r)
	assert_eq(_coord.process_queue(2), 2)
	assert_eq(_log, ["a", "b"] as Array[String])
	assert_eq(_coord.get_pending_count(), 3)
	assert_eq(_coord.process_queue(10), 3, "only what's left runs")
	assert_eq(_log, ["a", "b", "c", "d", "e"] as Array[String])


func test_same_requester_is_queued_once() -> void:
	var r: FakeRequester = FakeRequester.new("a", _log)
	_coord.request_path(r)
	_coord.request_path(r)
	_coord.request_path(r)
	assert_eq(_coord.get_pending_count(), 1)
	_coord.process_queue(5)
	assert_eq(_log.size(), 1)
	_coord.request_path(r)
	assert_eq(_coord.get_pending_count(), 1, "can queue again after its query ran")


func test_freed_requester_is_skipped_and_costs_no_budget() -> void:
	var gone: Node = Node.new()
	_coord.request_path(gone)
	gone.free()
	var r: FakeRequester = FakeRequester.new("alive", _log)
	_coord.request_path(r)
	assert_eq(_coord.process_queue(1), 1)
	assert_eq(_log, ["alive"] as Array[String], "the freed one didn't use the budget")


func test_physics_tick_uses_budget() -> void:
	# Keep references: the coordinator stores ids only and never keeps requesters alive.
	var reqs: Array[FakeRequester] = []
	for i in 6:
		reqs.append(FakeRequester.new(str(i), _log))
		_coord.request_path(reqs[i])
	_coord.budget_override = 4
	await wait_physics_frames(1)
	assert_eq(_log.size(), 4, "4 per physics frame")
	assert_eq(_coord.get_queries_last_frame(), 4)
	await wait_physics_frames(1)
	assert_eq(_log.size(), 6)


func test_live_enemy_count() -> void:
	var a: Node = autofree(Node.new())
	var b: Node = autofree(Node.new())
	_coord.register_enemy(a)
	_coord.register_enemy(b)
	_coord.register_enemy(a)
	assert_eq(_coord.get_live_count(), 2)
	_coord.unregister_enemy(a)
	assert_eq(_coord.get_live_count(), 1)


func test_find_or_create_returns_existing() -> void:
	assert_eq(EnemyCoordinator.find_or_create(self), _coord)


func test_separation_pushes_away_from_close_neighbours_only() -> void:
	var coord: EnemyCoordinator = EnemyCoordinator.new()
	add_child_autofree(coord)
	var me: Node3D = _body(Vector3.ZERO)
	var near: Node3D = _body(Vector3(0.5, 0.0, 0.0))
	var far: Node3D = _body(Vector3(-5.0, 0.0, 0.0))
	for n: Node3D in [me, near, far]:
		coord.register_enemy(n)
	var push: Vector3 = coord.separation_for(me, 1.0)
	assert_lt(push.x, -0.4, "pushed away from the near one")
	assert_almost_eq(push.z, 0.0, 0.0001)
	assert_eq(coord.separation_for(far, 1.0), Vector3.ZERO, "nobody close")


func _body(pos: Vector3) -> Node3D:
	var n: Node3D = Node3D.new()
	n.position = pos
	add_child_autofree(n)
	return n
