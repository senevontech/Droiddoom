class_name ArmoryPanel
extends VBoxContainer
## Pause-menu section for the Senevon account (D-035): sign-in state, tokens,
## and an Unlock button for each paid weapon in HOLLOW's loadout. Built in
## code. The pause menu only shows it where Senevon.can_buy() (web for now).
## Purchases happen in Senevon's own box over the page (senevon-account.js).

const CYAN: Color = Color(0.32, 0.86, 1, 1)

var _status: Label
var _sign_in: Button
var _plus: Button
var _tokens: Button
var _rows: VBoxContainer


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	var title: Label = Label.new()
	title.theme_type_variation = &"HeadingLabel"
	title.add_theme_color_override("font_color", CYAN)
	title.add_theme_font_size_override("font_size", 13)
	title.text = "SENEVON ACCOUNT"
	add_child(title)
	_status = Label.new()
	_status.theme_type_variation = &"SmallLabel"
	add_child(_status)
	var buttons: HBoxContainer = HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	add_child(buttons)
	_sign_in = _button(buttons, "SIGN IN WITH SENEVON", 220)
	_sign_in.pressed.connect(Senevon.sign_in)
	_tokens = _button(buttons, "GET TOKENS", 130)
	_tokens.pressed.connect(Senevon.open_page.bind("tokens"))
	_plus = _button(buttons, "SENEVON PLUS", 150)
	_plus.pressed.connect(Senevon.open_page.bind("plus"))
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 6)
	add_child(_rows)
	Senevon.state_changed.connect(refresh)
	Senevon.purchase_finished.connect(_on_purchase_finished)
	refresh()


## Rebuilds the status line and the weapon rows from the current Senevon state.
func refresh() -> void:
	if Senevon.is_all_access():
		var why: String = Senevon.access_reason.to_upper()
		_status.text = "ALL WEAPONS UNLOCKED" + ("" if why.is_empty() else " · " + why)
	elif Senevon.signed_in:
		_status.text = "SIGNED IN · %d TOKENS" % Senevon.tokens
	else:
		_status.text = "SIGNED OUT · FREE WEAPONS ONLY"
	_sign_in.visible = not Senevon.signed_in
	_tokens.visible = Senevon.signed_in and not Senevon.is_all_access()
	_plus.visible = not Senevon.is_all_access()
	for child: Node in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	for data: WeaponData in paid_weapons():
		_add_row(data)


## The paid weapons in HOLLOW's loadout (empty without a player).
func paid_weapons() -> Array[WeaponData]:
	var list: Array[WeaponData] = []
	var hollow: Hollow = get_tree().get_first_node_in_group(Hollow.PLAYER_GROUP) as Hollow
	if hollow == null:
		return list
	for gun: Weapon in hollow.get_primaries() + hollow.get_heavies():
		if not gun.data.unlock_id.is_empty():
			list.append(gun.data)
	return list


## Row count (tests).
func get_row_count() -> int:
	return _rows.get_child_count()


func _add_row(data: WeaponData) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	_rows.add_child(row)
	var label: Label = Label.new()
	label.custom_minimum_size = Vector2(170, 0)
	label.theme_type_variation = &"SmallLabel"
	label.text = _display_name(data)
	row.add_child(label)
	var id: String = data.unlock_id
	var price: int = Senevon.price_of(id)
	var button: Button = _button(row, "", 200)
	if Senevon.has_item(id):
		button.text = "UNLOCKED"
		button.disabled = true
	elif price < 0:
		button.text = "UNAVAILABLE"
		button.disabled = true
	else:
		button.text = "UNLOCK · %d TOKENS" % price
		button.pressed.connect(Senevon.buy.bind(id, _display_name(data).capitalize()))


func _button(parent: Control, text: String, width: float) -> Button:
	var b: Button = Button.new()
	b.custom_minimum_size = Vector2(width, 36)
	b.add_theme_font_size_override("font_size", 13)
	b.text = text
	parent.add_child(b)
	return b


static func _display_name(data: WeaponData) -> String:
	return data.name_key.trim_prefix("WEAPON_").replace("_", " ")


func _on_purchase_finished(_item: String, ok: bool, _reason: String) -> void:
	if ok:
		refresh()
