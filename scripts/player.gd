extends CharacterBody3D

# Paper-style brawler player.
# Move:   WASD / arrows   (run kicks in after RUN_DELAY of horizontal walking)
# Jump:   Space
# Punch:  J  (alternates punch / punch2, continuous)
# Super:  H  (forward lunge)
# Kick:   K  (alternates kick / stylish kick, continuous)
# Air:    Space+J = jump-punch slam (high),  Space+K = jump-kick (low)

const SPEED := 6.0
const RUN_SPEED := 10.0
const GRAVITY := 20.0
const JUMP_VELOCITY := 9.0
const SUPER_SPEED := 14.0
const RUN_DELAY := 0.7              # seconds of horizontal walking before running
const SLAM_JUMP_VELOCITY := 15.0    # high arc for jump-punch
const KICK_JUMP_VELOCITY := 11.0    # lower arc for jump-kick
const SLAM_GRAVITY := 34.0          # comes down hard
# Apex height scales with v^2 (at ascent GRAVITY). Normal jump h = 9^2/(2*20).
const DOUBLE_JUMP_VELOCITY := 12.7  # ~sqrt(2)*JUMP_VELOCITY  -> 2x normal height
const SUPER_LEAP_VELOCITY  := 22.0  # ~sqrt(6)*JUMP_VELOCITY  -> 6x normal height

# Playable bounds — defaults match the harbor; a level (e.g. the wide city)
# overrides these after instantiating the player.
var PLAY_X_MIN := -42.0
var PLAY_X_MAX := 44.0
var PLAY_Z_MIN := -14.0
var PLAY_Z_MAX := 22.0

signal attack_hit(type: String)

const GHOST_INTERVAL := 0.05
const GHOST_LIFE     := 0.45
const GHOST_ALPHA    := 0.45
const HOLO_COLOR     := Color(0.35, 0.9, 1.0)
var _holo_cache: Dictionary = {}     # source Texture2D -> holographic ImageTexture

@onready var sprite: AnimatedSprite3D = $Sprite

var attacking := false       # ground punch/kick (movement allowed)
var super_active := false    # super punch (locks movement, lunges)
var air_attacking := false   # jump-punch / jump-kick in progress
var face_left := false
var j_prev := false
var h_prev := false
var k_prev := false
var g_prev := false
var space_prev := false
var jumps_used := 0          # 0 on ground; 1 after first jump; 2 after double jump
var super_leap := false      # current jump-punch is the 6x leap (big impact landing)
var shake_timer := 0.0
var shake_strength := 0.0
var _cam: Camera3D = null
var punch_toggle := false
var kick_toggle := false
var was_in_air := false
var run_timer := 0.0         # how long we've been walking horizontally
var land_hold_timer := 0.0   # holds air-attack landing pose briefly
var _ghost_timer := 0.0
var _ghosts: Array = []

# --- hit reaction ---
# consecutive hits taken from a villain WITHOUT hitting back:
#   1st -> block pose (fall frame 0), 2nd -> pushed-back pose (fall frame 1),
#   3rd -> full knockdown (fall 2..7) then wake-up (wake 0..5).
var consecutive_hits := 0
var stun_timer := 0.0        # brief freeze on block / pushed poses
var downed := false          # knocked down: full fall+wake sequence, no control
var waking := false          # currently playing the wake-up half
var invincible_timer := 0.0  # brief iframes after each hit so mobs can't chain
var air_attack_anim_done := false  # jumppunch/jumpkick anim finished while still airborne
var gun_active := false

# laser projectile state
var _laser: MeshInstance3D = null
var _laser_vel := Vector3.ZERO
var _laser_life := 0.0
var _laser_hit_set: Dictionary = {}   # tracks already-hit villains per shot

const SLAM_AOE_RADIUS := 8.0

