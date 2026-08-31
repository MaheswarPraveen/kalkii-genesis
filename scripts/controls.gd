extends Node

# Central input layer. Touch UI and keyboard both feed into the player through
# this singleton (autoload "Controls"), so touch is purely ADDITIVE — the player
# still reads hardware keys directly and merges these values on top.
#
# Movement:  the virtual joystick writes `move_vec` every frame (Vector2, -1..1).
# Actions:   touch buttons call press_*(); the player consumes a one-frame latch
#            via consume_*() which returns true once then clears.
# Special:   `special_mode` switches what the SPECIAL button does
#            (SUPER_PUNCH ground lunge vs SUPER_LEAP high jump-punch slam).

enum SpecialMode { SUPER_LEAP, SUPER_PUNCH }

var move_vec: Vector2 = Vector2.ZERO

var _punch_just := false
var _kick_just := false
var _gun_just := false
var _special_just := false

var special_mode: SpecialMode = SpecialMode.SUPER_PUNCH

# --- action presses (called by the touch buttons) ---
func press_punch() -> void:
	_punch_just = true

func press_kick() -> void:
	_kick_just = true

func press_gun() -> void:
	_gun_just = true

func press_special() -> void:
	_special_just = true

# --- action consumers (called by the player; return-and-clear latch) ---
func consume_punch() -> bool:
	var v := _punch_just
	_punch_just = false
	return v

func consume_kick() -> bool:
	var v := _kick_just
	_kick_just = false
	return v

func consume_gun() -> bool:
	var v := _gun_just
	_gun_just = false
	return v

func consume_special() -> bool:
	var v := _special_just
	_special_just = false
	return v

# --- special mode toggle ---
func toggle_special_mode() -> void:
	if special_mode == SpecialMode.SUPER_PUNCH:
		special_mode = SpecialMode.SUPER_LEAP
	else:
		special_mode = SpecialMode.SUPER_PUNCH

func special_mode_label() -> String:
	return "LEAP" if special_mode == SpecialMode.SUPER_LEAP else "PUNCH"
