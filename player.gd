extends CharacterBody2D

var player_name: String = "Player"
var player_color: Color = Color.WHITE
var hp: int = 100

const SPEED = 150.0
const JUMP_VELOCITY = -300.0

# Get the gravity from the project settings to be synced with RigidBody nodes.
var gravity = 980.0

@onready var anim = $AnimatedSprite2D

func _ready():
	# Update the UI label text to match the selected character (e.g., "Tony")
	$NameLabel.text = player_name
	
	# Optional: Tint the sprite with the player's selected color
	# $AnimatedSprite2D.modulate = player_color

func _physics_process(delta: float) -> void:
	# 1. Apply Gravity
	if not is_on_floor():
		velocity.y += gravity * delta

	# 2. Handle Jump
	if Input.is_action_just_pressed("move_up") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# 3. Handle Left/Right Movement
	var direction := Input.get_axis("move_left", "move_right")
	
	if direction:
		velocity.x = direction * SPEED
		anim.play("walk")
		# Flip the sprite visually if walking left
		anim.flip_h = direction < 0 
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		anim.play("idle")

	move_and_slide()
