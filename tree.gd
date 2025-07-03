# res://tree.gd
extends Node3D

@export var auto_generate: bool       = false   # only generate on demand
@export var branch_length: float     = 3.0
@export var branch_thickness: float  = 0.3
@export var max_depth: int           = 3
@export var branch_angle: float      = 35.0
@export var randomness: float        = 50.0
@export var length_scale: float      = 0.75
@export var thickness_scale: float   = 0.7
@export var num_branches: int        = 3
@export var leaf_probability: float  = 0.2

var branch_material: StandardMaterial3D
var leaf_material:   StandardMaterial3D

func _ready():
	# set up materials
	branch_material = StandardMaterial3D.new()
	branch_material.albedo_color = Color(0.55, 0.27, 0.07)
	leaf_material   = StandardMaterial3D.new()
	leaf_material.albedo_color   = Color(1.0, 0.8, 0.2)

	# only auto–generate if the flag is set
	if auto_generate:
		generate_tree(
			Vector3.ZERO,
			Basis(),  # upright
			branch_length,
			branch_thickness,
			max_depth
		)

func generate_tree(start_pos: Vector3, basis: Basis, length: float, thickness: float, depth: int):
	if depth <= 0:
		return

	# === create branch ===
	var branch = MeshInstance3D.new()
	var cyl    = CylinderMesh.new()
	cyl.top_radius    = thickness * 0.5
	cyl.bottom_radius = thickness
	cyl.height        = length
	branch.mesh               = cyl
	branch.material_override  = branch_material
	branch.transform.origin   = start_pos + basis.y * (length * 0.3)
	branch.transform.basis    = basis
	add_child(branch)

	# add leaves at tips
	if depth == 1 and randf() < leaf_probability:
		add_leaf(branch.transform.origin, basis, length)

	# prepare for sub–branches
	var new_len   = length * length_scale
	var new_thick = thickness * thickness_scale
	var new_depth = depth - 1

	# recurse
	for i in range(num_branches):
		var axis  = Vector3(
			randf_range(-1,1),
			randf_range(0.5,1),
			randf_range(-1,1)
		).normalized()
		var angle = deg_to_rad(branch_angle + randf_range(-randomness, randomness))
		if depth == max_depth:
			angle *= 0.5
		var nb = basis.rotated(axis, angle)
		var np = branch.transform.origin + nb.y * (length * 0.3)
		generate_tree(np, nb, new_len, new_thick, new_depth)

func add_leaf(position: Vector3, basis: Basis, length: float):
	var parent = Node3D.new()
	parent.transform.origin = position + basis.y * (length * 0.5)
	parent.transform.basis  = basis
	add_child(parent)

	for i in 3:
		var leaf = MeshInstance3D.new()
		var box  = BoxMesh.new()
		box.size = Vector3(0.1, 0.3, 0.1)
		leaf.mesh              = box
		leaf.material_override = leaf_material
		leaf.transform.basis   = Basis().rotated(Vector3.FORWARD, deg_to_rad(i * 120))
		parent.add_child(leaf)