const MAX_HP         := 100.0
const GUN_DMG        := 20.0     # 5 shots = full bar depleted
const MELEE_DMG      := 7.0      # a villain punch/kick chips the bar
const SUPER_LEAP_CD  := 8.0
const SUPER_PUNCH_CD := 7.0
const ENEMY_GUN_DMG     := 6.5   # enemy laser dmg to player (~15 hits = down)
const HELI_HIT_CD       := 0.5   # min gap between heli hits (throttle the stream)
const HELI_HITS_TO_DOWN := 10    # exactly 10 silent heli hits before the hero falls
const HP_REGEN          := 2.0   # HP regenerated per second when not knocked down

var hp               := MAX_HP
var _heli_hit_cd     := 0.0
var _heli_hit_count  := 0        # counts silent heli hits; resets on wake
var _regen_emit_t    := 0.0
var _super_leap_cd   := 0.0
var _super_punch_cd  := 0.0

signal hp_changed(ratio: float)

func _ready() -> void:
	add_to_group("player")
	collision_layer = 1
	collision_mask  = 1   # only ground — villains are layer 2, never block movement
	_add_hit_anims()
	_add_gun_anim()
	_add_regular_jump_punch_anim()
	sprite.animation_finished.connect(_on_anim_finished)
	_build_holo_cache()

func _add_gun_anim() -> void:
	var sf := sprite.sprite_frames
	var BASE := "res://assets/sprites/player/gun/"
	if sf.has_animation(&"gun"):
		return
	# Only register if all three frames exist on disk — avoids a broken animation
	# that never finishes and permanently locks the player.
	var frames: Array[Texture2D] = []
	for i in 3:
		var t: Texture2D = load(BASE + "gun_%d.png" % i)
		if t == null:
			return   # sprites not generated yet — skip silently
		frames.append(t)
	sf.add_animation(&"gun")
	sf.set_animation_loop(&"gun", false)
	sf.set_animation_speed(&"gun", 9.0)
	for t in frames:
		sf.add_frame(&"gun", t)

func _build_holo_cache() -> void:
	# Pre-tint the attack frames (the only ones that spawn ghosts) into flat
	# holographic textures, so there's no per-spawn CPU hitch.
	var sf := sprite.sprite_frames
	for anim in [&"jumppunch", &"jumpkick", &"super", &"regularjumppunch"]:
		if not sf.has_animation(anim):
			continue
		for i in sf.get_frame_count(anim):
			var tex := sf.get_frame_texture(anim, i)
			if tex != null:
				_holo_tex(tex)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN:
		# Reset all edge-detection flags so no phantom edges fire on first frame back.
		# Also flush Godot's internal input buffer which can hold stale key states.
		j_prev = false
		h_prev = false
		k_prev = false
		g_prev = false
		space_prev = false
		Input.flush_buffered_events()

func _add_hit_anims() -> void:
	var sf := sprite.sprite_frames
	var BASE := "res://assets/sprites/player/fall/"
	if not sf.has_animation(&"fall"):
		sf.add_animation(&"fall")
		sf.set_animation_loop(&"fall", false)
		sf.set_animation_speed(&"fall", 10.0)
		for i in 8:
			sf.add_frame(&"fall", load(BASE + "fall_%d.png" % i))
	if not sf.has_animation(&"wake"):
		sf.add_animation(&"wake")
		sf.set_animation_loop(&"wake", false)
		sf.set_animation_speed(&"wake", 8.0)
		for i in 6:
			sf.add_frame(&"wake", load(BASE + "wake_%d.png" % i))

