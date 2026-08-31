extends Node3D

# Map 1 scene rig (placeholder colors, no art yet):
# sky gradient + fog, 3 parallax building layers, reflective ground, lights.
# Walk it to feel depth/atmosphere; real art (Nano Banana billboards) swaps in later.

const PlayerScene  := preload("res://scenes/player.tscn")
const VillainScene := preload("res://scenes/villain.tscn")
const TouchControlsScene := preload("res://scenes/touch_controls.tscn")

# Depth layers (Z, negative = farther back). Each layer parallaxes naturally
# because it's real 3D placed at distance; closer = moves past faster as you walk.
const SKYLINE_Z := -95.0      # far sea horizon band
const DOCK_EDGE_Z := -20.0    # where the deck meets the water (props sit here)
const DECK_FRONT_Z := 8.0     # front lip of the deck (near the camera)
const WATER_Y := -0.6         # ocean surface, just below the deck

func _ready() -> void:
	_build_sky_and_fog()
	_build_lights()
	_build_ground()
	_build_ocean()
	_build_harbor()
	_build_foreground()
	_build_rain()
	_build_player_and_camera()
	# Mobile touch overlay (CanvasLayer; visible only on touch devices unless forced).
	add_child(TouchControlsScene.instantiate())
	_build_hud()

func _build_sky_and_fog() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()

	# Flat steel-grey background matched to the painted backdrop, so any area beyond
	# the backdrop edges blends in instead of showing a gap.
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.40, 0.43, 0.47)

	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.58, 0.64)
	env.ambient_light_energy = 0.9   # flat overcast bounce

	# Cold grey haze — heavy rain in the air, distance washes out.
	env.fog_enabled = true
	env.fog_light_color = Color(0.22, 0.24, 0.27)
	env.fog_density = 0.010
	env.fog_sky_affect = 0.5

	# Restrained glow — wet highlights and the few dock/ship lights bloom softly.
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.1
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC

	we.environment = env
	add_child(we)

func _build_lights() -> void:
	# Overcast key: weak, cold, diffuse — no sun, just grey daylight through cloud.
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-60, -20, 0)
	sun.light_color = Color(0.62, 0.66, 0.74)
	sun.light_energy = 0.7
	sun.shadow_enabled = true
	add_child(sun)

	# Cold cyan dock light so the character reads against the grey.
	var fill := OmniLight3D.new()
	fill.position = Vector3(6, 4, 6)
	fill.light_color = Color(0.45, 0.75, 0.95)
	fill.light_energy = 1.8
	fill.omni_range = 22.0
	add_child(fill)

	# A single dim amber sodium dock lamp — lonely warmth in the cold.
	var rim := OmniLight3D.new()
	rim.position = Vector3(-7, 5, -6)
	rim.light_color = Color(1.0, 0.6, 0.25)
	rim.light_energy = 1.6
	rim.omni_range = 24.0
	add_child(rim)

func _build_ground() -> void:
	# Collision floor (invisible plane).
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	col.shape = WorldBoundaryShape3D.new()
	body.add_child(col)
	add_child(body)

	# Visible DECK = a grid of flat textured tiles, randomly chosen from the set
	# (1 metal + 3 wet-concrete) so the floor reads as a real wet dock, not a void.
	var floor_dir := "res://assets/sprites/env/floor/"
	var tiles := ["metal", "concrete1", "concrete2", "concrete3"]
	var mats: Array[StandardMaterial3D] = []
	for t in tiles:
		var m := StandardMaterial3D.new()
		m.albedo_texture = load(floor_dir + t + ".png")
		m.metallic = 0.35          # wet sheen so the dock lights play on it
		m.roughness = 0.45
		mats.append(m)

	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var cell := 6.0
	var quad := QuadMesh.new()
	quad.size = Vector2(cell, cell)
	# Cover the whole visible ground: wide on the sides and well toward the camera
	# (positive Z) so there's no grey gap in the foreground or at the edges.
	var x := -102.0
	while x < 102.0:
		var z := -18.0
		while z < 44.0:
			var mi := MeshInstance3D.new()
			mi.mesh = quad
			mi.material_override = mats[rng.randi() % mats.size()]
			mi.rotation_degrees = Vector3(-90, 0, 0)   # lay flat
			mi.position = Vector3(x + cell * 0.5, 0.0, z + cell * 0.5)
			add_child(mi)
			z += cell
		x += cell

