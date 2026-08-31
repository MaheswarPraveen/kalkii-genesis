extends CharacterBody3D

const GRAVITY        := 20.0
const MELEE_RANGE    := 2.8
const GUN_VIL_RANGE  := 14.0
const CHASE_RANGE    := 35.0
const MAX_ATTACKERS  := 2

const MAX_HP     := 15.0
const DMG_NORMAL := 1.0
const DMG_JUMP   := 1.25
const DMG_GUN    := 3.0
const DMG_SUPER  := 15.0 / 7.0

enum State { IDLE, CHASE, ATTACK, HIT, DYING, WAKING, DEAD }

@onready var sprite: AnimatedSprite3D = $Sprite

var state           := State.IDLE
var hp              := MAX_HP
var state_timer     := 0.0
var attack_cooldown := 0.0
var super_slammed   := false
var _super_landed   := false
var getup_timer     := 0.0
var player: CharacterBody3D = null

var _speed        := 3.5
var _atk_cooldown := 2.2
var _hangback     := 0.0
var _strafe_time  := 0.0
var _strafe_dir   := 1.0

@export var is_gunner := false
@export var hung := false              # dangling on a chopper rope (finale)
@export var hang_point := Vector3.ZERO
var _hung_t := 0.0

var _red_laser: MeshInstance3D = null
var _red_laser_vel  := Vector3.ZERO
var _red_laser_life := 0.0
var _burst_left     := 0     # gunner: shots remaining in the current standing burst


func _ready() -> void:
	add_to_group("villain")
	collision_layer = 2
	collision_mask  = 1
	var archetype := randi() % 3
	match archetype:
		0:
			_speed        = randf_range(3.8, 4.6)
			_atk_cooldown = randf_range(0.8, 1.5)
			_hangback     = 0.0
		1:
			_speed        = randf_range(2.8, 3.6)
			_atk_cooldown = randf_range(1.8, 2.8)
			_hangback     = randf_range(0.5, 1.5)
		2:
			_speed        = randf_range(1.8, 2.6)
			_atk_cooldown = randf_range(2.5, 4.0)
			_hangback     = randf_range(1.5, 3.0)
	_strafe_dir = 1.0 if randi() % 2 == 0 else -1.0
	if is_gunner:
		_speed        = randf_range(2.0, 3.0)
		_atk_cooldown = randf_range(2.0, 3.5)
		_hangback     = randf_range(5.0, 9.0)
	sprite.sprite_frames = _build_frames()
	sprite.play(&"idle")
	sprite.animation_finished.connect(_on_anim_finished)
	await get_tree().process_frame
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		player = players[0]
		player.connect("attack_hit", _on_player_attack)
	state_timer = randf_range(2.0, 12.0)