func _physics_process(delta: float) -> void:
	# slowly regenerate HP whenever upright (so chip damage recovers and you get
	# back up after a knockdown instead of falling again).
	if not downed and hp < MAX_HP:
		hp = minf(hp + HP_REGEN * delta, MAX_HP)
		_regen_emit_t -= delta
		if _regen_emit_t <= 0.0:
			_regen_emit_t = 0.2
			hp_changed.emit(hp / MAX_HP)

	# while taking a hit (block / pushed / knocked down) the player has no control
	if downed or stun_timer > 0.0:
		_physics_stunned(delta)
		return

	var j_now := Input.is_physical_key_pressed(KEY_J) or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var h_now := Input.is_physical_key_pressed(KEY_H)
	var k_now := Input.is_physical_key_pressed(KEY_K)
	var g_now := Input.is_physical_key_pressed(KEY_G)
	var space := Input.is_physical_key_pressed(KEY_SPACE)

	var busy := super_active or air_attacking or gun_active

	# --- movement input (blocked during super / air attack) ---
	var ix := 0.0
	var iz := 0.0
	if not busy:
		ix = Input.get_axis("ui_left", "ui_right")
		iz = Input.get_axis("ui_up", "ui_down")
		if Input.is_physical_key_pressed(KEY_A): ix -= 1.0
		if Input.is_physical_key_pressed(KEY_D): ix += 1.0
		if Input.is_physical_key_pressed(KEY_W): iz -= 1.0
		if Input.is_physical_key_pressed(KEY_S): iz += 1.0
		# touch joystick is additive on top of the keyboard read
		ix += Controls.move_vec.x
		iz += Controls.move_vec.y
		ix = clampf(ix, -1.0, 1.0)
		iz = clampf(iz, -1.0, 1.0)
	var dir := Vector3(ix, 0.0, iz)
	if dir.length() > 1.0:
		dir = dir.normalized()

	var space_edge := space and not space_prev
	var j_edge     := j_now and not j_prev
	var k_edge     := k_now and not k_prev

	# reset jump counter on the ground
	if is_on_floor():
		jumps_used = 0

	# --- jumps ---------------------------------------------------------------
	# Space (floor)        = jump. K+Space = jump-kick.
	# J tap in air         = jump punch  (Space first, then J).
	# Second Space + J     = super leap  (double-space with J held).
	# Second Space (no J)  = double jump.
	if _super_leap_cd  > 0.0: _super_leap_cd  -= delta
	if _super_punch_cd > 0.0: _super_punch_cd -= delta
	if _heli_hit_cd    > 0.0: _heli_hit_cd    -= delta

	if space_edge and is_on_floor() and not busy and not attacking:
		velocity.y = JUMP_VELOCITY
		jumps_used = 1
	elif space_edge and not is_on_floor() and jumps_used == 1 and not super_active and not air_attacking:
		# second Space = double jump (go higher); a J after this is the super leap
		velocity.y = DOUBLE_JUMP_VELOCITY
		jumps_used = 2

	# J tap while airborne:
	#   after a single jump (Space + J)         -> regular jump punch
	#   after a double jump (Space + Space + J) -> SUPER LEAP slam (ALWAYS, no cd)
	if j_edge and not is_on_floor() and not air_attacking and not super_active and jumps_used >= 1:
		if jumps_used >= 2:
			# double-jump + J = SUPER LEAP, gated only by its cooldown. On cooldown
			# it does NOTHING (never a regular punch).
			if _super_leap_cd <= 0.0:
				super_leap = true
				_start_air(&"jumppunch", SUPER_LEAP_VELOCITY, ix, iz)
				_super_leap_cd = SUPER_LEAP_CD
		else:
			_start_air(&"regularjumppunch", 0.0)
	elif k_edge and not is_on_floor() and not air_attacking and not super_active and jumps_used >= 1:
		_start_air(&"jumpkick", 0.0)

	# --- ground actions ---
	if is_on_floor() and not busy:
		if h_now and not h_prev and _super_punch_cd <= 0.0:
			_start_super()
			_super_punch_cd = SUPER_PUNCH_CD
		elif g_now and not g_prev:
			_start_gun()
		elif not attacking and not space_edge and not (space and (j_now or k_now)):
			if j_now:
				_start_punch()
			elif k_now:
				_start_kick()

	j_prev = j_now
	h_prev = h_now
	k_prev = k_now
	g_prev = g_now
	space_prev = space

	# --- touch controls (additive; mirror the keyboard J/K/H paths) ---------
	# Punch: like a J tap. In air after a jump -> jump punch; on ground -> punch.
	if Controls.consume_punch():
		if not is_on_floor() and not air_attacking and not super_active and jumps_used >= 1:
			_start_air(&"regularjumppunch", 0.0)
		elif is_on_floor() and not busy and not attacking:
			_start_punch()
	# Kick: like a K tap. In air -> jump kick; on ground -> kick.
	if Controls.consume_kick():
		if not is_on_floor() and not air_attacking and not super_active and jumps_used >= 1:
			_start_air(&"jumpkick", 0.0)
		elif is_on_floor() and not busy and not attacking:
			_start_kick()
	# Special: SUPER_PUNCH (ground lunge) or SUPER_LEAP (high jump-punch slam),
	# depending on the mode selected by the touch toggle.
	if Controls.consume_special():
		if Controls.special_mode == Controls.SpecialMode.SUPER_PUNCH:
			if is_on_floor() and not busy and _super_punch_cd <= 0.0:
				_start_super()
				_super_punch_cd = SUPER_PUNCH_CD
		else:  # SUPER_LEAP — mirror the keyboard double-space+J super-leap state
			if not super_active and not air_attacking and _super_leap_cd <= 0.0:
				super_leap = true
				_start_air(&"jumppunch", SUPER_LEAP_VELOCITY, ix, iz)
				jumps_used = 2
				_super_leap_cd = SUPER_LEAP_CD
	# Gun: placeholder stub (no mechanic yet).
	if Controls.consume_gun():
		_start_gun()

	# --- run ramp: accumulate horizontal-walk time ---
	var horiz := absf(ix) > 0.05 and absf(ix) >= absf(iz)
	if horiz and is_on_floor() and not attacking:
		run_timer += delta
	else:
		run_timer = 0.0
	var running := run_timer >= RUN_DELAY

	# --- horizontal velocity ---
	if super_active:
		velocity.x = (-1.0 if face_left else 1.0) * SUPER_SPEED
		velocity.z = 0.0
	elif air_attacking:
		pass  # keep whatever horizontal momentum the leap had
	else:
		var spd := RUN_SPEED if running else SPEED
		velocity.x = dir.x * spd
		velocity.z = dir.z * spd

	if land_hold_timer > 0.0:
		land_hold_timer -= delta

	# --- gravity: full height on the way up, hard slam on the way down ---
	if not is_on_floor():
		var g := GRAVITY
		if air_attacking and sprite.animation == &"jumppunch" and velocity.y < 0.0:
			g = SLAM_GRAVITY
		velocity.y -= g * delta
	move_and_slide()

	# --- camera shake (super-leap impact) ---
	_update_shake(delta)

	# keep the player inside the playable deck area
	global_position.x = clampf(global_position.x, PLAY_X_MIN, PLAY_X_MAX)
	global_position.z = clampf(global_position.z, PLAY_Z_MIN, PLAY_Z_MAX)

	if dir.x > 0.1: face_left = false
	elif dir.x < -0.1: face_left = true

	_tick_invincible(delta)
	_tick_laser(delta)
	_update_animation(ix, iz, dir.length(), running)

	# --- ghost trail during attacks (after movement so errors can't block it) ---
	if air_attacking or super_active:
		_ghost_timer += delta
		if _ghost_timer >= GHOST_INTERVAL:
			_ghost_timer = 0.0
			_spawn_ghost()
	else:
		_ghost_timer = 0.0
	_tick_ghosts(delta)

