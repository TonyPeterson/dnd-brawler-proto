extends CharacterBody2D

const SPEED: float = 350.0
const RADIUS: float = 24.0
const BORDER_WIDTH: float = 3.0

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

var _name_label: Label
var _collision_shape: CollisionShape2D
var _synchronizer: MultiplayerSynchronizer


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
	_name_label.position = Vector2(-80.0, -RADIUS - 28.0)
	_name_label.text = player_name
	add_child(_name_label)

	# Programmatically create and configure MultiplayerSynchronizer
	_synchronizer = MultiplayerSynchronizer.new()
	_synchronizer.name = "MultiplayerSynchronizer"

	var replication_config := SceneReplicationConfig.new()
	for prop in [":position", ":player_name", ":player_color"]:
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


func _physics_process(_delta: float) -> void:
	if not is_multiplayer_authority():
		return

	var input_dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = input_dir * SPEED
	move_and_slide()


func _draw() -> void:
	draw_circle(Vector2.ZERO, RADIUS, player_color)
	draw_arc(Vector2.ZERO, RADIUS, 0.0, TAU, 64, Color.WHITE, BORDER_WIDTH, true)
