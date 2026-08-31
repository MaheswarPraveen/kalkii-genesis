extends Node3D

# KALKII — Map 2: the city. A WIDE left→right beat-'em-up stage. The player fights
# across the street; the crane sits at the far-right end (the finale spot where the
# helicopter is brought down). For now the helicopter just patrols the sky.

const PlayerScene  := preload("res://scenes/player.tscn")
const VillainScene := preload("res://scenes/villain.tscn")
const TouchControlsScene := preload("res://scenes/touch_controls.tscn")

const ART := "res://assets/sprites/citymap/"

const LEVEL_LEN := 280.0     # stage length along +X
const X_START   := 6.0       # player spawn (left end)
const X_END     := LEVEL_LEN - 12.0
const Z_MIN     := -7.0      # fighting lane depth
const Z_MAX     := 14.0
const CRANE_X   := LEVEL_LEN - 14.0

var player: CharacterBody3D = null
var _cam: Camera3D = null
var _heli: AnimatedSprite3D = null
var _helis: Array = []
var _heli_t := 0.0
var _ropes: Array = []      # one black swaying rope per gunship
var _red_shots: Array = []
var _finale_enemies: Array = []   # the 3 black-suits that rappel + fire
var _crashes: Array = []          # per-chopper crash visuals (half-broken -> wreck)
var _shooting_stopped := false    # set once a rope is pulled — choppers stop firing
var _crash_started := false
# finale stages: 0 fight, 1 tie ropes, 2 lower+attach hook, 3 enter crane,
#                4 tug-of-war, 5 win/crash, 6 done
var _finale_state := 0
var _finale_t := 0.0
var _hook: Sprite3D = null
var _cable: MeshInstance3D = null
var _hook_pos := Vector3.ZERO
var _crane_anchor := Vector3.ZERO
var _e_prev := false
var _hud_prompt: Label = null
var _tug := 0.45                  # tug-of-war progress 0..1 (win at 1, lose at 0)
var _tug_bg: ColorRect = null
var _tug_fill: ColorRect = null
var _carried := -1                # index of the rope currently in hand (-1 = none)
var _attached := 0                # how many ropes hitched onto the hook
var _crane_mat: StandardMaterial3D = null
var _crane_mi: MeshInstance3D = null
const HOOK_REST := 4.5            # reachable hook height for hand-attaching
var _moon: MeshInstance3D = null
var _hud_health_fill: ColorRect = null
var _hud_bar_full_w := 0.0
var _hud_leap_lbl: Label = null
var _hud_punch_lbl: Label = null


func _ready() -> void:
	_build_env()
	_build_floor()
	_build_backdrop()
	_build_buildings()
	_build_front_facade()
	# _build_props()   # mid-rooftop props are placed by hand in city.tscn (Props node)
	_build_end_fill()  # but the non-playable ends stay auto-packed with clutter
	_build_crane()
	_build_heli()
	_build_player_and_camera()
	# _spawn_villains()   # the patrol waves are off; only the finale squad spawns
	_spawn_finale_enemies()
	_build_hud()


func _spawn_finale_enemies() -> void:
	# One black-suit gunner dangles on each chopper's rope, firing at the player,
	# until killed. Defeat all 3 to operate the crane (press E).
	for hd in _helis:
		var hp: Vector3 = hd["hang"]
		var v := VillainScene.instantiate()
		v.position = hp
		v.set("is_gunner", true)
		v.set("hung", true)
		v.set("hang_point", hp)
		add_child(v)
		v.set("state_timer", randf_range(0.3, 1.2))
		_finale_enemies.append(v)
		hd["enemy"] = v


func _process(delta: float) -> void:
	_heli_t += delta
	_update_ability_hud()
	_tick_finale(delta)
	_update_camera(delta)
	_update_crane_motion()
	# Hover during fight + pull stages; machine-gun the hero until a rope is pulled.
	if _finale_state <= 1:
		for hd in _helis:
			if not is_instance_valid(hd["node"]):
				continue
			var base: Vector3 = hd["base"]
			var t := _heli_t * float(hd["spd"]) + float(hd["phase"])
			var pos: Vector3 = base + Vector3(sin(t) * 1.2, sin(t * 1.3) * 0.9, 0.0)
			hd["node"].global_position = pos
			if _shooting_stopped:
				continue
			hd["fire_t"] = float(hd["fire_t"]) - delta
			if hd["fire_t"] <= 0.0:
				hd["fire_t"] = 0.08 + randf() * 0.04
				_fire_red(pos + hd["gun"])
	_update_rope()
	# advance red tracers; hit the hero, or drop at the rooftop / after lifetime
	for i in range(_red_shots.size() - 1, -1, -1):
		var s = _red_shots[i]
		var sp: Vector3 = s["node"].global_position + s["vel"] * delta
		s["node"].global_position = sp
		s["life"] = float(s["life"]) - delta
		var hit := false
		if player != null and sp.distance_to(player.global_position + Vector3(0, 2.5, 0)) < 1.8:
			player.call("receive_heli_hit")
			hit = true
		if hit or sp.y <= 0.2 or float(s["life"]) <= 0.0:
			s["node"].queue_free()
			_red_shots.remove_at(i)