func _hit_at_contact(type: String, delay: float) -> void:
	# fire the hit at the CONTACT frame, not the wind-up, so the enemy reacts when
	# the fist/foot actually lands.
	get_tree().create_timer(delay).timeout.connect(func() -> void:
		if attacking or super_active:
			attack_hit.emit(type))

func _start_punch() -> void:
	attacking = true
	consecutive_hits = 0   # hitting back resets the knockdown chain
	sprite.flip_h = face_left
	punch_toggle = not punch_toggle
	sprite.play(&"punch" if punch_toggle else &"punch2")
	_hit_at_contact("normal", 0.12)

func _start_kick() -> void:
	attacking = true
	consecutive_hits = 0
	sprite.flip_h = face_left
	kick_toggle = not kick_toggle
	sprite.play(&"kick" if kick_toggle else &"stylish")
	_hit_at_contact("normal", 0.14)

func _start_super() -> void:
	super_active = true
	attacking = false
	consecutive_hits = 0
	collision_mask = 1   # pass through villains during super punch
	sprite.flip_h = face_left
	sprite.play(&"super")
	_hit_at_contact("super", 0.10)

func _start_gun() -> void:
	if gun_active or not is_on_floor() or super_active or air_attacking:
		return
	if not sprite.sprite_frames.has_animation(&"gun"):
		return   # frames not generated yet
	gun_active = true
	attacking = true
	consecutive_hits = 0
	sprite.flip_h = face_left
	sprite.play(&"gun")
	# fire the laser on frame 1 (the shoot frame, ~0.11 s at 9 fps)
	get_tree().create_timer(1.0 / 9.0).timeout.connect(_fire_laser)

