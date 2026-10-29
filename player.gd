extends CharacterBody2D

var player_name: String = "Player"
var player_color: Color = Color.WHITE
var hp: int = 100 

const SPEED = 150.0
const JUMP_VELOCITY = -300.0
var gravity = 980.0

var use_3d_sprites = false

@onready var anim = $AnimatedSprite2D

# 1. Assign network ownership based on the peer ID
# DELETE the _enter_tree() function completely!

func _ready():
	# 1. Grab the true peer ID now that the server has officially named the node
	var peer_id = name.to_int()
	
	# 2. Assign physics authority
	set_multiplayer_authority(peer_id)
	
	# 3. Explicitly tell the network synchronizer who owns this node's network data
	$MultiplayerSynchronizer.set_multiplayer_authority(peer_id)
	
	# 4. Set the UI elements
	$NameLabel.text = player_name
	anim.play("3d_idle")
	# $AnimatedSprite2D.modulate = player_color

func _physics_process(delta: float) -> void:
	# 2. If this isn't YOUR character, ignore the physics and keyboard inputs!
	if not is_multiplayer_authority():
		return

	# Apply Gravity
	if not is_on_floor():
		velocity.y += gravity * delta
		
	if Input.is_action_just_pressed("swap_style"):
		use_3d_sprites = !use_3d_sprites

	# Handle Jump
	if Input.is_action_just_pressed("move_up") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Handle Left/Right Movement
	var direction := Input.get_axis("move_left", "move_right")
	
	if direction:
		velocity.x = direction * SPEED
		anim.flip_h = direction < 0
		
		if use_3d_sprites:
			anim.play("3d_walk")
		else:
			anim.play("walk")
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		
		if use_3d_sprites:
			anim.play("3d_idle")
		else:
			anim.play("idle")

	move_and_slide()