func _tick_finale(delta: float) -> void:
	var e := _e_just_pressed()
	# crane pulses red while the ropes still need pulling / hitching
	if _crane_mat != null:
		if _finale_state >= 1 and _finale_state <= 2:
			_crane_mat.emission = Color(0.9, 0.0, 0.0) * (0.35 + 0.3 * sin(_heli_t * 5.0))
		else:
			_crane_mat.emission = Color(0, 0, 0)
	match _finale_state:
		0:  # FIGHT — wait until all 3 dangling black-suits are dead (DEAD == 6)
			if _finale_enemies.is_empty():
				return
			for v in _finale_enemies:
				if is_instance_valid(v) and int(v.get("state")) != 6:
					return
			_finale_state = 1
		1:  # PULL one chopper's rope -> it strafes the other two; all take half
			#    damage in the air, the pulled one's frame breaks too, fire stops.
			_set_prompt("▸ PRESS  E  TO PULL A CHOPPER'S ROPE", _near_free_rope() != -1)
			if _near_free_rope() != -1 and e:
				_trigger_pull(_near_free_rope())
				_finale_state = 2
		2:  # TIE — grab each rope, carry it to the hook, hitch all three together
			var hook_reach := Vector3(_crane_anchor.x, HOOK_REST, _crane_anchor.z)
			_hook_pos = _hook_pos.lerp(hook_reach, delta * 1.6)
			if _carried == -1:
				var ri := _near_free_rope()
				_set_prompt("▸ PRESS  E  TO GRAB THE ROPE", ri != -1)
				if ri != -1 and e:
					_ropes[ri]["state"] = 1
					_carried = ri
			else:
				_set_prompt("▸ CARRY TO THE HOOK — PRESS  E  TO HITCH IT", true)
				if _player_near_hook() and e:
					_ropes[_carried]["state"] = 2
					_carried = -1
					_attached += 1
			if _attached >= _ropes.size():
				_finale_state = 3
		3:  # OPERATE — climb into the crane and start the tug-of-war
			_set_prompt("▸ PRESS  E  TO OPERATE THE CRANE", _player_near_crane())
			if _player_near_crane() and e:
				_show_player(false)
				_tug = 0.45
				_finale_state = 4
				_finale_t = 0.0
		4:  # TUG OF WAR — mash E; win at full, lose (and untie) at empty
			_finale_t += delta
			_set_prompt("◄ TUG OF WAR — MASH  E ! ►", true)
			if e:
				_tug = minf(_tug + 0.08, 1.0)
			if _tug >= 1.0:
				_finale_state = 5
				_finale_t = 0.0
				_crash_started = false
				_set_prompt("", false)
			else:
				_tug = maxf(_tug - delta * 0.11, 0.0)   # the choppers strain back
				for c in _crashes:
					if is_instance_valid(c["heli"]):
						c["heli"].global_position = (c["start"] as Vector3) + Vector3(sin(_finale_t * 9.0) * 0.25, lerpf(2.0, -2.0, _tug), 0)
				if _tug <= 0.0:
					for rd in _ropes:
						rd["state"] = 0
					_attached = 0
					_carried = -1
					_show_player(true)
					_finale_state = 2
		5:  # WIN — the broken choppers are dragged down to a wreck + blast + smoke
			_finale_t += delta
			_hook_pos = _hook_pos.lerp(_crane_anchor + Vector3(0, -2.0, 0), delta * 1.2)
			_update_crashes()
			if _finale_t > 6.5:
				for rd in _ropes:
					if is_instance_valid(rd["node"]):
						rd["node"].queue_free()
				_ropes.clear()
				_show_player(true)
				_finale_state = 6
		6:
			pass
	_update_broken_follow()
	_update_cable()
	_update_tug_hud()


func _update_crane_motion() -> void:
	# idle life so the crane isn't a dead prop: the whole rig sways a hair and the
	# dangling hook bobs/swings. During the finale the stages drive the hook.
	if _crane_mi != null:
		_crane_mi.rotation.z = sin(_heli_t * 0.65) * 0.007
	if _finale_state == 0:
		_hook_pos = _crane_anchor + Vector3(sin(_heli_t * 0.9) * 0.6, -3.0 + sin(_heli_t * 1.4) * 0.45, 0.0)


func _trigger_pull(pulled: int) -> void:
	# Pulling one rope: the pulled chopper sprays the other two with a tracer burst
	# (cross-fire), all three take damage and freeze — visually still flying but
	# locked in place. The half-broken "before" sprite swaps in at 25% of the fall.
	_shooting_stopped = true
	# cross-fire burst: pulled chopper fires at each of the other two
	if is_instance_valid(_helis[pulled]["node"]):
		var src: Vector3 = _helis[pulled]["node"].global_position + _helis[pulled]["gun"]
		for i in _helis.size():
			if i == pulled:
				continue
			if not is_instance_valid(_helis[i]["node"]):
				continue
			var tgt: Vector3 = _helis[i]["node"].global_position
			for _s in 10:
				var dir := (tgt - src).normalized()
				dir += Vector3(randf_range(-0.07, 0.07), randf_range(-0.05, 0.05), 0.0)
				_red_shots.append({"node": _mk_tracer(src + Vector3(randf_range(-0.4, 0.4), randf_range(-0.4, 0.4), 0.0)),
					"vel": dir.normalized() * 24.0, "life": 3.0})
	# freeze every chopper in the sky — keep visible, pause the rotor, stop bobbing
	for i in _helis.size():
		var hd = _helis[i]
		if not is_instance_valid(hd["node"]):
			continue
		hd["node"].pause()   # freeze rotor animation
		var ground := Vector3(CRANE_X - 64.0 + float(i) * 12.0, 0.0, -5.0)
		_crashes.append({"idx": i, "heli": hd["node"], "before": null,
			"before_spawned": false, "start": hd["node"].global_position,
			"ground": ground, "done": false})