func _fire_laser() -> void:
	if _laser != null:
		_laser.queue_free()
		_laser = null
	_laser_hit_set.clear()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.1, 0.6, 1.0, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.2, 0.85, 1.0)
	mat.emission_energy_multiplier = 5.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var mesh := BoxMesh.new()
	mesh.size = Vector3(2.0, 0.07, 0.07)
	mesh.material = mat
	_laser = MeshInstance3D.new()
	_laser.mesh = mesh
	get_parent().add_child(_laser)
	var dir_x := -1.0 if face_left else 1.0
	# Origin: gun muzzle — the pistol is held out at the end of the extended arm
	# (~2.0u to the side) at shoulder height (~y 3.7).
	# Holding W while firing = aim slightly UP (to hit dangling enemies / choppers)
	var aim_up := Input.is_physical_key_pressed(KEY_W) or Input.is_action_pressed("ui_up")
	if aim_up:
		_laser.global_position = global_position + Vector3(dir_x * 1.7, 4.0, 0.0)
		_laser_vel = Vector3(dir_x * 27.0, 16.0, 0.0)
		_laser.rotation.z = atan2(_laser_vel.y, _laser_vel.x)
	else:
		_laser.global_position = global_position + Vector3(dir_x * 2.0, 3.7, 0.0)
		_laser_vel = Vector3(dir_x * 32.0, 0.0, 0.0)
	_laser_life = 1.4

func _tick_laser(delta: float) -> void:
	if _laser == null:
		return
	_laser_life -= delta
	if _laser_life <= 0.0:
		_laser.queue_free()
		_laser = null
		_laser_hit_set.clear()
		return
	_laser.global_position += _laser_vel * delta
	# Penetrating shot — damages every villain the beam passes through,
	# but only once per villain per shot.
	for v in get_tree().get_nodes_in_group("villain"):
		if _laser_hit_set.has(v):
			continue
		var diff: Vector3 = v.global_position - _laser.global_position
		diff.y = 0.0
		if diff.length() < 1.8 and v.has_method("_on_player_attack"):
			_laser_hit_set[v] = true
			v._on_player_attack("gun")

func _start_air(anim: StringName, launch: float, dir_x: float = 1.0, dir_z: float = 0.0) -> void:
	air_attacking = true
	air_attack_anim_done = false
	attacking = false
	consecutive_hits = 0
	sprite.flip_h = face_left
	if launch > 0.0:
		velocity.y = launch
		# no WASD held → drop straight down, no horizontal drift
		var has_dir := absf(dir_x) > 0.1 or absf(dir_z) > 0.1
		if has_dir:
			velocity.x = dir_x * RUN_SPEED
			velocity.z = dir_z * RUN_SPEED
		else:
			velocity.x = 0.0
			velocity.z = 0.0
	else:
		velocity.x = (-1.0 if face_left else 1.0) * RUN_SPEED
	sprite.stop()
	sprite.play(anim)
	sprite.pause()

