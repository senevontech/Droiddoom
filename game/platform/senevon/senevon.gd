extends Node
## Senevon account (D-035): sign-in, unlocks and token purchases. Autoload "Senevon".
## Adapted from Senevon's integrations/droiddoom/senevon.gd (7games repo); keep the JS side
## (platform/web/senevon-account.js) in sync with that repo.
##
##   Senevon.state_changed              → re-check unlocks (sign-in, Plus, a purchase)
##   Senevon.has_item("weapon_railgun") → can the player use it? ("" = free item)
##   Senevon.is_all_access()            → all unlocked (Plus / Pro / unlimited / premium build)
##   Senevon.can_buy()                  → may the game show buy / sign-in buttons?
##   Senevon.buy("weapon_railgun", "Railgun") → purchase box; answer in purchase_finished
##   Senevon.sign_in()                  → "Sign in with Senevon" (leaves the page, comes back)
##   Senevon.open_page("plus")          → "plus" | "tokens": opens Senevon in a new tab
##
## Each build decides by export feature tag:
##   web      → unlocks come from the player's Senevon account (senevon-account.js).
##   premium  → custom tag for paid Steam/desktop presets: everything unlocked.
##   android  → Senevon account later (droiddoom://open#senevon_code=…, Play Billing). Until that
##              exists, paid items stay locked: no buy button, no link to buy elsewhere.
##   other    → only free items (DEV_UNLOCK_ALL can unlock all, editor runs only).
## Only res://platform/ may touch JavaScriptBridge (AGENTS.md rule 4).

signal state_changed
signal purchase_finished(item: String, ok: bool, reason: String)

## Testing switch: treat everything as unlocked. Only works when run from the editor.
const DEV_UNLOCK_ALL: bool = false

var signed_in: bool = false
var all_access: bool = false
## Why everything is unlocked: "plus" | "pro" | "unlimited" (Senevon), or "".
var access_reason: String = ""
var tokens: int = 0
var owned: PackedStringArray = []
## Everything for sale: [{ "id", "kind", "price" }]
var items: Array = []

var _bridge: JavaScriptObject
# Keep the callbacks referenced, or Godot frees them and JS calls into nothing.
var _on_state_cb: JavaScriptObject
var _on_purchase_cb: JavaScriptObject


func _ready() -> void:
	if not OS.has_feature("web"):
		return
	_bridge = JavaScriptBridge.get_interface("SenevonAccount")
	if _bridge == null:
		push_warning("Senevon: senevon-account.js is not loaded (HTML head include)")
		return
	_on_state_cb = JavaScriptBridge.create_callback(_on_state)
	_on_purchase_cb = JavaScriptBridge.create_callback(_on_purchase)
	_bridge.onState(_on_state_cb)
	_bridge.onPurchase(_on_purchase_cb)
	apply_state_json(str(_bridge.getState()))


## True when the Senevon account script is running (web build).
func is_connected_to_senevon() -> bool:
	return _bridge != null


## True when the game may offer purchases and sign-in (web only, for now).
func can_buy() -> bool:
	return _bridge != null


func is_premium_build() -> bool:
	return OS.has_feature("premium")


func is_all_access() -> bool:
	return (
		all_access
		or is_premium_build()
		or (DEV_UNLOCK_ALL and OS.has_feature("editor") and not OS.has_feature("web"))
	)


## Can the player use item `id`? An empty id is a free item.
func has_item(id: String) -> bool:
	return id.is_empty() or is_all_access() or owned.has(id)


## Price in tokens, or -1 if the item isn't for sale.
func price_of(id: String) -> int:
	for it: Variant in items:
		if it is Dictionary and str(it.get("id", "")) == id:
			return int(it.get("price", 0))
	return -1


## Shows the purchase box. `display_name` is shown in it (e.g. "Railgun").
func buy(id: String, display_name: String = "") -> void:
	if _bridge == null:
		purchase_finished.emit(id, false, "error")
		return
	_bridge.buy(id, display_name)


func sign_in() -> void:
	open_page("signin")


func sign_out() -> void:
	if _bridge != null:
		_bridge.signOut()


## "plus" | "tokens" | "signin"
func open_page(page: String) -> void:
	if _bridge != null:
		_bridge.open(page)


## Applies a state from senevon-account.js (public for tests).
func apply_state_json(json: String) -> void:
	var d: Dictionary = _parse_object(json)
	if d.is_empty():
		return
	signed_in = bool(d.get("signedIn", false))
	all_access = bool(d.get("allAccess", false))
	var reason: Variant = d.get("accessReason")
	access_reason = "" if reason == null else str(reason)
	tokens = int(d.get("tokens", 0))
	var owned_list: Variant = d.get("owned", [])
	owned = PackedStringArray(owned_list if owned_list is Array else [])
	var item_list: Variant = d.get("items", [])
	items = item_list if item_list is Array else []
	state_changed.emit()


func _on_state(args: Array) -> void:
	apply_state_json(str(args[0]))


func _on_purchase(args: Array) -> void:
	var d: Dictionary = _parse_object(str(args[0]))
	if d.is_empty():
		return
	purchase_finished.emit(
		str(d.get("item", "")), bool(d.get("ok", false)), str(d.get("reason", ""))
	)


## A JSON object from the page, or {} (bad messages are ignored quietly).
static func _parse_object(json: String) -> Dictionary:
	var parser: JSON = JSON.new()
	if parser.parse(json) != OK or not parser.data is Dictionary:
		return {}
	return parser.data