func _update_broken_follow() -> void:
	# while hanging (tie / operate stages) the frozen choppers sway on their ropes
	if _finale_state < 2 or _finale_state > 3:
		return
	for c in _crashes:
		if not is_instance_valid(c["heli"]):
			continue
		var idx := float(c["idx"])
		var sway := Vector3(sin(_heli_t * 1.5 + idx * 2.0) * 0.35, sin(_heli_t * 2.2 + idx) * 0.22, 0.0)
		c["heli"].global_position = (c["start"] as Vector3) + sway


func _update_crashes() -> void:
	if not _crash_started:
		for c in _crashes:
			if is_instance_valid(c["heli"]):
				c["start"] = c["heli"].global_position
		_crash_started = true
	var fall_t := 2.4
	for c in _crashes:
		var p := clampf(_finale_t / fall_t, 0.0, 1.0)
		var cur: Vector3 = (c["start"] as Vector3).lerp(c["ground"], ease(p, 2.0))
		# tumbling jitter — eases out as it nears the ground
		if not c["done"]:
			var idx := float(c["idx"])
			var amp := (1.0 - p) * 0.9 + 0.2
			cur += Vector3(
				sin(_finale_t * 27.0 + idx * 1.7) * amp + randf_range(-0.4, 0.4) * amp,
				sin(_finale_t * 21.0 + idx * 3.1) * amp * 0.7 + randf_range(-0.3, 0.3) * amp,
				0.0)
		# at 25% of the fall swap from frozen fly-frame to the half-broken before sprite
		if not c.get("before_spawned", false) and p >= 0.25 and not c["done"]:
			c["before_spawned"] = true
			var bef = _mk_crash_sprite(load(ART + "hc_before_%d.png" % int(c["idx"])), 0.030, false)
			bef.global_position = cur
			c["before"] = bef
			if is_instance_valid(c["heli"]):
				c["heli"].visible = false
		# move whichever visual is active
		if is_instance_valid(c["heli"]) and c["heli"].visible:
			c["heli"].global_position = cur
		if c.get("before") != null and is_instance_valid(c["before"]):
			c["before"].global_position = cur
		# ground impact
		if not c["done"] and p >= 1.0:
			if c.get("before") != null and is_instance_valid(c["before"]):
				c["before"].queue_free()
			if is_instance_valid(c["heli"]):
				c["heli"].visible = false
			var wreck := _mk_crash_sprite(load(ART + "hc_after_%d.png" % int(c["idx"])), 0.032, true)
			wreck.global_position = c["ground"]
			_spawn_crash_flame(c["ground"] + Vector3(0.0, 0.0, 0.6))
			c["done"] = true


func _mk_tracer(pos: Vector3) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.13, 1.5, 0.13)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 0.12, 0.08)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.3, 0.12)
	m.emission_energy_multiplier = 8.0
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = m
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	add_child(mi)
	mi.global_position = pos
	return mi


func _mk_crash_sprite(tex: Texture2D, px: float, bottom: bool) -> Sprite3D:
	var s := Sprite3D.new()
	s.texture = tex
	s.pixel_size = px
	s.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	if bottom and tex != null:
		s.offset = Vector2(0.0, float(tex.get_height()) * 0.5)   # base sits on the ground
	add_child(s)
	return s


func _spawn_crash_flame(pos: Vector3) -> void:
	# 8-frame explosion blast (flame_0..7) then 8-frame perpetual smoke (smoke_0..7).
	var sf := SpriteFrames.new()
	sf.remove_animation(&"default")
	sf.add_animation(&"blast")
	sf.set_animation_loop(&"blast", false)
	sf.set_animation_speed(&"blast", 13.0)
	for i in 8:
		sf.add_frame(&"blast", load(ART + "flame_%d.png" % i))
	sf.add_animation(&"smoke")
	sf.set_animation_loop(&"smoke", true)
	sf.set_animation_speed(&"smoke", 6.0)
	for i in 8:
		sf.add_frame(&"smoke", load(ART + "smoke_%d.png" % i))
	var a := AnimatedSprite3D.new()
	a.sprite_frames = sf
	a.pixel_size = 0.028
	a.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	a.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	a.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	var t0: Texture2D = load(ART + "flame_0.png")
	if t0 != null:
		a.offset = Vector2(0.0, float(t0.get_height()) * 0.5)   # fire grows up from the ground
	add_child(a)
	a.global_position = pos
	a.play(&"blast")
	a.animation_finished.connect(func() -> void:
		if is_instance_valid(a):
			a.play(&"smoke"))


func _show_player(v: bool) -> void:
	# hide/show only the character sprite — never the player node (it holds the camera)
	if player == null:
		return
	var spr := player.get_node_or_null("Sprite")
	if spr != null:
		spr.visible = v


func _update_camera(delta: float) -> void:
	if _cam == null:
		return
	# Once all three ropes are hooked (operate/tug/win stages) snap out to a wide
	# shot framing all three choppers; otherwise the normal follow view.
	# Wide shot for the whole hook -> tug -> crash finale (one consistent framing,
	# ~17% less zoomed-out than before so the action isn't tiny).
	var wide := _finale_state >= 3 and _finale_state <= 5
	var tpos := Vector3(0, 14.0, 38.0) if wide else Vector3(0, 6.2, 17.5)
	var tfov := 81.0 if wide else 75.0
	var thoff := -8.0 if wide else 0.0
	var spd := delta * 4.5
	_cam.position = _cam.position.lerp(tpos, spd)
	_cam.fov = lerpf(_cam.fov, tfov, spd)
	_cam.h_offset = lerpf(_cam.h_offset, thoff, spd)


func _near_free_rope() -> int:
	if player == null:
		return -1
	for i in _ropes.size():
		if int(_ropes[i]["state"]) == 0:
			var hx: float = _ropes[i]["hang"].x
			if absf(player.global_position.x - hx) < 4.0:
				return i
	return -1