func _tick_invincible(delta: float) -> void:
	if invincible_timer > 0.0:
		invincible_timer -= delta

func _physics_stunned(delta: float) -> void:
	_tick_invincible(delta)
	# knockback slides out and decays; gravity keeps us grounded
	velocity.x = lerpf(velocity.x, 0.0, delta * 6.0)
	velocity.z = lerpf(velocity.z, 0.0, delta * 6.0)
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	move_and_slide()
	global_position.x = clampf(global_position.x, PLAY_X_MIN, PLAY_X_MAX)
	global_position.z = clampf(global_position.z, PLAY_Z_MIN, PLAY_Z_MAX)

	if not downed:
		stun_timer -= delta
		if stun_timer <= 0.0:
			_set_anim(&"front")

# Called by a villain when its punch/kick connects. `dir` points away from the
# attacker. Escalates with each consecutive unanswered hit.
func receive_knockback(dir: Vector3) -> void:
	if downed:
		return
	if not is_on_floor():
		return
	if invincible_timer > 0.0:
		return  # iframes — only one villain can connect per window
	consecutive_hits += 1
	hp -= MELEE_DMG
	hp = maxf(hp, 0.0)
	hp_changed.emit(hp / MAX_HP)
	velocity = dir * 4.0
	face_left = dir.x > 0.0   # face toward the hit
	sprite.flip_h = face_left
	attacking = false
	super_active = false
	air_attacking = false
	gun_active = false

	invincible_timer = 0.9
	if hp <= 0.0 or consecutive_hits >= 3:
		# emptied bar or 3rd consecutive hit -> full knockdown, then wake-up
		downed = true
		waking = false
		velocity = dir * 9.0
		sprite.play(&"fall"); sprite.frame = 2   # play falling sequence 2..7
	elif consecutive_hits == 1:
		# skip defend stagger — just a brief nudge so movement isn't interrupted
		velocity = dir * 3.0
		stun_timer = 0.1
	else:
		# 2nd consecutive hit -> pushed-back pose
		sprite.play(&"fall"); sprite.pause(); sprite.frame = 1
		velocity = dir * 7.0
		stun_timer = 0.4

func receive_gun_hit(dir: Vector3) -> void:
	if downed: return
	if invincible_timer > 0.0: return
	hp -= ENEMY_GUN_DMG
	hp = maxf(hp, 0.0)
	invincible_timer = 0.4
	face_left = dir.x > 0.0
	sprite.flip_h = face_left
	attacking = false
	super_active = false
	gun_active = false
	hp_changed.emit(hp / MAX_HP)
	if hp <= 0.0:
		downed = true
		waking = false
		velocity = dir * 9.0
		sprite.play(&"fall")
		sprite.frame = 2
	else:
		velocity = dir * 3.0
		stun_timer = 0.2

func receive_heli_hit() -> void:
	# Chopper fire: completely SILENT — no stagger, no defend, no HP bar change,
	# nothing interrupts the finale mission. A dedicated counter tracks hits;
	# on the 10th the hero falls. Throttled so a rapid spray counts as one hit.
	if downed: return
	if _heli_hit_cd > 0.0: return
	_heli_hit_cd = HELI_HIT_CD
	_heli_hit_count += 1
	if _heli_hit_count >= HELI_HITS_TO_DOWN:
		_heli_hit_count = 0
		downed = true
		waking = false
		attacking = false
		super_active = false
		air_attacking = false
		gun_active = false
		velocity = Vector3(0.0, 3.0, 0.0)
		sprite.play(&"fall")
		sprite.frame = 2

func _add_regular_jump_punch_anim() -> void:
	var sf := sprite.sprite_frames
	var BASE := "res://assets/sprites/player/jump/"
	if sf.has_animation(&"regularjumppunch"):
		return
	var frames: Array[Texture2D] = []
	for i in 4:
		var t: Texture2D = load(BASE + "regularjumppunch_%d.png" % i)
		if t == null:
			return
		frames.append(t)
	sf.add_animation(&"regularjumppunch")
	sf.set_animation_loop(&"regularjumppunch", false)
	sf.set_animation_speed(&"regularjumppunch", 9.0)
	for t in frames:
		sf.add_frame(&"regularjumppunch", t)

