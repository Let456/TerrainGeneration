# TreeMeshBuilder.gd
# Create a new scene with a single Node3D, attach this script to it.

extends Node3D
class_name TreeMeshBuilder

@export var output_path: String       = "res://CombinedTree.tres"
@export var branch_length:     float = 3.0
@export var branch_thickness:  float = 0.3
@export var max_depth:         int   = 7
@export var branch_angle:      float = 35.0
@export var randomness:        float = 50.0
@export var length_scale:      float = 0.75
@export var thickness_scale:   float = 0.7
@export var num_branches:      int   = 3
@export var leaf_probability:  float = 0.2

# SurfaceTools for batch geometry
var st_branch: SurfaceTool
var st_leaf:   SurfaceTool

# Materials
var branch_material: StandardMaterial3D
var leaf_material:   StandardMaterial3D

func _ready() -> void:
	randomize()

	# 1) Materiale identice cu tree.gd
	branch_material = StandardMaterial3D.new()
	branch_material.albedo_color = Color(0.55, 0.27, 0.07)
	leaf_material   = StandardMaterial3D.new()
	leaf_material.albedo_color   = Color(1.0, 0.8, 0.2)

	# 2) Initialize branch SurfaceTool
	st_branch = SurfaceTool.new()
	st_branch.begin(Mesh.PRIMITIVE_TRIANGLES)
	st_branch.set_material(branch_material)

	# 3) Initialize leaf SurfaceTool
	st_leaf = SurfaceTool.new()
	st_leaf.begin(Mesh.PRIMITIVE_TRIANGLES)
	st_leaf.set_material(leaf_material)

	# 4) Construcție recursivă
	_build_tree(Vector3.ZERO, Basis(), branch_length, branch_thickness, max_depth)

	# 5) Normale și extragere arrays
	st_branch.generate_normals()
	var arr_branch = st_branch.commit_to_arrays()
	st_leaf.generate_normals()
	var arr_leaf   = st_leaf.commit_to_arrays()

	# 6) Combina mesh-ul
	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr_branch)
	mesh.surface_set_material(0, branch_material)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr_leaf)
	mesh.surface_set_material(1, leaf_material)

	# 7) Salvează
	if output_path != "":
		ResourceSaver.save(mesh, output_path)
		print("Saved combined tree to ", output_path)

	# 8) Preview (opțional)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	add_child(mi)
	queue_free()

func _build_tree(start_pos: Vector3, basis: Basis, length: float, thickness: float, depth: int) -> void:
	if depth <= 0:
		return

	# — stamp branch —  
	st_branch.set_material(branch_material)
	var cyl := CylinderMesh.new()
	cyl.top_radius    = thickness * 0.5
	cyl.bottom_radius = thickness
	cyl.height        = length
	# poziția branch-ului în codul original:
	var branch_center = start_pos + basis.y * (length * 0.3)
	st_branch.append_from(cyl, 0, Transform3D(basis, branch_center))

	# — frunze la capăt dacă depth==1 —  
	if depth == 1 and randf() < leaf_probability:
		# exact ca add_leaf: un parent poziționat la branch_center + basis.y*(length*0.5)
		var leaf_base = branch_center + basis.y * (length * 0.5)
		for i in range(3):
			st_leaf.set_material(leaf_material)
			var box := BoxMesh.new()
			box.size = Vector3(0.1, 0.3, 0.1)
			var leaf_basis = basis.rotated(Vector3.FORWARD, deg_to_rad(i * 120))
			st_leaf.append_from(box, 0, Transform3D(leaf_basis, leaf_base))

	# — recursivitate —  
	var new_len   = length * length_scale
	var new_th    = thickness * thickness_scale
	var new_dep   = depth - 1
	for i in range(num_branches):
		var axis = Vector3(
			randf_range(-1, 1),
			randf_range(0.5, 1),
			randf_range(-1, 1)
		).normalized()
		var ang = deg_to_rad(branch_angle + randf_range(-randomness, randomness))
		if depth == max_depth:
			ang *= 0.5
		var nb = basis.rotated(axis, ang)
		var np = branch_center
		_build_tree(np, nb, new_len, new_th, new_dep)