func _player_near_hook() -> bool:
	return player != null and absf(player.global_position.x - _hook_pos.x) < 4.5 \
		and absf(player.global_position.z - _hook_pos.z) < 7.0


func _set_prompt(txt: String, show: bool) -> void:
	if _hud_prompt == null:
		return
	if show:
		_hud_prompt.text = txt
	_hud_prompt.visible = show


func _update_tug_hud() -> void:
	var on := _finale_state == 4
	if _tug_bg != null:
		_tug_bg.visible = on
	if _tug_fill != null:
		_tug_fill.visible = on
		if on:
			_tug_fill.offset_right = -260.0 + 520.0 * clampf(_tug, 0.0, 1.0)


func _e_just_pressed() -> bool:
	var now := Input.is_physical_key_pressed(KEY_E)
	var fired := now and not _e_prev
	_e_prev = now
	return fired


func _player_near_crane() -> bool:
	return player != null and absf(player.global_position.x - (CRANE_X - 40.0)) < 26.0


func _update_cable() -> void:
	if _cable == null:
		return
	if is_instance_valid(_hook):
		_hook.global_position = _hook_pos
	var im: ImmediateMesh = _cable.mesh
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var hw := 0.08
	im.surface_set_normal(Vector3(0, 0, 1))
	im.surface_add_vertex(Vector3(_crane_anchor.x - hw, _crane_anchor.y, _crane_anchor.z))
	im.surface_add_vertex(Vector3(_crane_anchor.x + hw, _crane_anchor.y, _crane_anchor.z))
	im.surface_add_vertex(Vector3(_hook_pos.x - hw, _hook_pos.y, _hook_pos.z))
	im.surface_add_vertex(Vector3(_hook_pos.x + hw, _hook_pos.y, _hook_pos.z))
	im.surface_end()


func _spawn_explosion(at: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 0.5, 0.1)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.55, 0.15)
	m.emission_energy_multiplier = 10.0
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.material = m
	mi.mesh = sm
	add_child(mi)
	mi.global_position = at
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(7, 7, 7), 0.6)
	tw.tween_property(m, "emission_energy_multiplier", 0.0, 0.7)
	tw.chain().tween_callback(mi.queue_free)


# ── ENVIRONMENT ───────────────────────────────────────────────────────────────
func _build_env() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.06, 0.10)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.32, 0.36, 0.50)
	env.ambient_light_energy = 0.9
	env.fog_enabled = true
	env.fog_light_color = Color(0.20, 0.24, 0.34)
	env.fog_density = 0.012          # subtle haze, backdrop stays clear
	env.fog_sky_affect = 0.3
	env.fog_aerial_perspective = 0.25
	env.glow_enabled = true
	env.glow_intensity = 0.45
	env.glow_bloom = 0.15
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = env
	add_child(we)

	var moon := DirectionalLight3D.new()
	moon.rotation_degrees = Vector3(-58, -28, 0)
	moon.light_color = Color(0.55, 0.62, 0.85)
	moon.light_energy = 0.55
	moon.shadow_enabled = true
	add_child(moon)
	# a couple of warm street fills along the lane
	for fx in [40.0, 140.0, 240.0]:
		var o := OmniLight3D.new()
		o.position = Vector3(fx, 5.0, 6.0)
		o.light_color = Color(1.0, 0.6, 0.3)
		o.light_energy = 1.6
		o.omni_range = 30.0
		add_child(o)
	var cyan := OmniLight3D.new()
	cyan.position = Vector3(CRANE_X, 7.0, 2.0)
	cyan.light_color = Color(0.4, 0.8, 1.0)
	cyan.light_energy = 2.0
	cyan.omni_range = 34.0
	add_child(cyan)


func _build_floor() -> void:
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	col.shape = WorldBoundaryShape3D.new()
	body.add_child(col)
	add_child(body)

	var dir := ART + "floor/"
	var names := ["asphalt", "gravel", "grating"]
	var mats: Array[StandardMaterial3D] = []
	for n in names:
		var m := StandardMaterial3D.new()
		m.albedo_texture = load(dir + n + ".png")
		m.metallic = 0.3
		m.roughness = 0.5
		mats.append(m)
	var rng := RandomNumberGenerator.new()
	rng.seed = 71
	var cell := 6.0
	var quad := QuadMesh.new()
	quad.size = Vector2(cell, cell)
	var x := -60.0
	while x < LEVEL_LEN + 60.0:   # extends well past the play bounds (no void at ends)
		var z := -30.0   # start aligned so 6-wide tiles end exactly at the front (z=12)
		while z < 12.0:   # floor ends at the front rooftop edge (z=12)
			var mi := MeshInstance3D.new()
			mi.mesh = quad
			mi.material_override = mats[rng.randi() % mats.size()]
			mi.rotation_degrees = Vector3(-90, 0, 0)
			mi.position = Vector3(x + cell * 0.5, 0.0, z + cell * 0.5)
			add_child(mi)
			z += cell
		x += cell

	# ONE big helipad pad, laid flat near the crane/finale end.
	var helipad_mat := StandardMaterial3D.new()
	helipad_mat.albedo_texture = load(dir + "helipad.png")
	helipad_mat.metallic = 0.3
	helipad_mat.roughness = 0.5
	var pad := MeshInstance3D.new()
	var pquad := QuadMesh.new()
	pquad.size = Vector2(20.0, 20.0)
	pad.mesh = pquad
	pad.material_override = helipad_mat
	pad.rotation_degrees = Vector3(-90, 0, 0)
	pad.position = Vector3(LEVEL_LEN * 0.45, 0.02, 2.0)
	add_child(pad)


