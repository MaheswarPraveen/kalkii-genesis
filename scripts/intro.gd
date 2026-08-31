extends Control

# Boot sequence: intro video → logo card (TAP TO PLAY) → main game.
# The video is skippable (any key / click / tap). The logo card WAITS for a tap.
#
# DEVELOPER NOTE: while running from the Godot editor the whole intro is
# skipped instantly so F5 drops you straight into gameplay. To PREVIEW the
# intro from the editor, flip DEV_SKIP_IN_EDITOR to false, run, then flip back.

const NEXT_SCENE         := "res://scenes/main.tscn"
const DEV_SKIP_IN_EDITOR := true
const FADE_TIME          := 0.6

@onready var video: VideoStreamPlayer = $Video
@onready var logo_layer: Control = $LogoLayer
@onready var logo: TextureRect = $LogoLayer/Logo
@onready var tap_label: Label = $LogoLayer/TapLabel

enum Stage { VIDEO, LOGO, DONE }
var _stage := Stage.VIDEO

func _ready() -> void:
	if DEV_SKIP_IN_EDITOR and OS.has_feature("editor"):
		_go_to_game()
		return
	logo_layer.modulate.a = 0.0
	logo_layer.visible = false
	video.finished.connect(_to_logo)
	video.play()
	_pulse_tap_label()

func _input(event: InputEvent) -> void:
	var pressed: bool = (event is InputEventKey and event.pressed and not event.echo) \
		or (event is InputEventMouseButton and event.pressed) \
		or (event is InputEventScreenTouch and event.pressed)
	if not pressed:
		return
	match _stage:
		Stage.VIDEO:
			_to_logo()        # first tap skips the video to the logo card
		Stage.LOGO:
			_go_to_game()     # tap on the logo card starts the game

func _to_logo() -> void:
	if _stage != Stage.VIDEO:
		return
	_stage = Stage.LOGO
	video.stop()
	video.visible = false
	logo_layer.visible = true
	var tw := create_tween()
	tw.tween_property(logo_layer, "modulate:a", 1.0, FADE_TIME)

# Gently pulse the "TAP TO PLAY" prompt so it reads as interactive.
func _pulse_tap_label() -> void:
	var tw := create_tween().set_loops()
	tw.tween_property(tap_label, "modulate:a", 0.25, 0.8).set_trans(Tween.TRANS_SINE)
	tw.tween_property(tap_label, "modulate:a", 1.0, 0.8).set_trans(Tween.TRANS_SINE)

func _go_to_game() -> void:
	if _stage == Stage.DONE:
		return
	_stage = Stage.DONE
	get_tree().change_scene_to_file(NEXT_SCENE)