func _on_anim_finished() -> void:
	var a := sprite.animation
	if a == &"fall" and downed:
		# knockdown finished -> begin wake-up
		waking = true
		sprite.play(&"wake")
		return
	elif a == &"wake" and downed:
		# fully recovered
		downed = false
		waking = false
		consecutive_hits = 0
		_heli_hit_count = 0
		# Only revive if the bar was emptied (a 3-hit stagger knockdown keeps HP);
		# this stops a knockdown from acting as a free heal.
		if hp <= 0.0:
			hp = MAX_HP * 0.5   # revive with a buffer; regen tops it up from there
		hp_changed.emit(hp / MAX_HP)
		sprite.play(&"front")
		return
	if a == &"super":
		super_active = false
		_clear_ghosts()
		sprite.play(&"front")
	elif a == &"gun":
		gun_active = false
		attacking = false
		sprite.play(&"front")
	elif a in [&"punch", &"punch2", &"kick", &"stylish"]:
		attacking = false
		sprite.play(&"front")
	# jumppunch/jumpkick frames are driven manually in _update_animation; nothing here.

func _shake(duration: float, strength: float) -> void:
	shake_timer = duration
	shake_strength = strength

func _update_shake(delta: float) -> void:
	if _cam == null:
		_cam = get_node_or_null("Camera3D")
	if _cam == null:
		return
	if shake_timer > 0.0:
		shake_timer -= delta
		var amt := shake_strength * (shake_timer / 0.45)
		_cam.h_offset = randf_range(-amt, amt)
		_cam.v_offset = randf_range(-amt, amt)
	else:
		_cam.h_offset = 0.0
		_cam.v_offset = 0.0

func _spawn_ghost() -> void:
	var tex := sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
	if tex == null:
		return
	var g := Sprite3D.new()
	g.texture = _holo_tex(tex)   # flat holographic recolor, not the character's colors
	g.pixel_size = 0.0044
	g.billboard = 2
	g.flip_h = sprite.flip_h
	g.centered = true
	g.modulate = Color(1.0, 1.0, 1.0, GHOST_ALPHA)
	g.render_priority = -1
	var pos := sprite.global_position + Vector3(0.0, 0.0, 0.015)
	get_parent().call_deferred("add_child", g)
	g.set_deferred("global_position", pos)
	_ghosts.append({"node": g, "life": GHOST_LIFE})

func _holo_tex(tex: Texture2D) -> Texture2D:
	# Recolor a frame into a flat hologram: silhouette filled with HOLO_COLOR,
	# luminance kept as brightness for depth, faint scanline bands. Cached.
	if _holo_cache.has(tex):
		return _holo_cache[tex]
	var img := tex.get_image()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	var data := img.get_data()    # PackedByteArray, 4 bytes/px RGBA8
	var cr := HOLO_COLOR.r
	var cg := HOLO_COLOR.g
	var cb := HOLO_COLOR.b
	var idx := 0
	for y in h:
		var scan := 0.7 if (y % 4 < 2) else 1.0   # horizontal hologram banding
		for x in w:
			var a := data[idx + 3]
			if a > 5:
				var lum := (data[idx] + data[idx + 1] + data[idx + 2]) / 765.0  # 0..1
				var b := (0.5 + 0.7 * lum) * scan
				data[idx]     = int(clampf(cr * b, 0.0, 1.0) * 255.0)
				data[idx + 1] = int(clampf(cg * b, 0.0, 1.0) * 255.0)
				data[idx + 2] = int(clampf(cb * b, 0.0, 1.0) * 255.0)
			idx += 4
	var out := Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, data)
	var t := ImageTexture.create_from_image(out)
	_holo_cache[tex] = t
	return t