func _build_moon() -> void:
	# A SINGLE moon, far in the sky. It follows the view (loose parallax) so it
	# appears once and never tiles/repeats like the backdrop does.
	var tex: Texture2D = load(ART + "moon.png")
	if tex == null:
		return
	var hgt := 20.0
	var w := hgt * float(tex.get_width()) / float(tex.get_height())
	var quad := QuadMesh.new()
	quad.size = Vector2(w, hgt)
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA   # soft glow edge
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	quad.material = m
	_moon = MeshInstance3D.new()
	_moon.mesh = quad
	add_child(_moon)
	_moon.global_position = Vector3(X_START, 30.0, -64.0)


func _build_backdrop() -> void:
	# Far street-canyon backdrop, repeated across the whole stage width.
	var tex: Texture2D = load(ART + "backdrop.png")
	if tex == null:
		return
	# Big back wall: tall + dropped low so it fully covers behind the rooftop edge
	# (no gap shows on a jump or in the wide shot), brought a touch closer.
	var h := 108.0
	var w := h * float(tex.get_width()) / float(tex.get_height())
	var x := -w
	while x < LEVEL_LEN + w:
		_art_tex(tex, h, Vector3(x + w * 0.5, -26.0, -60.0), 0.9)
		x += w


func _build_buildings() -> void:
	# Two apartment towers alternating across the mid-ground as a parallax layer.
	var rng := RandomNumberGenerator.new()
	rng.seed = 12
	var x := -8.0
	var k := 0
	while x < LEVEL_LEN + 8.0:
		var f := "building_%d.png" % (k % 2)
		var hgt := rng.randf_range(26.0, 36.0)
		# Sunk well below the ground plane so the bases hide behind the street
		# horizon and the towers rise from behind it (instead of floating).
		var bz := -40.0 + rng.randf_range(-3.0, 3.0)
		_art(f, hgt, Vector3(x, -13.0, bz), 0.82)
		# A small neon spot glowing off the facade — alternating green / blue.
		var neon := OmniLight3D.new()
		if k % 2 == 0:
			neon.light_color = Color(0.2, 1.0, 0.45)   # green
		else:
			neon.light_color = Color(0.25, 0.55, 1.0)  # blue
		neon.light_energy = rng.randf_range(1.2, 2.2)
		neon.omni_range = rng.randf_range(10.0, 16.0)
		neon.position = Vector3(x + rng.randf_range(-3.0, 3.0), rng.randf_range(8.0, 18.0), bz + 4.0)
		add_child(neon)
		x += rng.randf_range(36.0, 52.0)
		k += 1


func _build_front_facade() -> void:
	# The building face dropping away in FRONT of the rooftop edge. Tilted so it
	# recedes down-and-away (we look down the side of the building), not a flat
	# wall. Tiled across the whole stage width along the front lip.
	var tex: Texture2D = load(ART + "building_fore.png")
	if tex == null:
		return
	var drop_h := 26.0
	var tile_w := drop_h * float(tex.get_width()) / float(tex.get_height())
	var x := -tile_w
	while x < LEVEL_LEN + tile_w:
		var mi := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(tile_w, drop_h)
		var m := StandardMaterial3D.new()
		m.albedo_texture = tex
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.5
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		quad.material = m
		mi.mesh = quad
		# Top edge sits at the front rooftop lip. Barely any X-tilt so it reads as
		# a wall face dropping away — perspective does the depth work.
		mi.rotation_degrees = Vector3(1.5, 0.0, 0.0)
		mi.position = Vector3(x + tile_w * 0.5, -12.5, 14.5)
		add_child(mi)
		x += tile_w


const PROP_H := [5.5, 6.5, 6.0, 4.5, 3.8, 3.2]   # heights of prop_0..5
# prop_0 AC unit, 1 water tank, 2 dish, 3 neon sign, 4 crates, 5 barrier

func _place_prop(idx: int, px: float, pz: float, rng: RandomNumberGenerator) -> void:
	var h: float = float(PROP_H[idx]) * rng.randf_range(0.88, 1.12)
	_art("prop_%d.png" % idx, h, Vector3(px, 0.0, pz), 0.92)

func _build_props() -> void:
	# Rooftop clutter placed in logical CLUSTERS with irregular gaps, not an even
	# line. Heavy machinery hugs the back; low crates/barriers sit a bit forward.
	var rng := RandomNumberGenerator.new()
	rng.seed = 91
	var machinery := [0, 1, 2]   # AC / tank / dish -> back wall
	var low := [4, 5]            # crates / barriers -> low, can creep forward
	var pad_x := LEVEL_LEN * 0.45
	var x := X_START + 10.0
	while x < X_END - 12.0:
		# keep the helipad landing zone clear of clutter
		if absf(x - pad_x) < 13.0:
			x = pad_x + 13.0
			continue
		var roll := rng.randf()
		if roll < 0.42:
			# a huddle of 2-3 machines jammed against the back
			var n := rng.randi_range(2, 3)
			for i in n:
				var idx: int = machinery[rng.randi() % machinery.size()]
				_place_prop(idx, x + i * rng.randf_range(3.2, 5.0), -6.6 + rng.randf_range(-0.8, 0.4), rng)
		elif roll < 0.66:
			# a tall neon sign, often with a crate slumped at its foot
			_place_prop(3, x, -6.0 + rng.randf_range(-0.5, 0.5), rng)
			if rng.randf() < 0.6:
				_place_prop(4, x + rng.randf_range(2.5, 4.5), -4.4 + rng.randf_range(-0.5, 0.5), rng)
		elif roll < 0.88:
			# scattered low clutter creeping toward the lane
			var n2 := rng.randi_range(1, 3)
			for i in n2:
				var idx2: int = low[rng.randi() % low.size()]
				_place_prop(idx2, x + i * rng.randf_range(2.0, 3.6), -5.0 + rng.randf_range(-1.6, 1.4), rng)
		# else: deliberately leave an open gap to break the rhythm
		x += rng.randf_range(20.0, 40.0)

	# Pack the non-playable LEFT and RIGHT ends with dense clutter so the rooftop
	# looks enclosed instead of fading into bare floor.
	_fill_end(rng, -16.0, -2.0)
	_fill_end(rng, X_END + 1.0, LEVEL_LEN + 8.0)

