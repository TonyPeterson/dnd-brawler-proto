extends CharacterBody2D

const SPEED: float = 350.0
const RADIUS: float = 24.0
const BORDER_WIDTH: float = 3.0
const MAX_HP: int = 10
const ATTACK_COOLDOWN_TIME: float = 0.25
const HIT_FLASH_DURATION: float = 0.1

@export var player_name: String = "":
	set(value):
		player_name = value
		if _name_label:
			_name_label.text = player_name
		queue_redraw()

@export var player_color: Color = Color.WHITE:
	set(value):
		player_color = value
		queue_redraw()

@export var hp: int = MAX_HP:
	set(value):
		hp = clampi(value, 0, MAX_HP)
		queue_redraw()

var aim_dir: Vector2 = Vector2.RIGHT
var hit_flash_timer: float = 0.0
var _attack_cooldown: float = 0.0

var _name_label: Label
var _collision_shape: CollisionShape2D
var _synchronizer: MultiplayerSynchronizer


class DiceProjectile extends Area2D:
	const PROJECTILE_SPEED: float = 650.0
	const SPIN_SPEED: float = 12.0
	const HALF_SIZE: float = 6.0
	const LIFETIME: float = 2.0

	var direction: Vector2 = Vector2.RIGHT
	var shooter_id: int = 0
	var dice_color: Color = Color.WHITE
	var _elapsed: float = 0.0

	func _init(start_pos: Vector2, dir: Vector2, owner_id: int, color: Color) -> void:
		global_position = start_pos
		direction = dir.normalized() if dir.length_squared() > 0.0001 else Vector2.RIGHT
		shooter_id = owner_id
		dice_color = color
		rotation = PI * 0.25

		var shape_node := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = HALF_SIZE * 1.2
		shape_node.shape = circle
		add_child(shape_node)

		body_entered.connect(_on_body_entered)

	func _physics_process(delta: float) -> void:
		global_position += direction * PROJECTILE_SPEED * delta
		rotation += SPIN_SPEED * delta
		_elapsed += delta
		if _elapsed >= LIFETIME:
			queue_free()

	func _draw() -> void:
		var rect := Rect2(-HALF_SIZE, -HALF_SIZE, HALF_SIZE * 2.0, HALF_SIZE * 2.0)
		draw_rect(rect, Color.WHITE, true)
		draw_rect(rect, dice_color.darkened(0.15), false, 2.0)
		draw_circle(Vector2.ZERO, 1.8, Color(0.15, 0.15, 0.15))

	func _on_body_entered(body: Node) -> void:
		if body is CharacterBody2D and body.name.to_int() != shooter_id:
			if multiplayer.multiplayer_peer and multiplayer.get_unique_id() == shooter_id:
				if body.has_method("take_damage"):
					body.take_damage.rpc(1)
			queue_free()


func _init() -> void:
	# CollisionShape2D with a CircleShape2D matching the player dot radius
	_collision_shape = CollisionShape2D.new()
	_collision_shape.name = "CollisionShape2D"
	var circle_shape := CircleShape2D.new()
	circle_shape.radius = RADIUS
	_collision_shape.shape = circle_shape
	add_child(_collision_shape)

	# Centered Label above the dot for the player's name
	_name_label = Label.new()
	_name_label.name = "NameLabel"
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name_label.size = Vector2(160.0, 24.0)
	_name_label.position = Vector2(-80.0, -RADIUS - 38.0)
	_name_label.text = player_name
	add_child(_name_label)

	# Programmatically create and configure MultiplayerSynchronizer
	_synchronizer = MultiplayerSynchronizer.new()
	_synchronizer.name = "MultiplayerSynchronizer"

	var replication_config := SceneReplicationConfig.new()
	for prop in [":position", ":player_name", ":player_color", ":hp"]:
		var prop_path := NodePath(prop)
		replication_config.add_property(prop_path)
		replication_config.property_set_spawn(prop_path, true)
		replication_config.property_set_replication_mode(
			prop_path,
			SceneReplicationConfig.REPLICATION_MODE_ALWAYS
		)

	_synchronizer.replication_config = replication_config
	add_child(_synchronizer)