func _build_ocean() -> void:
	# Dark harbor water with gentle rolling waves + rippling surface (shader-driven).
	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(400, 220)
	plane.subdivide_width = 100        # enough geometry for the vertex waves
	plane.subdivide_depth = 60
	mesh.position = Vector3(0, WATER_Y, DOCK_EDGE_Z - 100.0)

	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode specular_schlick_ggx;
uniform vec3 deep_col : source_color = vec3(0.02, 0.06, 0.12);
uniform vec3 shallow_col : source_color = vec3(0.07, 0.16, 0.26);
uniform float speed = 0.6;
uniform float wave_height = 0.35;

float wsum(vec2 p, float t) {
	return sin(p.x * 0.25 + t) * 0.5
		 + sin(p.y * 0.4 + t * 1.3) * 0.35
		 + sin((p.x + p.y) * 0.18 + t * 0.7) * 0.4;
}
void vertex() {
	float t = TIME * speed;
	VERTEX.y += wsum(VERTEX.xz, t) * wave_height;
}
void fragment() {
	float t = TIME * speed;
	vec2 uv = UV * 60.0;
	// small rippling normal so the surface shimmers and reflects
	float nx = sin(uv.x * 1.7 + t * 2.0) + sin(uv.y * 0.9 - t * 1.4);
	float ny = cos(uv.y * 1.5 - t * 1.8) + sin(uv.x * 1.1 + t * 1.1);
	NORMAL_MAP = normalize(vec3(nx * 0.25 + 0.5, ny * 0.25 + 0.5, 1.0));
	NORMAL_MAP_DEPTH = 0.6;
	float crest = clamp(wsum(VERTEX.xz, t) * 0.5 + 0.5, 0.0, 1.0);
	ALBEDO = mix(deep_col, shallow_col, crest);
	METALLIC = 0.85;
	ROUGHNESS = 0.12;
	EMISSION = deep_col * 0.4;
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	plane.material = m
	mesh.mesh = plane
	add_child(mesh)

# A flat upright billboard quad standing on the ground at a given depth.
# Placeholder uses a flat emissive color; later we swap in a Nano Banana texture.
func _billboard(width: float, height: float, pos: Vector3, color: Color, emit: float) -> void:
	var mi := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(width, height)
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = emit > 0.0
	m.emission = color
	m.emission_energy_multiplier = emit
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA  # real art will have alpha edges
	quad.material = m
	mi.mesh = quad
	# Stand it up: quad faces +Z by default, sits with its base on the ground.
	mi.position = pos + Vector3(0, height * 0.5, 0)
	add_child(mi)

# Textured upright billboard sized by the art's aspect ratio. Unshaded so the
# painted lighting in the concept art is preserved; modulate dims it for depth.
const ENV := "res://assets/sprites/env/"
func _art(file: String, height: float, pos: Vector3, dim := 1.0, flip := false) -> void:
	var tex: Texture2D = load(ENV + file)
	if tex == null:
		return
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
	quad.material = m
	mi.mesh = quad
	mi.position = pos + Vector3(0, height * 0.5, 0)
	if flip:
		mi.scale.x = -1.0
	add_child(mi)

# Same as _art() but also adds a solid StaticBody3D so the player and villains
# are blocked by the prop. col_w/col_h are the collision box size; depth is thin.
func _art_solid(file: String, height: float, pos: Vector3, dim := 1.0,
		col_w := 0.0, col_h := 0.0) -> void:
	_art(file, height, pos, dim)
	var tex: Texture2D = load(ENV + file)
	if tex == null:
		return
	var vis_w := height * float(tex.get_width()) / float(tex.get_height())
	var bw := col_w if col_w > 0.0 else vis_w * 0.7
	var bh := col_h if col_h > 0.0 else height * 0.5   # block lower half
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask  = 0
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(bw, bh, 0.9)
	col.shape = box
	body.add_child(col)
	# centre the box on the lower half of the sprite
	body.position = pos + Vector3(0.0, bh * 0.5, 0.0)
	add_child(body)

# A flat decal lying on the ground (quad rotated to the XZ plane).
func _floor_decal(file: String, size: float, pos: Vector3) -> void:
	var tex: Texture2D = load(ENV + file)
	if tex == null:
		return
	var h := size * float(tex.get_height()) / float(tex.get_width())
	var mi := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(size, h)
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.5
	quad.material = m
	mi.mesh = quad
	mi.rotation_degrees = Vector3(-90, 0, 0)   # lay flat on the deck
	mi.position = pos + Vector3(0, 0.02, 0)
	add_child(mi)

const CONT_CH := 6.0                          # one container's on-screen height
const CONT_W := CONT_CH * 0.553               # matching width (art aspect ~561x1014)

# A solid PACKED block of containers: `cols` wide x `levels` high, touching with
# no internal gaps — like one stack block in a real container yard.
func _container_block(x0: float, z: float, cols: int, levels: int, dim: float) -> void:
	for c in range(cols):
		var col_h := levels
		if (c % 3) == 1: col_h = maxi(1, levels - 1)
		for lvl in range(col_h):
			var k := (int(abs(x0)) + c * 2 + lvl) % 5
			var d := dim * (1.0 - lvl * 0.03)
			# tiny per-column z stagger so no two billboards are exactly coplanar
			_art("container_%d.png" % k, CONT_CH,
				Vector3(x0 + c * CONT_W, lvl * CONT_CH, z + c * 0.12), d, (c + lvl) % 2 == 0)

func _build_harbor() -> void:
	# FAR backdrop: very wide + tall so it always fills the screen at the edges.
	_art("backdrop.png", 170, Vector3(0, -34, SKYLINE_Z), 0.9)

	# HERO SHIP: pushed far back into the water, smaller so the full silhouette reads.
	_art("ship.png", 46, Vector3(-32, -4.5, -52.0), 1.0)

	# CONTAINER YARD — right side, clear of the mobile crane area
	# 2-wide + 1 on top stacking (pyramid feel, not flat wall)
	_container_block(8.0,   -22.0, 4, 3, 0.8)    # back-left block
	_container_block(36.0,  -25.0, 3, 4, 0.66)   # far-back right

	# CRANES
	# STS portal gantry: pushed behind dock edge toward ship so it reads behind the dock floor
	_art("crane_0.png", 46, Vector3(6, 3.0, -34.0), 0.84)
	# Pedestal knuckle-boom: right apron, sunk 2u so base reads grounded
	_art("crane_1.png", 22, Vector3(40, -2.0, DOCK_EDGE_Z + 1.0), 0.85)
	# Mobile excavator: smaller
	_art("crane_2.png", 15, Vector3(28, 0, -8.0), 0.97)

	# BOARD: holographic warning sign hung elevated near gantry base
	_art("light_2.png", 6.0, Vector3(-6, 5.5, -9.0), 1.0)

	# NOTE: arena props (box stacks, scatter, lamps) are all placed in
	# _build_foreground() now, deliberately kept OUT of the fighting lane so the
	# player can run the full width. The container yard, cranes, ship and backdrop
	# above still frame the scene from the background.

func _build_foreground() -> void:
	# Decoration philosophy: dense, evenly-spread props EVERYWHERE except the
	# fighting arena. The arena (X -42..44, Z roughly -6..12) stays OPEN so you can
	# run the full width. Blocking (_art_solid) props sit only on the back line and
	# as a couple of off-centre cover crates — never across the running corridor.
	# High-Z central props (which would sit between camera and player) are avoided.
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var deco := ["prop_0", "prop_1", "prop_3", "prop_4", "prop_5",
			"prop_7", "prop_8", "prop_9", "prop_10", "prop_11"]

	# ── OOB SIDE FIELDS — dense even decoration where the player can't go ──────
	# Left field and right field, a prop column every ~10u out to X ±150, with 3
	# props per column at staggered depths, dimmed by distance.
	for side in [-1.0, 1.0]:
		var xi := 50.0
		while xi <= 150.0:
			var x: float = side * xi
			var ddim := clampf(0.95 - (xi - 50.0) / 150.0, 0.45, 0.9)
			_art(deco[rng.randi() % deco.size()] + ".png", rng.randf_range(3.0, 5.0),
					Vector3(x, 0, rng.randf_range(-12.0, -5.0)), ddim)
			_art(deco[rng.randi() % deco.size()] + ".png", rng.randf_range(2.2, 3.6),
					Vector3(x + rng.randf_range(-3.0, 3.0), 0, rng.randf_range(-2.0, 6.0)), ddim)
			_art(deco[rng.randi() % deco.size()] + ".png", rng.randf_range(1.8, 3.0),
					Vector3(x + rng.randf_range(-3.0, 3.0), 0, rng.randf_range(8.0, 16.0)), ddim * 0.95)
			xi += 10.0

	# ── LAMP POSTS — evenly every ~24u across the WHOLE width (tall, visual) ───
	var lx := -144.0
	while lx <= 144.0:
		var ldim := clampf(1.0 - maxf(absf(lx) - 46.0, 0.0) / 140.0, 0.5, 1.0)
		_art("light_0.png", 9.0, Vector3(lx, 0, -7.0), ldim)
		lx += 24.0
	_art("light_4.png", 5.0, Vector3(-46, 0, 11.0), 0.9)   # arena-edge accents
	_art("light_4.png", 5.0, Vector3( 46, 0, 11.0), 0.9)

	# ── CRANE HOOKS hanging high above the action (visual) ────────────────────
	for hx in [-120.0, -70.0, -48.0, 48.0, 70.0, 120.0]:
		var hdim := clampf(0.9 - (absf(hx) - 48.0) / 150.0, 0.5, 0.85)
		_art("prop_6.png", 4.5, Vector3(hx, 6.5, -4.0), hdim)

	# ── BACK LINE — solid crate/barrel cover along the arena's far edge ───────
	# Spaced ~22u apart at Z -8: gives a back wall and collision to bump into,
	# with wide gaps so movement is never funnelled.
	var bx := -40.0
	while bx <= 40.0:
		_art_solid(deco[rng.randi() % deco.size()] + ".png",
				rng.randf_range(2.8, 3.6), Vector3(bx, 0, -8.0))
		bx += 22.0

	# ── BACKGROUND SCATTER behind the back line (visual only) ─────────────────
	var sx := -42.0
	while sx <= 42.0:
		_art(deco[rng.randi() % deco.size()] + ".png", rng.randf_range(2.0, 3.2),
				Vector3(sx + rng.randf_range(-4.0, 4.0), 0, rng.randf_range(-13.0, -10.0)), 0.8)
		sx += 14.0

	# ── A FEW OFF-CENTRE COVER CRATES — far apart, leaving the centre clear ───
	_art_solid("prop_1.png", 3.4, Vector3(-34, 0, 9.5))
	_art_solid("prop_5.png", 3.0, Vector3( 34, 0, 9.5))

var _hud_health_fill: ColorRect = null
var _hud_bar_full_w  := 0.0
var _hud_leap_lbl: Label = null
var _hud_punch_lbl: Label = null
var _hud_player: Node = null

func _build_hud() -> void:
	var frame_tex: Texture2D = load("res://assets/ui/health_bar.png")
	if frame_tex == null:
		push_warning("HUD: health_bar.png failed to load")
		return
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)

	# Fixed on-screen size, tucked flush into the top-left corner.
	const FRAME_W := 400.0
	const PX := 6.0
	const PY := 6.0
	var fw := FRAME_W
	var fh := FRAME_W * float(frame_tex.get_height()) / float(frame_tex.get_width())

	# Bar cavity inside the frame — fractions measured from health.png:
	# x 0.280-0.940 (w 0.660), y 0.411-0.644 (h 0.233).
	var bar_x := PX + 0.280 * fw
	var bar_y := PY + 0.411 * fh
	var bar_w := 0.660 * fw
	var bar_h := 0.233 * fh

	# Dark empty-bar background (shows through when HP is low)
	var bg := ColorRect.new()
	bg.color    = Color(0.10, 0.0, 0.0, 0.85)
	bg.position = Vector2(bar_x, bar_y)
	bg.size     = Vector2(bar_w, bar_h)
	layer.add_child(bg)

	# Red health fill (shrinks right-to-left as HP drops)
	_hud_health_fill          = ColorRect.new()
	_hud_health_fill.color    = Color(0.88, 0.10, 0.10, 1.0)
	_hud_health_fill.position = Vector2(bar_x, bar_y)
	_hud_health_fill.size     = Vector2(bar_w, bar_h)
	_hud_bar_full_w           = bar_w
	layer.add_child(_hud_health_fill)

	# Frame PNG on top (transparent center after magenta key)
	var frame_rect := TextureRect.new()
	frame_rect.texture      = frame_tex
	frame_rect.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	frame_rect.stretch_mode = TextureRect.STRETCH_SCALE
	frame_rect.position     = Vector2(PX, PY)
	frame_rect.size         = Vector2(fw, fh)
	layer.add_child(frame_rect)

	# ability cooldown timers, top-right
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	box.offset_left = -300.0; box.offset_top = 12.0; box.offset_right = -14.0
	box.add_theme_constant_override("separation", 4)
	layer.add_child(box)
	_hud_leap_lbl = _make_cd_label()
	_hud_punch_lbl = _make_cd_label()
	box.add_child(_hud_leap_lbl)
	box.add_child(_hud_punch_lbl)

	# Connect to player hp_changed signal once the player node is ready
	await get_tree().process_frame
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		_hud_player = players[0]
		players[0].connect("hp_changed", _on_player_hp_changed)

