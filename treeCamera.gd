# res://treeCamera.gd
extends Camera3D

@export var speed: float       = 10.0   # Movement speed
@export var sensitivity: float = 0.2    # Mouse look sensitivity

var yaw:   float = 0.0
var pitch: float = 0.0

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	# Initialize yaw/pitch from the current rotation
	var rd = rotation_degrees
	pitch = rd.x
	yaw   = rd.y

func _process(delta):
	var m = Vector3.ZERO
	if Input.is_key_pressed(Key.KEY_W):
		m -= transform.basis.z
	if Input.is_key_pressed(Key.KEY_S):
		m += transform.basis.z
	if Input.is_key_pressed(Key.KEY_A):
		m -= transform.basis.x
	if Input.is_key_pressed(Key.KEY_D):
		m += transform.basis.x
	if Input.is_key_pressed(Key.KEY_Q):
		m += transform.basis.y
	if Input.is_key_pressed(Key.KEY_E):
		m -= transform.basis.y

	if m != Vector3.ZERO:
		translate(m.normalized() * speed * delta)

func _unhandled_input(event):
	if event is InputEventMouseMotion:
		yaw   -= event.relative.x * sensitivity
		pitch -= event.relative.y * sensitivity
		pitch = clamp(pitch, -89, 89)
		rotation_degrees = Vector3(pitch, yaw, 0)
	elif event is InputEventKey and event.pressed and event.keycode == Key.KEY_ESCAPE:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