func _enter_tree() -> void:
	set_multiplayer_authority(name.to_int())


func _ready() -> void:
	if _name_label:
		_name_label.text = player_name
	queue_redraw()


func _process(delta: float) -> void:
	if hit_flash_timer > 0.0:
		hit_flash_timer = maxf(0.0, hit_flash_timer - delta)
		if hit_flash_timer == 0.0:
			queue_redraw()


func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return

	if _attack_cooldown > 0.0:
		_attack_cooldown = maxf(0.0, _attack_cooldown - delta)

	var input_dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if input_dir.length_squared() > 0.0001:
		aim_dir = input_dir.normalized()

	velocity = input_dir * SPEED
	move_and_slide()

	if Input.is_action_just_pressed("attack") and _attack_cooldown <= 0.0:
		var shoot_dir := aim_dir
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			var to_mouse := get_global_mouse_position() - global_position
			if to_mouse.length_squared() > 0.0001:
				shoot_dir = to_mouse.normalized()
				aim_dir = shoot_dir
		_attack_cooldown = ATTACK_COOLDOWN_TIME
		spawn_dice_projectile.rpc(global_position, shoot_dir, name.to_int())


@rpc("any_peer", "call_local", "reliable")
func spawn_dice_projectile(pos: Vector2, dir: Vector2, shooter_id: int) -> void:
	var norm_dir := dir.normalized() if dir.length_squared() > 0.0001 else Vector2.RIGHT
	var projectile := DiceProjectile.new(pos, norm_dir, shooter_id, player_color)
	var container := get_parent() if get_parent() else get_tree().current_scene
	container.add_child(projectile)


@rpc("any_peer", "call_local", "reliable")
func take_damage(amount: int = 1) -> void:
	hit_flash_timer = HIT_FLASH_DURATION
	queue_redraw()

	if is_multiplayer_authority():
		hp -= amount
		if hp <= 0:
			hp = MAX_HP
			var viewport_size := get_viewport_rect().size
			if viewport_size == Vector2.ZERO:
				viewport_size = Vector2(800.0, 600.0)
			position = Vector2(
				randf_range(80.0, maxf(160.0, viewport_size.x - 80.0)),
				randf_range(80.0, maxf(160.0, viewport_size.y - 80.0))
			)


func _draw() -> void:
	var circle_color: Color = Color.WHITE if hit_flash_timer > 0.0 else player_color
	draw_circle(Vector2.ZERO, RADIUS, circle_color)
	draw_arc(Vector2.ZERO, RADIUS, 0.0, TAU, 64, Color.WHITE, BORDER_WIDTH, true)

	# 10-Hit Health Bar above the player dot (just below NameLabel)
	var bar_width: float = 50.0
	var bar_height: float = 6.0
	var bar_x: float = -bar_width * 0.5
	var bar_y: float = -RADIUS - 14.0
	var bg_rect := Rect2(bar_x, bar_y, bar_width, bar_height)

	draw_rect(bg_rect, Color(0.15, 0.15, 0.15, 0.9), true)

	var ratio: float = clampf(float(hp) / float(MAX_HP), 0.0, 1.0)
	if ratio > 0.0:
		var fill_color: Color
		if hp > 5:
			fill_color = Color(0.2, 0.85, 0.3)
		elif hp >= 3:
			fill_color = Color(0.95, 0.8, 0.15)
		else:
			fill_color = Color(0.9, 0.2, 0.2)
		draw_rect(Rect2(bar_x, bar_y, bar_width * ratio, bar_height), fill_color, true)

	for i in range(1, MAX_HP):
		var pip_x: float = bar_x + float(i) * 5.0
		draw_line(
			Vector2(pip_x, bar_y),
			Vector2(pip_x, bar_y + bar_height),
			Color(0.1, 0.1, 0.1, 0.95),
			1.0
		)