func _tick_ghosts(delta: float) -> void:
	for i in range(_ghosts.size() - 1, -1, -1):
		var gd: Dictionary = _ghosts[i]
		gd["life"] -= delta
		if gd["life"] <= 0.0:
			gd["node"].queue_free()
			_ghosts.remove_at(i)
		else:
			gd["node"].modulate.a = (gd["life"] / GHOST_LIFE) * GHOST_ALPHA

func _clear_ghosts() -> void:
	for gd: Dictionary in _ghosts:
		gd["node"].queue_free()
	_ghosts.clear()

func _super_slam_aoe() -> void:
	for v in get_tree().get_nodes_in_group("villain"):
		var diff: Vector3 = v.global_position - global_position
		diff.y = 0.0
		if diff.length() <= SLAM_AOE_RADIUS and v.has_method("receive_super_slam"):
			v.receive_super_slam(global_position)

# Image-based slam effect goes here. Provide a frame strip (e.g. slam_fx_0..N on
# magenta) and this will play a flat AnimatedSprite3D burst at the impact point
# instead of coded particles. Stub no-op until the art exists.
func _spawn_slam_fx() -> void:
	pass

func _set_anim(name: StringName) -> void:
	if sprite.animation != name:
		sprite.play(name)

func _update_animation(ix: float, iz: float, moving_amount: float, running: bool) -> void:
	if super_active or attacking:
		return

	# --- airborne ---
	if not is_on_floor():
		was_in_air = true
		if air_attacking:
			# manual frames: leap pose rising, descent pose falling. The LAST frame
			# (ground-break impact) is reserved for landing only — never shown in air.
			var fc := sprite.sprite_frames.get_frame_count(sprite.animation)
			if velocity.y > 0.5:
				sprite.frame = 0
			else:
				sprite.frame = maxi(0, fc - 2)
				if not air_attack_anim_done:
					air_attack_anim_done = true
					attack_hit.emit("jump")   # pass-through hit as he starts coming down
			return
		var idx := 2
		if absf(velocity.x) > 0.5 or absf(velocity.z) > 0.5:
			if velocity.y > 3.0: idx = 0
			elif velocity.y > 0.3: idx = 1
			elif velocity.y > -0.3: idx = 2
			else: idx = 3
		if sprite.animation != &"jump" or sprite.is_playing():
			sprite.play(&"jump")
			sprite.pause()
		sprite.frame = idx
		return

	# --- just landed ---
	if was_in_air:
		was_in_air = false
		if air_attacking:
			# now on the ground: show the ground-break impact frame (last frame)
			sprite.frame = sprite.sprite_frames.get_frame_count(sprite.animation) - 1
			land_hold_timer = 0.0 if sprite.animation == &"jumpkick" else 0.45
			if not air_attack_anim_done:
				attack_hit.emit("jump")
			if super_leap:
				land_hold_timer = 0.7
				invincible_timer = 1.8   # iframes while slam resolves
				_shake(0.55, 0.8)
				_super_slam_aoe()
				# Coded-particle dust removed — drop an image-based slam/fire
				# effect here once the art exists (see _spawn_slam_fx stub).
		air_attack_anim_done = false
		super_leap = false
		air_attacking = false
		_clear_ghosts()
		if land_hold_timer <= 0.0:
			_set_anim(&"front")

	# still in landing hold — keep pose, block idle/walk overwrite
	if land_hold_timer > 0.0:
		return

	# --- grounded: run / walk / idle ---
	var moving := moving_amount > 0.05
	if not moving:
		_set_anim(&"front")
		return
	if absf(ix) >= absf(iz):
		face_left = ix < 0.0
		sprite.flip_h = face_left
		_set_anim(&"run" if running else &"walk")
	elif iz < 0.0:
		sprite.flip_h = ix < -0.05
		_set_anim(&"walk_back")
	else:
		sprite.flip_h = ix < -0.05
		_set_anim(&"walk_front")
