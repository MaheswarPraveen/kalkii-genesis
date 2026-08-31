extends Node3D

# Automated playtest: instances the real game, injects inputs, screenshots each
# state to res://playtest_shots/, then quits. Run with:
#   Godot --path . scenes/_playtest.tscn

const Main := preload("res://scenes/main.tscn")
var player: Node3D

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://playtest_shots"))
	var m := Main.instantiate()
	add_child(m)
	await get_tree().process_frame
	player = m.get_node("Player")
	await _run()
	get_tree().quit()

func press(kc: int) -> void:
	var e := InputEventKey.new(); e.physical_keycode = kc; e.pressed = true
	Input.parse_input_event(e)
func release(kc: int) -> void:
	var e := InputEventKey.new(); e.physical_keycode = kc; e.pressed = false
	Input.parse_input_event(e)
func wait(t: float) -> void:
	await get_tree().create_timer(t).timeout
func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://playtest_shots/%s.png" % name)

func _run() -> void:
	# ── SCENE / PROP DENSITY + HEALTH BAR ────────────────────────────────────
	await wait(0.6)
	await shot("A1_arena_overview")          # open arena + HUD health bar top-left
	# Prove you can run the FULL width without being blocked by props.
	press(KEY_A); await wait(2.6); await shot("A2_run_far_left"); release(KEY_A); await wait(0.3)
	press(KEY_D); await wait(5.0); await shot("A3_run_far_right"); release(KEY_D); await wait(0.3)
	# back toward the centre
	press(KEY_A); await wait(2.2); release(KEY_A); await wait(0.3)
	await shot("A4_centre")

	# ── HERO GUN (G) — blue penetrating laser from the muzzle ────────────────
	await shot("B1_before_gun")
	press(KEY_G); await wait(0.05); release(KEY_G)
	await wait(0.10); await shot("B2_gun_fire")
	await wait(0.12); await shot("B3_gun_laser")
	await wait(0.10); await shot("B4_gun_laser2")
	await wait(0.7)

	# ── REGULAR JUMP PUNCH (Space then J in air) ─────────────────────────────
	press(KEY_SPACE); await wait(0.18); release(KEY_SPACE)
	press(KEY_J); await wait(0.05); release(KEY_J)
	await wait(0.10); await shot("C1_regular_jumppunch_air")
	await wait(0.35); await shot("C2_regular_jumppunch_down"); await wait(0.6)

	# ── SUPER LEAP (double Space + J held) — now on a 15s cooldown ────────────
	press(KEY_SPACE); await wait(0.08); release(KEY_SPACE); await wait(0.05)
	press(KEY_J); press(KEY_SPACE); await wait(0.06); release(KEY_SPACE)
	await wait(0.18); await shot("D1_super_leap_air"); release(KEY_J)
	await wait(0.5); await shot("D2_super_leap_slam"); await wait(0.5)

	# ── SUPER PUNCH (H) — now on a 10s cooldown ──────────────────────────────
	press(KEY_H); await wait(0.05); release(KEY_H)
	await wait(0.15); await shot("E1_super_punch"); await wait(0.7)

	# ── COMBAT: let the mob (incl. 3 GUN villains) close in ──────────────────
	# Stand and watch — gun villains should keep distance and fire RED lasers,
	# the health bar should drop as shots connect.
	await wait(1.2); await shot("F1_combat")
	await wait(1.2); await shot("F2_combat")
	await wait(1.2); await shot("F3_combat")
	await wait(1.5); await shot("F4_combat")
	await wait(1.5); await shot("F5_combat_hp")
	await wait(2.0); await shot("F6_combat_hp")