func _build_end_fill() -> void:
	# Densely pack the non-playable LEFT and RIGHT ends so the rooftop reads as
	# enclosed rather than fading to bare floor.
	var rng := RandomNumberGenerator.new()
	rng.seed = 91
	_fill_end(rng, -18.0, -2.0)
	_fill_end(rng, X_END + 1.0, LEVEL_LEN + 10.0)

func _fill_end(rng: RandomNumberGenerator, x0: float, x1: float) -> void:
	var x := x0
	while x < x1:
		var idx := rng.randi_range(0, 5)
		_place_prop(idx, x + rng.randf_range(-1.0, 1.0), rng.randf_range(-7.0, 1.0), rng)
		x += rng.randf_range(3.5, 6.5)


func _build_crane() -> void:
	# The finale crane sits just behind the play lane (right after the building
	# line) so the character can reach its base and climb it. Base grounded at the
	# floor; full tower/jib/hook visible.
	_crane_mi = _art("crane.png", 24.0, Vector3(CRANE_X - 40.0, 0.0, -20.0), 1.0, true)
	if _crane_mi != null:
		_crane_mat = (_crane_mi.mesh as QuadMesh).material
		_crane_mat.emission_enabled = true
		_crane_mat.emission = Color(0, 0, 0)
	# Thread + hook hang from the jib-tip pulley (left end, since the crane is
	# flipped). The hook starts retracted just below it.
	_crane_anchor = Vector3(CRANE_X - 56.0, 16.8, -20.0)
	_hook_pos = _crane_anchor + Vector3(0.0, -3.0, 0.0)
	_cable = MeshInstance3D.new()
	_cable.mesh = ImmediateMesh.new()
	var cm := StandardMaterial3D.new()
	cm.albedo_color = Color(0.05, 0.05, 0.06)
	cm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cm.cull_mode = BaseMaterial3D.CULL_DISABLED
	_cable.material_override = cm
	add_child(_cable)
	# Use the crane's own hook art (extracted from crane.png) as the moving hook.
	_hook = Sprite3D.new()
	_hook.texture = load(ART + "hook.png")
	_hook.pixel_size = 0.045
	_hook.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	_hook.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_hook.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	add_child(_hook)
	_hook.global_position = _hook_pos


func _build_rope(heli: AnimatedSprite3D, hang: Vector3) -> void:
	# A brown rappel rope, rebuilt every frame as a swaying ribbon so it moves
	# fluidly. state: 0 free (hangs), 1 carried (in hand), 2 attached (on hook).
	var rope := MeshInstance3D.new()
	rope.mesh = ImmediateMesh.new()
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(ART + "rope_tex.png")   # real steel-cable art
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.4
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	m.emission_enabled = true
	m.emission = Color(0.0, 0.0, 0.0)          # turns red when grabbable
	rope.material_override = m
	add_child(rope)
	_ropes.append({"node": rope, "heli": heli, "phase": randf() * 6.28,
		"hang": hang, "state": 0, "mat": m})


func _update_rope() -> void:
	for rd in _ropes:
		var heli = rd["heli"]   # untyped: a crashed chopper may be freed
		if not is_instance_valid(heli):
			continue
		var hp: Vector3 = heli.global_position
		var top := Vector3(hp.x + 1.0, hp.y - 2.2, hp.z + 0.4)
		# free end: hangs at its own spot / in the player's hand / on the hook
		var st: int = rd["state"]
		var bottom: Vector3 = rd["hang"]
		if st == 1 and player != null:        # carried
			bottom = player.global_position + Vector3(0.0, 3.2, 0.4)
		elif st == 2:                          # attached to the hook
			bottom = _hook_pos
		# red glow once the squad is dead and the rope is still grabbable/free
		var mat: StandardMaterial3D = rd["mat"]
		if _finale_state >= 1 and _finale_state <= 2 and st == 0:
			mat.emission = Color(1.0, 0.0, 0.0) * (0.6 + 0.4 * sin(_heli_t * 6.0))
		else:
			mat.emission = Color(0, 0, 0)
		var N := 20
		var ph: float = rd["phase"]
		var swayamp := 0.30 if st == 0 else 0.06   # taut once grabbed/attached
		var rope_len := top.distance_to(bottom)
		var vtiles := rope_len / 2.2                # how many cable repeats down it
		var im: ImmediateMesh = rd["node"].mesh
		im.clear_surfaces()
		im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
		var halfw := 0.16
		for i in N + 1:
			var t := float(i) / float(N)
			var base := top.lerp(bottom, t)
			var bell := t * (1.0 - t) * 4.0          # peaks mid-rope, 0 at the ends
			var sway := sin(_heli_t * 2.2 + ph + t * 4.5) * bell * swayamp
			var v := t * vtiles
			im.surface_set_normal(Vector3(0, 0, 1))
			im.surface_set_uv(Vector2(0.0, v))
			im.surface_add_vertex(Vector3(base.x - halfw + sway, base.y, base.z))
			im.surface_set_uv(Vector2(1.0, v))
			im.surface_add_vertex(Vector3(base.x + halfw + sway, base.y, base.z))
		im.surface_end()


