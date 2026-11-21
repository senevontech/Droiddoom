extends GutTest
## D-035: the Senevon autoload reads the account state from senevon-account.js
## and decides what's unlocked. Outside the web build nothing is connected.

const SIGNED_OUT: String = '{"signedIn":false,"allAccess":false,"owned":[],"tokens":0,"items":[]}'


func after_each() -> void:
	Senevon.apply_state_json(SIGNED_OUT)


func test_not_connected_outside_web() -> void:
	assert_false(Senevon.is_connected_to_senevon(), "no JS bridge in the editor/headless")
	assert_false(Senevon.can_buy(), "no buy buttons outside the web build")


func test_free_items_always_usable() -> void:
	Senevon.apply_state_json(SIGNED_OUT)
	assert_true(Senevon.has_item(""), "an empty id is a free item")
	assert_false(Senevon.has_item("weapon_railgun"), "paid item locked when signed out")


func test_parses_state_and_owned_items() -> void:
	Senevon.apply_state_json(
		(
			'{"signedIn":true,"allAccess":false,"accessReason":null,"tokens":1500,'
			+ '"owned":["weapon_railgun"],'
			+ '"items":[{"id":"weapon_railgun","kind":"dd_weapon","price":2000},'
			+ '{"id":"weapon_rocket_pod","kind":"dd_weapon","price":1500}]}'
		)
	)
	assert_true(Senevon.signed_in)
	assert_eq(Senevon.tokens, 1500)
	assert_eq(Senevon.access_reason, "", "null reason becomes empty")
	assert_true(Senevon.has_item("weapon_railgun"), "owned")
	assert_false(Senevon.has_item("weapon_rocket_pod"), "not bought")
	assert_eq(Senevon.price_of("weapon_rocket_pod"), 1500)
	assert_eq(Senevon.price_of("weapon_unknown"), -1, "not for sale")


func test_all_access_unlocks_everything() -> void:
	Senevon.apply_state_json(
		'{"signedIn":true,"allAccess":true,"accessReason":"plus","owned":[],"tokens":0,"items":[]}'
	)
	assert_true(Senevon.is_all_access())
	assert_eq(Senevon.access_reason, "plus")
	assert_true(Senevon.has_item("weapon_grenade_launcher"))


func test_bad_json_is_ignored() -> void:
	Senevon.apply_state_json('{"signedIn":true,"allAccess":true,"owned":[],"items":[]}')
	Senevon.apply_state_json("not json")
	assert_true(Senevon.signed_in, "a broken message doesn't wipe the state")


func test_buy_without_bridge_fails_cleanly() -> void:
	watch_signals(Senevon)
	Senevon.buy("weapon_railgun", "Railgun")
	assert_signal_emitted_with_parameters(
		Senevon, "purchase_finished", ["weapon_railgun", false, "error"]
	)
