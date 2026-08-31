extends CanvasLayer

# On-screen mobile touch overlay. Feeds the Controls singleton:
#   - BOTTOM-RIGHT: four round action buttons PUNCH / KICK / GUN / SPECIAL.
#   - A small toggle above SPECIAL flips Controls.special_mode (LEAP / PUNCH).
#
# Touch is additive: keyboard still works. The overlay only shows on touch
# devices unless FORCE_SHOW is true (set true for now so it's testable on desktop).

const FORCE_SHOW := true

# --- action button geometry ---
const BTN_RADIUS := 56.0
const BTN_GAP := 26.0

const COL_TEXT := Color(0.88, 0.95, 1.0, 0.95)

var _toggle_btn: Button


func _ready() -> void:
	layer = 50
	visible = FORCE_SHOW or DisplayServer.is_touchscreen_available() or OS.has_feature("mobile")
	_build_action_buttons()


# --------------------------------------------------------------------------
# ACTION BUTTONS
# --------------------------------------------------------------------------
func _make_round_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(BTN_RADIUS * 2.0, BTN_RADIUS * 2.0)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 18)
	b.add_theme_color_override("font_color", COL_TEXT)
	b.add_theme_color_override("font_pressed_color", Color(1, 1, 1, 1))
	b.add_theme_color_override("font_hover_color", COL_TEXT)

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.14, 0.18, 0.55)
	sb.set_corner_radius_all(int(BTN_RADIUS))
	sb.border_color = Color(0.55, 0.85, 1.0, 0.65)
	sb.set_border_width_all(3)
	var sb_pressed := sb.duplicate() as StyleBoxFlat
	sb_pressed.bg_color = Color(0.30, 0.55, 0.75, 0.80)
	var sb_hover := sb.duplicate() as StyleBoxFlat
	sb_hover.bg_color = Color(0.18, 0.22, 0.28, 0.60)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("pressed", sb_pressed)
	b.add_theme_stylebox_override("hover", sb_hover)
	b.add_theme_stylebox_override("focus", sb)
	return b


func _build_action_buttons() -> void:
	# Cluster anchored to the bottom-right. Layout (x grows left of edge):
	#   PUNCH  (far left of cluster, two-row)   GUN
	#   KICK                                     SPECIAL
	# A small mode-toggle sits above SPECIAL.
	var holder := Control.new()
	holder.name = "ActionButtons"
	holder.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)

	var d := BTN_RADIUS * 2.0
	var gap := BTN_GAP
	# positions are offsets from the bottom-right corner (negative = inward)
	# right column (closest to edge): GUN top, SPECIAL bottom
	# left column: PUNCH top, KICK bottom
	var margin := Vector2(-40.0, -40.0)
	var col_right_x := margin.x - d
	var col_left_x := col_right_x - d - gap
	var row_bot_y := margin.y - d
	var row_top_y := row_bot_y - d - gap

	var punch := _make_round_button("PUNCH")
	_place(holder, punch, Vector2(col_left_x, row_top_y))
	punch.pressed.connect(func(): Controls.press_punch())

	var kick := _make_round_button("KICK")
	_place(holder, kick, Vector2(col_left_x, row_bot_y))
	kick.pressed.connect(func(): Controls.press_kick())

	var gun := _make_round_button("GUN")
	_place(holder, gun, Vector2(col_right_x, row_top_y))
	gun.pressed.connect(func(): Controls.press_gun())

	var special := _make_round_button("SPECIAL")
	_place(holder, special, Vector2(col_right_x, row_bot_y))
	special.pressed.connect(func(): Controls.press_special())

	# mode toggle: small pill above the SPECIAL button
	_toggle_btn = Button.new()
	_toggle_btn.text = Controls.special_mode_label()
	_toggle_btn.focus_mode = Control.FOCUS_NONE
	_toggle_btn.custom_minimum_size = Vector2(d, 40.0)
	_toggle_btn.add_theme_font_size_override("font_size", 16)
	_toggle_btn.add_theme_color_override("font_color", COL_TEXT)
	var tsb := StyleBoxFlat.new()
	tsb.bg_color = Color(0.15, 0.10, 0.20, 0.65)
	tsb.set_corner_radius_all(14)
	tsb.border_color = Color(0.85, 0.55, 1.0, 0.70)
	tsb.set_border_width_all(2)
	_toggle_btn.add_theme_stylebox_override("normal", tsb)
	_toggle_btn.add_theme_stylebox_override("pressed", tsb)
	_toggle_btn.add_theme_stylebox_override("hover", tsb)
	_toggle_btn.add_theme_stylebox_override("focus", tsb)
	# sits just above the right column's top row
	_place(holder, _toggle_btn, Vector2(col_right_x, row_top_y - 50.0))
	_toggle_btn.pressed.connect(_on_toggle_pressed)


func _place(holder: Control, ctrl: Control, offset_from_br: Vector2) -> void:
	# anchor each control to the holder's bottom-right, then position by offset.
	ctrl.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	ctrl.offset_left = offset_from_br.x
	ctrl.offset_top = offset_from_br.y
	ctrl.offset_right = offset_from_br.x + ctrl.custom_minimum_size.x
	ctrl.offset_bottom = offset_from_br.y + ctrl.custom_minimum_size.y
	holder.add_child(ctrl)


func _on_toggle_pressed() -> void:
	Controls.toggle_special_mode()
	_toggle_btn.text = Controls.special_mode_label()