func _fire_red(from: Vector3) -> void:
	# A glowing red machine-gun tracer streaking toward the hero.
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.13, 1.5, 0.13)   # narrow tracer
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 0.12, 0.08)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.3, 0.12)
	m.emission_energy_multiplier = 8.0
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = m
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	add_child(mi)
	mi.global_position = from
	# aim straight at the hero (chest), with a little spread so it sprays
	var dir := Vector3(-1.0, -0.6, 0.0)
	if player != null:
		dir = (player.global_position + Vector3(0.0, 2.5, 0.0) - from).normalized()
	dir += Vector3(randf_range(-0.02, 0.02), randf_range(-0.015, 0.015), randf_range(-0.02, 0.02))
	# orient the tracer along its travel
	if dir.length() > 0.01:
		mi.look_at(from + dir, Vector3.UP)
		mi.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	_red_shots.append({"node": mi, "vel": dir.normalized() * 11.0, "life": 4.0})


func _make_heli_frames() -> SpriteFrames:
	var sf := SpriteFrames.new()
	sf.remove_animation(&"default")
	sf.add_animation(&"fly")
	sf.set_animation_loop(&"fly", true)
	sf.set_animation_speed(&"fly", 30.0)
	# 36 cross-fade interpolated frames -> smooth rotor spin (~1.2s loop).
	for i in 36:
		var t: Texture2D = load(ART + "heli_%d.png" % i)
		if t == null:
			break
		sf.add_frame(&"fly", t)
	return sf

func _build_heli() -> void:
	# Three gunships hovering in the open sky by the crane — the staging for the
	# crash-mission finale. They hold position with a gentle hover bob.
	var sf := _make_heli_frames()
	# x, y, z, scale, bob-speed, bob-phase  (spread across the sky near the crane)
	# High up in the sky (above the skyline), well back from the rooftop.
	# x, y, z, scale, bob-speed, bob-phase, fire-cooldown
	# Positioned in the sky but OVER the playable area near the crane, so each
	# rope hangs down to a reachable hang point where a black-suit dangles.
	var fleet := [
		[CRANE_X - 72.0, 19.0, -4.0, 0.020, 0.8, 0.0, 1.3],
		[CRANE_X - 52.0, 21.0, 2.0, 0.018, 0.6, 1.7, 1.6],
		[CRANE_X - 34.0, 17.0, -9.0, 0.022, 0.9, 3.1, 1.1],
	]
	for spec in fleet:
		var h := AnimatedSprite3D.new()
		h.sprite_frames = sf
		h.pixel_size = float(spec[3])
		h.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		h.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		h.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		h.play(&"fly")
		h.frame = randi() % 36
		add_child(h)
		var base := Vector3(float(spec[0]), float(spec[1]), float(spec[2]))
		h.global_position = base
		# Gun muzzle: the rotary minigun hangs at the FRONT-BOTTOM (the chopper
		# faces left) — measured ~x4%, y89% of the frame, i.e. far left and low.
		var ftex: Texture2D = sf.get_frame_texture(&"fly", 0)
		var w := float(spec[3]) * float(ftex.get_width())
		var hh := float(spec[3]) * float(ftex.get_height())
		var gun := Vector3(-0.46 * w, -0.39 * hh, 0.4)
		var hang := Vector3(base.x + 1.0, 3.5, base.z + 0.4)   # where the rope ends
		_helis.append({"node": h, "base": base, "spd": float(spec[4]),
			"phase": float(spec[5]), "fire_cd": float(spec[6]), "fire_t": randf() * 2.0,
			"gun": gun, "hang": hang})
		_build_rope(h, hang)   # every gunship drops a rope


func _build_player_and_camera() -> void:
	player = PlayerScene.instantiate()
	player.position = Vector3(X_START, 0.2, 4.0)
	# widen the playable bounds for the long stage
	player.set("PLAY_X_MIN", -2.0)
	player.set("PLAY_X_MAX", X_END)
	player.set("PLAY_Z_MIN", -18.0)  # can walk back to the crane (z=-20)
	player.set("PLAY_Z_MAX", 10.0)   # keep the player back from the front edge
	add_child(player)

	var cam := Camera3D.new()
	cam.rotation_degrees = Vector3(-12, 0, 0)   # down-tilt enough to show the facade
	cam.position = Vector3(0, 6.2, 17.5)
	player.add_child(cam)
	cam.current = true
	_cam = cam


func _spawn_villains() -> void:
	# Waves spread across the stage; every 3rd is a gunner.
	var rng := RandomNumberGenerator.new()
	rng.seed = 33
	var x := 24.0
	var i := 0
	while x < X_END - 8.0:
		var v := VillainScene.instantiate()
		v.position = Vector3(x + rng.randf_range(-3.0, 3.0), 0.2, rng.randf_range(0.0, 10.0))
		if i % 3 == 2:
			v.set("is_gunner", true)
		add_child(v)
		v.set("state_timer", randf_range(1.5, 8.0))
		x += rng.randf_range(14.0, 22.0)
		i += 1


# ── ART HELPERS (mirror main.gd, rooted at the citymap folder) ─────────────────
func _art(file: String, height: float, pos: Vector3, dim := 1.0, flip := false) -> MeshInstance3D:
	return _art_tex(load(ART + file), height, pos, dim, flip)

