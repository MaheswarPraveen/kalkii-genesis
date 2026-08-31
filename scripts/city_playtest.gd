extends Node3D

# Automated playtest for the city stage: instances City, walks right across the
# wide level, teleports to the crane end, screenshots each to res://playtest_shots/.

const City := preload("res://scenes/city.tscn")
var city: Node3D
var player: Node3D

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://playtest_shots"))
	city = City.instantiate()
	add_child(city)
	await get_tree().process_frame
	player = city.get_node("Player")
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
	await wait(0.6)
	await shot("CITY_1_start")          # left end: backdrop, buildings, heli, HUD
	# jump to check for any gap between the rooftop and the backdrop at apex
	press(KEY_SPACE); await wait(0.05); release(KEY_SPACE)
	await wait(0.35); await shot("CITY_JUMP_gap")
	# fire the hero gun to check the muzzle height
	press(KEY_G); await wait(0.12); await shot("CITY_GUN_a")
	await wait(0.06); await shot("CITY_GUN_b"); release(KEY_G); await wait(0.3)
	press(KEY_D); await wait(2.5); await shot("CITY_2_walk")
	await wait(2.5); await shot("CITY_3_walk2")
	release(KEY_D); await wait(0.3)
	# jump to the crane / finale end to verify it renders at the far right
	player.global_position.x = city.CRANE_X - 22.0
	await wait(0.5); await shot("CITY_4_crane_end")
	await wait(1.2); await shot("CITY_5_crane_end2")
	# check the extreme LEFT and RIGHT bounds for any empty void past the floor
	player.global_position.x = -2.0
	await wait(0.5); await shot("CITY_6_left_edge")
	player.global_position.x = city.X_END
	await wait(0.5); await shot("CITY_7_right_edge")
	# finale staging: 3 gunships hovering in the open sky by the crane
	player.global_position.x = city.CRANE_X - 62.0
	await wait(0.6); await shot("CITY_8_heli_fleet")
	await wait(0.5); await shot("CITY_8b_heli_fleet")
	await wait(0.5); await shot("CITY_8c_heli_fleet")
	# FORCE the win/crash stage to catch the post-crash crash bug
	for v in city._finale_enemies:
		if is_instance_valid(v):
			v.set("hp", 0.0)
			v.set("state", 6)
	city._trigger_pull(0)         # break the choppers in the air
	await wait(0.5); await shot("CITY_PULL")
	city._attached = 3
	city._finale_t = 0.0
	city._crash_started = false
	city._finale_state = 5        # WIN / crash
	await wait(2.0); await shot("CITY_CRASH_1")
	await wait(2.0); await shot("CITY_CRASH_2")
	await wait(1.5); await shot("CITY_CRASH_3")