func _physics_process(delta: float) -> void:
	# While hung on a rope (and still alive) it doesn't fall — it dangles in place
	# and keeps shooting. Once it dies it drops normally.
	var dangling := hung and state != State.DYING and state != State.DEAD
	if not dangling and not is_on_floor():
		velocity.y -= GRAVITY * delta

	match state:
		State.IDLE:
			velocity.x = 0.0
			velocity.z = 0.0
			state_timer -= delta
			if state_timer <= 0.0:
				_set_state(State.CHASE)

		State.CHASE:
			attack_cooldown -= delta
			if player == null:
				_set_state(State.IDLE)
			else:
				var diff := player.global_position - global_position
				diff.y = 0.0
				var dist := diff.length()
				_face(player.global_position)

				var atk_range := GUN_VIL_RANGE if is_gunner else MELEE_RANGE
				if dist <= atk_range and attack_cooldown <= 0.0 and _can_attack():
					_strafe_time = 0.0
					_set_state(State.ATTACK)
				elif dist > CHASE_RANGE or (_hangback > 1.0 and randf() < 0.002):
					_set_state(State.IDLE)
				elif is_gunner:
					# Stay at ~8u shooting distance; back off if player rushes in
					if dist > 9.0:
						var dir := diff.normalized()
						velocity.x = dir.x * _speed
						velocity.z = dir.z * _speed
					elif dist < MELEE_RANGE + 1.5:
						var dir := -diff.normalized()
						velocity.x = dir.x * _speed * 0.7
						velocity.z = dir.z * _speed * 0.7
					else:
						velocity.x = lerpf(velocity.x, 0.0, delta * 4.0)
						velocity.z = lerpf(velocity.z, 0.0, delta * 4.0)
				else:
					var commit_dist := MELEE_RANGE + _hangback
					if dist <= commit_dist + 0.5:
						if _strafe_time > 0.0:
							_strafe_time -= delta
							var perp := Vector3(-diff.normalized().z, 0.0, diff.normalized().x) * _strafe_dir
							velocity.x = perp.x * _speed * 0.7
							velocity.z = perp.z * _speed * 0.7
						else:
							var dir := diff.normalized()
							velocity.x = dir.x * _speed
							velocity.z = dir.z * _speed
					else:
						if _strafe_time <= 0.0 and randf() < 0.008:
							_strafe_time = randf_range(0.4, 1.2)
							_strafe_dir  = 1.0 if randi() % 2 == 0 else -1.0
						var dir := diff.normalized()
						velocity.x = dir.x * _speed
						velocity.z = dir.z * _speed

		State.ATTACK:
			velocity.x = 0.0
			velocity.z = 0.0

		State.HIT:
			velocity.x = lerpf(velocity.x, 0.0, delta * 8.0)
			velocity.z = lerpf(velocity.z, 0.0, delta * 8.0)
			state_timer -= delta
			if state_timer <= 0.0:
				_set_state(State.CHASE)

		State.DYING:
			velocity.x = lerpf(velocity.x, 0.0, delta * 4.0)
			velocity.z = lerpf(velocity.z, 0.0, delta * 4.0)
			if super_slammed:
				if is_on_floor() and not _super_landed:
					_super_landed = true
					sprite.stop()
					sprite.animation = &"fall"
					sprite.frame = sprite.sprite_frames.get_frame_count(&"fall") - 1
				getup_timer -= delta
				if getup_timer <= 0.0:
					super_slammed = false
					_super_landed = false
					_set_state(State.WAKING)

		State.WAKING:
			velocity.x = lerpf(velocity.x, 0.0, delta * 4.0)
			velocity.z = lerpf(velocity.z, 0.0, delta * 4.0)

		State.DEAD:
			velocity.x = 0.0
			velocity.z = 0.0

	_tick_red_laser(delta)
	if dangling:
		# pin to the rope with a gentle dangle; movement velocity is ignored
		_hung_t += delta
		global_position = hang_point + Vector3(sin(_hung_t * 1.3) * 0.18, sin(_hung_t * 2.1) * 0.12, 0.0)
		velocity = Vector3.ZERO
		return
	move_and_slide()

func _set_state(s: State) -> void:
	state = s
	match s:
		State.IDLE:
			state_timer = randf_range(0.5, 3.5)
			sprite.play(&"idle")
		State.CHASE:
			sprite.play(&"idle" if hung else &"run")
		State.ATTACK:
			if player:
				_face(player.global_position)
			if is_gunner:
				_burst_left = randi_range(2, 3)   # stand and fire 2-3 shots
				sprite.play(&"shoot")
				# fire mid-animation (frame 2 of 4 at 9fps ≈ 0.22s) so the laser
				# leaves the gun when the arm is raised, not after the full windup
				get_tree().create_timer(0.22).timeout.connect(_gunner_mid_fire)
			else:
				sprite.play(&"punch" if randi() % 2 == 0 else &"kick")
				# contact frame is frame 1 of 3 at 9fps ≈ 0.11s
				get_tree().create_timer(0.11).timeout.connect(_melee_contact)
		State.HIT:
			state_timer = 0.3
			sprite.play(&"fall")
			sprite.pause()
			sprite.frame = 0
		State.DYING:
			if super_slammed:
				sprite.play(&"fall")
				sprite.pause()
				sprite.frame = 3
			else:
				sprite.play(&"fall")
		State.WAKING:
			sprite.play(&"wake")
		State.DEAD:
			sprite.frame = sprite.sprite_frames.get_frame_count(&"fall") - 1
			sprite.pause()