func _art_tex(tex: Texture2D, height: float, pos: Vector3, dim := 1.0, flip := false) -> MeshInstance3D:
	if tex == null:
		return null
	var w := height * float(tex.get_width()) / float(tex.get_height())
	var mi := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(w, height)
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.albedo_color = Color(dim, dim, dim)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.5
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if flip:
		m.uv1_scale = Vector3(-1.0, 1.0, 1.0)   # mirror horizontally
		m.uv1_offset = Vector3(1.0, 0.0, 0.0)
	quad.material = m
	mi.mesh = quad
	mi.position = pos + Vector3(0, height * 0.5, 0)
	add_child(mi)
	return mi


# ── HUD (same health bar as the harbor map) ───────────────────────────────────
func _build_hud() -> void:
	var frame_tex: Texture2D = load("res://assets/ui/health_bar.png")
	if frame_tex == null:
		return
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	const FRAME_W := 400.0
	const PX := 6.0
	const PY := 6.0
	var fw := FRAME_W
	var fh := FRAME_W * float(frame_tex.get_height()) / float(frame_tex.get_width())
	var bar_x := PX + 0.280 * fw
	var bar_y := PY + 0.411 * fh
	var bar_w := 0.660 * fw
	var bar_h := 0.233 * fh
	var bg := ColorRect.new()
	bg.color = Color(0.10, 0.0, 0.0, 0.85)
	bg.position = Vector2(bar_x, bar_y); bg.size = Vector2(bar_w, bar_h)
	layer.add_child(bg)
	_hud_health_fill = ColorRect.new()
	_hud_health_fill.color = Color(0.88, 0.10, 0.10, 1.0)
	_hud_health_fill.position = Vector2(bar_x, bar_y); _hud_health_fill.size = Vector2(bar_w, bar_h)
	_hud_bar_full_w = bar_w
	layer.add_child(_hud_health_fill)
	var frame_rect := TextureRect.new()
	frame_rect.texture = frame_tex
	frame_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	frame_rect.stretch_mode = TextureRect.STRETCH_SCALE
	frame_rect.position = Vector2(PX, PY); frame_rect.size = Vector2(fw, fh)
	layer.add_child(frame_rect)

	# ── ability cooldown timers, top-right ───────────────────────────────
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	box.offset_left = -300.0; box.offset_top = 12.0; box.offset_right = -14.0
	box.add_theme_constant_override("separation", 4)
	layer.add_child(box)
	_hud_leap_lbl = _make_cd_label()
	_hud_punch_lbl = _make_cd_label()
	box.add_child(_hud_leap_lbl)
	box.add_child(_hud_punch_lbl)

	# "Press E to operate the crane" prompt (hidden until the squad is dead)
	_hud_prompt = Label.new()
	_hud_prompt.text = "▸ PRESS  E  TO OPERATE THE CRANE"
	_hud_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hud_prompt.offset_left = -300.0; _hud_prompt.offset_right = 300.0
	_hud_prompt.offset_top = -110.0; _hud_prompt.offset_bottom = -70.0
	_hud_prompt.add_theme_font_size_override("font_size", 30)
	_hud_prompt.add_theme_color_override("font_color", Color(1.0, 0.92, 0.35))
	_hud_prompt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	_hud_prompt.add_theme_constant_override("outline_size", 6)
	_hud_prompt.visible = false
	layer.add_child(_hud_prompt)

	# tug-of-war bar (hidden until the tug stage)
	_tug_bg = ColorRect.new()
	_tug_bg.color = Color(0.08, 0.08, 0.10, 0.85)
	_tug_bg.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_tug_bg.offset_left = -262.0; _tug_bg.offset_right = 262.0
	_tug_bg.offset_top = -160.0; _tug_bg.offset_bottom = -128.0
	_tug_bg.visible = false
	layer.add_child(_tug_bg)
	_tug_fill = ColorRect.new()
	_tug_fill.color = Color(1.0, 0.85, 0.25, 1.0)
	_tug_fill.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_tug_fill.offset_left = -260.0; _tug_fill.offset_right = -260.0 + 520.0
	_tug_fill.offset_top = -158.0; _tug_fill.offset_bottom = -130.0
	_tug_fill.visible = false
	layer.add_child(_tug_fill)

	await get_tree().process_frame
	if player != null and player.has_signal("hp_changed"):
		player.connect("hp_changed", _on_player_hp_changed)

func _make_cd_label() -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.add_theme_font_size_override("font_size", 22)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 5)
	return l

func _update_ability_hud() -> void:
	if _hud_leap_lbl == null or player == null:
		return
	var lcd: float = player.get("_super_leap_cd")
	var pcd: float = player.get("_super_punch_cd")
	if lcd <= 0.0:
		_hud_leap_lbl.text = "SUPER LEAP  ✦ READY"
		_hud_leap_lbl.add_theme_color_override("font_color", Color(0.4, 1.0, 0.5))
	else:
		_hud_leap_lbl.text = "SUPER LEAP  %.1fs" % lcd
		_hud_leap_lbl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9))
	if pcd <= 0.0:
		_hud_punch_lbl.text = "SUPER PUNCH  ✦ READY"
		_hud_punch_lbl.add_theme_color_override("font_color", Color(0.4, 1.0, 0.5))
	else:
		_hud_punch_lbl.text = "SUPER PUNCH  %.1fs" % pcd
		_hud_punch_lbl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9))

func _on_player_hp_changed(ratio: float) -> void:
	if _hud_health_fill == null:
		return
	var tween := create_tween()
	tween.tween_property(_hud_health_fill, "size:x", _hud_bar_full_w * maxf(ratio, 0.0), 0.15)
