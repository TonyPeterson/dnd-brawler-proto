extends CharacterBody3D

const SPEED = 2.0
const JUMP_VELOCITY = 5.0
var gravity = 12.0 # Tweak this so the jumps feel heavy and tight, not floaty

# Replace this with the exact name of Bob's model node in your scene tree
@onready var model = $animation_test 

func _physics_process(delta):
	# 1. Apply Gravity (Y-Axis)
	if not is_on_floor():
		velocity.y -= gravity * delta

	# 2. Handle Jump (Y-Axis)
	if Input.is_action_just_pressed("move_up") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# 3. Handle Left/Right Movement (X-Axis ONLY)
	var direction_x = Input.get_axis("move_left", "move_right")
	
	if direction_x:
		velocity.x = direction_x * SPEED
		
		# Snap the 3D model to face the correct direction
		if direction_x > 0:
			model.rotation.y = 0 # Face Right
		elif direction_x < 0:
			model.rotation.y = PI # Face Left (PI is exactly 180 degrees in radians)
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)

	# 4. THE METROIDVANIA LOCK
	# This prevents collisions from bumping you into the background or foreground
	velocity.z = 0
	global_position.z = 0 

	move_and_slide()
