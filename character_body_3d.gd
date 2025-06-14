# CharacterBody3D.gd
extends CharacterBody3D

@export var move_speed := 50.0
@export var mouse_sensitivity := 0.3

var rotation_x := 0.0
var rotation_y := 0.0
var mouse_locked := true

# once we’ve successfully raycast and lifted ourselves out of the ground, we flip this
var _placed_on_ground := false

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	$Camera3D.current = true

func _input(event):
	if event is InputEventMouseMotion and mouse_locked:
		rotation_y -= event.relative.x * mouse_sensitivity * 0.01
		rotation_x -= event.relative.y * mouse_sensitivity * 0.01
		rotation_x = clamp(rotation_x, deg_to_rad(-89), deg_to_rad(89))
		# yaw the body, pitch the camera
		rotation.y = rotation_y
		$Camera3D.rotation.x = rotation_x

	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		mouse_locked = false

	if event is InputEventMouseButton and event.pressed:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		mouse_locked = true

func _physics_process(delta):
	# step 1: if we haven’t placed ourselves on the terrain yet, try to do so now
	if not _placed_on_ground:
		_try_place_on_ground()
		return

	# step 2: now do normal movement
	var dir = Vector3.ZERO
	if Input.is_action_pressed("move_forward"):
		dir -= transform.basis.z
	if Input.is_action_pressed("move_backward"):
		dir += transform.basis.z
	if Input.is_action_pressed("move_left"):
		dir -= transform.basis.x
	if Input.is_action_pressed("move_right"):
		dir += transform.basis.x

	# zero out any vertical velocity so we don’t fly
	velocity.y = 0

	if dir != Vector3.ZERO:
		velocity.x = dir.normalized().x * move_speed
		velocity.z = dir.normalized().z * move_speed
	else:
		velocity.x = lerp(velocity.x, 0.0, 0.1)
		velocity.z = lerp(velocity.z, 0.0, 0.1)

	move_and_slide()

# this will repeatedly attempt to raycast downward until it actually hits
func _try_place_on_ground():
	var from = global_transform.origin + Vector3.UP * 100.0
	var to   = from + Vector3.DOWN * 200.0

	var params = PhysicsRayQueryParameters3D.new()
	params.from                = from
	params.to                  = to
	params.exclude             = [self]
	params.collision_mask      = 0x7FFFFFFF  # collide with everything
	params.collide_with_bodies = true

	var result = get_world_3d().direct_space_state.intersect_ray(params)
	if result:
		# lift the character just above the hit point
		global_transform.origin.y = result.position.y + 2.0
		_placed_on_ground = true