func _make_cd_label() -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.add_theme_font_size_override("font_size", 22)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 5)
	return l

func _process(_delta: float) -> void:
	if _hud_leap_lbl == null or _hud_player == null:
		return
	var lcd: float = _hud_player.get("_super_leap_cd")
	var pcd: float = _hud_player.get("_super_punch_cd")
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

func _build_rain() -> void:
	# Heavy rain over the play area: many fast thin streaks falling straight down.
	var rain := GPUParticles3D.new()
	rain.amount = 1800
	rain.lifetime = 1.2
	rain.position = Vector3(0, 24, 0)   # emit from high above the deck
	rain.visibility_aabb = AABB(Vector3(-60, -30, -60), Vector3(120, 60, 120))

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(90, 1, 60)   # full scene coverage
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 2.0
	pm.gravity = Vector3(0, -14, 0)
	pm.initial_velocity_min = 7.0
	pm.initial_velocity_max = 10.0
	rain.process_material = pm

	# Each drop is a small thin streak.
	var streak := QuadMesh.new()
	streak.size = Vector2(0.02, 0.5)
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.7, 0.8, 0.95, 0.3)
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	sm.billboard_keep_scale = true
	streak.material = sm
	rain.draw_pass_1 = streak
	add_child(rain)

func _build_player_and_camera() -> void:
	var player := PlayerScene.instantiate()
	player.position = Vector3(0, 0.2, 0)
	add_child(player)

	# Side-on, slightly raised, partial-isometric beat-'em-up angle.
	var cam := Camera3D.new()
	cam.rotation_degrees = Vector3(-14, 0, 0)
	cam.position = Vector3(0, 5.5, 16)
	player.add_child(cam)
	cam.current = true

	var spawn_points := [
		Vector3( 8,  0.2,  4), Vector3(-8,  0.2,  4),
		Vector3(14,  0.2,  2), Vector3(-14, 0.2,  2),
		Vector3( 5,  0.2,  8), Vector3(-5,  0.2,  8),
		Vector3(18,  0.2,  6), Vector3(-18, 0.2,  6),
		Vector3(11,  0.2, 10), Vector3( 0,  0.2, 10),
	]
	for i in spawn_points.size():
		var v := VillainScene.instantiate()
		v.position = spawn_points[i]
		if i >= 7:   # last 3 spawn points get gun villains
			v.set("is_gunner", true)
		add_child(v)
		v.set("state_timer", randf_range(1.5, 6.0))