func _melee_contact() -> void:
	if state == State.ATTACK and not is_gunner:
		_try_hit_player()

func _gunner_mid_fire() -> void:
	# fire the laser at the raised-arm frame, not at the end of the full animation
	if state == State.ATTACK and is_gunner:
		_fire_red_laser()

func _can_attack() -> bool:
	var count := 0
	for v in get_tree().get_nodes_in_group("villain"):
		if v != self and v.get("state") == State.ATTACK and v.get("is_gunner") == is_gunner:
			count += 1
	return count < MAX_ATTACKERS

func _on_anim_finished() -> void:
	match state:
		State.ATTACK:
			if is_gunner:
				_burst_left -= 1
				if _burst_left > 0:
					# stay planted and fire another shot in the burst
					if player:
						_face(player.global_position)
					sprite.play(&"shoot")
					get_tree().create_timer(0.22).timeout.connect(_gunner_mid_fire)
					return
			attack_cooldown = _atk_cooldown
			_set_state(State.CHASE)
		State.DYING:
			if hp <= 0.0:
				_set_state(State.DEAD)
			elif not super_slammed:
				_set_state(State.CHASE)
		State.WAKING:
			_set_state(State.CHASE)

func _face(target: Vector3) -> void:
	sprite.flip_h = target.x < global_position.x

func _try_hit_player() -> void:
	if player == null:
		return
	if is_gunner:
		_fire_red_laser()
		return
	if not player.is_on_floor():
		return
	var diff := player.global_position - global_position
	diff.y = 0.0
	if diff.length() > MELEE_RANGE:
		return
	player.receive_knockback(diff.normalized())

func _fire_red_laser() -> void:
	if player == null:
		return
	if _red_laser != null:
		_red_laser.queue_free()
		_red_laser = null
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.12, 0.0, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.05, 0.0)
	mat.emission_energy_multiplier = 7.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.76, 0.077, 0.077)   # 10% bigger
	mesh.material = mat
	_red_laser = MeshInstance3D.new()
	_red_laser.mesh = mesh
	get_parent().add_child(_red_laser)
	var dir: Vector3 = player.global_position - global_position
	dir.y = 0.0
	dir = dir.normalized()
	var dir_x := -1.0 if sprite.flip_h else 1.0
	_red_laser.global_position = global_position + Vector3(dir_x * 1.5, 2.0, 0.0)
	_red_laser_vel  = dir * 22.0
	_red_laser_life = 1.5

func _tick_red_laser(delta: float) -> void:
	if _red_laser == null:
		return
	_red_laser_life -= delta
	if _red_laser_life <= 0.0:
		_red_laser.queue_free()
		_red_laser = null
		return
	_red_laser.global_position += _red_laser_vel * delta
	if player == null:
		return
	var diff: Vector3 = player.global_position - _red_laser.global_position
	diff.y = 0.0
	if diff.length() < 1.2:
		# hung finale gunners use the SILENT hit (no stagger, 10 hits = down) so a
		# crossfire from all three can't lock the hero out of control.
		if hung and player.has_method("receive_heli_hit"):
			player.receive_heli_hit()
		elif player.has_method("receive_gun_hit"):
			player.receive_gun_hit(_red_laser_vel.normalized())
		_red_laser.queue_free()
		_red_laser = null

