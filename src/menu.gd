extends Control
# Main menu and pause menu. The game node calls open(kind) / close().

const CONTROLS := "WASD move   |   Left / right click: left / right hand   |   Q / E: use left / right side   |   Wheel: pick loot   |   F: jaw   |   Space: legs   |   R: reload   |   Tab: body & map   |   Esc: pause"

var g
var title: Label
var sub: Label
var buttons: VBoxContainer

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.04, 0.82)
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	center.add_child(v)
	title = _label(64, Color.WHITE)
	sub = _label(18, Color("c9a0a0"))
	v.add_child(title)
	v.add_child(sub)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 18)
	v.add_child(gap)
	buttons = VBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	buttons.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(buttons)
	var gap2 := Control.new()
	gap2.custom_minimum_size = Vector2(0, 18)
	v.add_child(gap2)
	var help := _label(14, Color("888899"))
	help.text = CONTROLS
	v.add_child(help)
	visible = false

func _label(size: int, col: Color) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l

func _button(text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(300, 50)
	b.add_theme_font_size_override("font_size", 20)
	b.pressed.connect(cb)
	buttons.add_child(b)

func open(kind: String) -> void:
	for c in buttons.get_children():
		buttons.remove_child(c)
		c.queue_free()
	if kind == "main":
		title.text = "SPARE PARTS"
		sub.text = "You will come apart. Pick up the pieces."
		_button("New run", g.start_run)
		_button("Debug room", g.debug_room.start_debug)
		_button("Quit", g.quit_game)
	else:
		title.text = "PAUSED"
		sub.text = "Floor %d  -  %d kills" % [g.floor_n, g.kills]
		_button("Resume", g.resume)
		if g.debug:
			_button("Restart debug room", g.debug_room.start_debug)
		else:
			_button("Restart run", g.start_run)
		_button("Main menu", g.to_main_menu)
		_button("Quit", g.quit_game)
	visible = true
	buttons.get_child(0).grab_focus()

func close() -> void:
	visible = false
