extends GutTest
## D-035: HOLLOW can't equip paid weapons (Railgun, Rocket Pod, Grenade
## Launcher) until Senevon says they're unlocked, and re-checks when the
## account state changes (sign-in, purchase, Plus ending).

const HOLLOW: String = "res://actors/player/hollow.tscn"
const SIGNED_OUT: String = '{"signedIn":false,"allAccess":false,"owned":[],"tokens":0,"items":[]}'
const ALL_ACCESS: String = '{"signedIn":true,"allAccess":true,"owned":[],"tokens":0,"items":[]}'
const OWNS_RAILGUN: String = '{"signedIn":true,"owned":["weapon_railgun"],"items":[]}'

var _hollow: Hollow


func before_each() -> void:
	Senevon.apply_state_json(SIGNED_OUT)
	var root: Node3D = Node3D.new()
	add_child_autofree(root)
	root.add_child(ProjectileSystem.new())
	root.add_child(CombatFX.new())
	_hollow = (load(HOLLOW) as PackedScene).instantiate()
	root.add_child(_hollow)


func after_each() -> void:
	Senevon.apply_state_json(SIGNED_OUT)


func test_signed_out_gets_free_weapons_only() -> void:
	assert_eq(_hollow.weapon.data.unlock_id, "", "starts with a free primary")
	assert_null(_hollow.heavy_weapon, "both heavies are paid")
	var railgun: int = _index_of(&"weapon_railgun")
	assert_gt(railgun, -1, "the railgun is in the loadout")
	_hollow.select_primary(railgun)
	assert_ne(_hollow.weapon.data.unlock_id, "weapon_railgun", "locked: can't select it")


func test_cycling_skips_locked_weapons() -> void:
	for i: int in 8:
		_hollow.select_primary(
			_hollow._next_unlocked_index(_hollow.get_primaries(), _hollow.weapon, 1)
		)
		assert_eq(_hollow.weapon.data.unlock_id, "", "never lands on a paid weapon")


func test_buying_unlocks_and_losing_access_swaps_back() -> void:
	Senevon.apply_state_json(OWNS_RAILGUN)
	_hollow.select_primary(_index_of(&"weapon_railgun"))
	assert_eq(_hollow.weapon.data.unlock_id, "weapon_railgun", "owned: selectable")
	Senevon.apply_state_json(SIGNED_OUT)  # signed out / refunded
	assert_eq(_hollow.weapon.data.unlock_id, "", "swapped to a free weapon")


func test_all_access_equips_a_heavy() -> void:
	watch_signals(_hollow)
	Senevon.apply_state_json(ALL_ACCESS)
	assert_not_null(_hollow.heavy_weapon, "Plus: a heavy weapon is equipped")
	assert_signal_emitted(_hollow, "weapons_changed")


func test_ignore_unlocks_for_benchmark() -> void:
	_hollow.ignore_unlocks = true
	_hollow.refresh_unlocks()
	assert_not_null(_hollow.heavy_weapon)
	_hollow.select_primary(_index_of(&"weapon_railgun"))
	assert_eq(_hollow.weapon.data.unlock_id, "weapon_railgun")


func _index_of(unlock_id: StringName) -> int:
	var guns: Array[Weapon] = _hollow.get_primaries()
	for i: int in guns.size():
		if guns[i].data.unlock_id == unlock_id:
			return i
	return -1