func _on_player_attack(type: String) -> void:
	if state == State.DYING or state == State.DEAD or player == null:
		return
	# Gun hits are called directly by the laser (player._tick_laser) only for the
	# villains the beam actually passes through, so they skip the proximity/facing
	# gates that the melee/jump/super attacks need.
	if type != "gun":
		var diff := player.global_position - global_position
		diff.y = 0.0
		var range_check := MELEE_RANGE + (2.0 if type == "jump" else 0.5)
		if diff.length() > range_check:
			return
		if type != "jump":
			var villain_on_right: bool = global_position.x > player.global_position.x + 0.3
			var villain_on_left: bool  = global_position.x < player.global_position.x - 0.3
			var hero_faces_right: bool = not player.face_left
			if hero_faces_right and villain_on_left:
				return
			if (not hero_faces_right) and villain_on_right:
				return
	var dmg := DMG_NORMAL
	if type == "jump":
		dmg = DMG_JUMP
	elif type == "gun":
		dmg = DMG_GUN
	elif type == "super":
		dmg = DMG_SUPER
	hp -= dmg
	var kb_dir := (global_position - player.global_position)
	kb_dir.y = 0.0
	velocity = kb_dir.normalized() * 6.0
	if hp <= 0.0:
		hp = 0.0
		_set_state(State.DYING)
	else:
		_set_state(State.HIT)

func receive_super_slam(origin: Vector3) -> void:
	if state == State.DEAD:
		return
	hp -= DMG_SUPER
	hp = maxf(hp, 0.0)
	var kb: Vector3 = global_position - origin
	kb.y = 0.0
	if kb.length() < 0.1:
		kb = Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)).normalized()
	else:
		kb = kb.normalized()
	velocity.x = kb.x * 12.0
	velocity.z = kb.z * 12.0
	velocity.y = 6.0
	super_slammed = true
	_super_landed = false
	getup_timer = 3.0
	_set_state(State.DYING)

func _build_frames() -> SpriteFrames:
	var sf := SpriteFrames.new()
	sf.remove_animation(&"default")
	var BASE := "res://assets/sprites/player/villain/"

	if is_gunner:
		var GB := "res://assets/sprites/player/gun_villain/"
		sf.add_animation(&"idle"); sf.set_animation_loop(&"idle", true)
		sf.set_animation_speed(&"idle", 2.0)
		for i in 4:
			sf.add_frame(&"idle", load(GB + "gun_villain_idle_%d.png" % i))
		sf.add_animation(&"run"); sf.set_animation_loop(&"run", true)
		sf.set_animation_speed(&"run", 9.0)
		for i in 6:
			sf.add_frame(&"run", load(GB + "gun_villain_run_%d.png" % i))
		sf.add_animation(&"shoot"); sf.set_animation_loop(&"shoot", false)
		sf.set_animation_speed(&"shoot", 9.0)
		for i in 4:
			sf.add_frame(&"shoot", load(GB + "gun_villain_idle_%d.png" % i))
	else:
		sf.add_animation(&"idle"); sf.set_animation_loop(&"idle", true)
		sf.set_animation_speed(&"idle", 1.0)
		sf.add_frame(&"idle", load(BASE + "villain_idle_%d.png" % (randi() % 4)))
		sf.add_animation(&"run"); sf.set_animation_loop(&"run", true)
		sf.set_animation_speed(&"run", 9.0)
		for i in 6:
			sf.add_frame(&"run", load(BASE + "villain_run_%d.png" % i))
		sf.add_animation(&"punch"); sf.set_animation_loop(&"punch", false)
		sf.set_animation_speed(&"punch", 9.0)
		for i in 3:
			sf.add_frame(&"punch", load(BASE + "villain_punch_%d.png" % i))
		sf.add_animation(&"kick"); sf.set_animation_loop(&"kick", false)
		sf.set_animation_speed(&"kick", 9.0)
		for i in 3:
			sf.add_frame(&"kick", load(BASE + "villain_kick_%d.png" % i))

	# shared fall + wake (same art for both villain types)
	sf.add_animation(&"fall"); sf.set_animation_loop(&"fall", false)
	sf.set_animation_speed(&"fall", 9.0)
	for i in 4:
		sf.add_frame(&"fall", load(BASE + "villain_fall_air_%d.png" % i))
	for i in 4:
		sf.add_frame(&"fall", load(BASE + "villain_fall_gnd_%d.png" % i))
	sf.add_animation(&"wake"); sf.set_animation_loop(&"wake", false)
	sf.set_animation_speed(&"wake", 6.0)
	for i in 4:
		sf.add_frame(&"wake", load(BASE + "villain_wake_%d.png" % i))

	return sf
