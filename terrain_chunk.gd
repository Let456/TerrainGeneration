extends Node3D
class_name TerrainChunk

signal mesh_ready(mesh: ArrayMesh)

@export var map_width: int = 241
@export var map_height: int = 241
@export var noise_scale: float = 80.0
@export var mesh_height: float = 20.0
@export var octaves: int = 3
@export var persistence: float = 0.35
@export var lacunarity: float = 2.5
@export var noise_seed: int = 0
@export var height_curve: Curve
@export var use_falloff: bool = false
@export var use_flat_shading: bool = false
@export var global_min_height: float = 0.0
@export var global_max_height: float = 50.0
@export var tree_scene: PackedScene
@export var trees_per_chunk: int = 0

var amplitude_sum: float = 0.0
var octave_offsets: Array = []
var chunk_coords: Vector2 = Vector2.ZERO
var current_lod: int = -1
var job_pending: bool = false
var height_curve_lookup: Array = []
var falloff_map: Array = []

const MAX_COLLISION_LOD := 10

var _collision_body: StaticBody3D
var _collision_shape: CollisionShape3D

func _ready():
	amplitude_sum = 0.0
	var amp = 1.0
	for i in range(octaves):
		amplitude_sum += amp
		amp *= persistence
	connect("mesh_ready", Callable(self, "_on_mesh_ready"))

func prepare():
	height_curve_lookup.clear()
	if height_curve:
		for i in range(256):
			height_curve_lookup.append(height_curve.sample(i / 255.0))
	else:
		push_warning("[TerrainChunk] height_curve is null.")

func reset_chunk():
	if $MeshInstance3D:
		$MeshInstance3D.mesh = null

func update_chunk(viewer_pos: Vector3):
	var dist_sq = distance_squared_to_chunk(viewer_pos)
	var new_lod = 0
	if dist_sq > 700 * 700:
		new_lod = 4
	elif dist_sq > 500 * 500:
		new_lod = 3
	elif dist_sq > 300 * 300:
		new_lod = 2
	elif dist_sq > 100 * 100:
		new_lod = 1

	if new_lod == current_lod and job_pending:
		return

	if new_lod != current_lod:
		current_lod = new_lod
		reset_chunk()
		chunk_coords = Vector2(
			floor(global_position.x / (map_width - 1)),
			floor(global_position.z / (map_height - 1))
		)
		if not job_pending:
			add_job_to_pool()
		if has_node("LodLabel"):
			$LodLabel.text = "LOD: %d" % current_lod

func distance_squared_to_chunk(viewer_pos: Vector3) -> float:
	var size = map_width - 1
	var min_x = position.x
	var max_x = position.x + size
	var min_y = position.y
	var max_y = position.y + mesh_height
	var min_z = position.z
	var max_z = position.z + size
	var cx = clamp(viewer_pos.x, min_x, max_x)
	var cy = clamp(viewer_pos.y, min_y, max_y)
	var cz = clamp(viewer_pos.z, min_z, max_z)
	return Vector3(cx, cy, cz).distance_squared_to(viewer_pos)

func add_job_to_pool():
	job_pending = true
	TerrainManager.active_chunk_jobs += 1
	WorkerThreadPool.add_task(
		Callable(self, "thread_generate_chunk"),
		false,
		"Generate mesh for chunk"
	)

func thread_generate_chunk():
	var mesh = generate_chunk_job()
	call_deferred("emit_signal", "mesh_ready", mesh)

func generate_chunk_job() -> ArrayMesh:
	var height_map = generate_noise_map(map_width, map_height, noise_scale, chunk_coords)
	return generate_terrain_mesh(height_map)

func _on_mesh_ready(mesh: ArrayMesh):
	job_pending = false
	TerrainManager.active_chunk_jobs -= 1

	$MeshInstance3D.mesh = mesh
	$MeshInstance3D.material_override = preload("res://TerrainMaterial.tres").duplicate()
	position = Vector3(
		chunk_coords.x * (map_width - 1),
		0,
		chunk_coords.y * (map_height - 1)
	)
	set_terrain_material_min_max($MeshInstance3D, mesh)
	_update_collider(mesh)
	spawn_trees()


func set_terrain_material_min_max(mesh_instance, mesh):
	var min_y = INF
	var max_y = -INF
	var arrs = mesh.surface_get_arrays(0)
	for v in arrs[Mesh.ARRAY_VERTEX]:
		min_y = min(min_y, v.y)
		max_y = max(max_y, v.y)
	var mat = mesh_instance.material_override
	if mat and mat is ShaderMaterial:
		mat.set_shader_parameter("min_height", global_min_height)
		mat.set_shader_parameter("max_height", global_max_height)



func apply_height_curve(h: float) -> float:
	var i = clamp(int(h * 255.0), 0, 255)
	return height_curve_lookup[i]

func spawn_trees():
	if not tree_scene or trees_per_chunk <= 0:
		return

	randomize()
	var space = get_world_3d().direct_space_state

	for i in range(trees_per_chunk):
		# 1) pick a random X,Z in chunk
		var local_x = randf() * (map_width - 1)
		var local_z = randf() * (map_height - 1)
		# 2) world coords
		var world_x = chunk_coords.x * (map_width - 1) + local_x
		var world_z = chunk_coords.y * (map_height - 1) + local_z

		# 3) build the query parameters
		var from = Vector3(world_x, mesh_height + 10.0, world_z)
		var to   = Vector3(world_x, -10.0,         world_z)
		var params = PhysicsRayQueryParameters3D.new()
		params.from    = from
		params.to      = to
		params.exclude = [ self ]             # don’t hit the chunk’s own body
		# params.collision_mask = 1          # if you need to limit layers

		# 4) perform the raycast
		var result = space.intersect_ray(params)
		# Option A: check for the “position” key
		if not result.has("position"):
			continue
		var hit_pos = result["position"]


		# 5) instance & place the tree
		var t = tree_scene.instantiate() as Node3D
		add_child(t)
		t.global_transform.origin = result.position

		# 6) finally build it (using its exported settings)
		t.generate_tree(
			Vector3.ZERO,
			Basis(),  # upright
			t.branch_length,
			t.branch_thickness,
			t.max_depth
		)


func generate_noise_map(width: int, height: int, scale: float, coords: Vector2) -> Array:
	var noise = FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.seed = noise_seed

	var height_map := []
	for y in range(height):
		height_map.append([])
		for x in range(width):
			var amplitude := 1.0
			var frequency := 1.0
			var noise_height := 0.0
			for i in range(octaves):
				var world_x = coords.x * (width - 1) + x
				var world_y = coords.y * (height - 1) + y
				var sx = (world_x / scale) * frequency + octave_offsets[i].x
				var sy = (world_y / scale) * frequency + octave_offsets[i].y
				noise_height += noise.get_noise_2d(sx, sy) * amplitude
				amplitude *= persistence
				frequency *= lacunarity
			var n := (noise_height + amplitude_sum) / (2.0 * amplitude_sum)
			if use_falloff:
				n = clamp(n - falloff_map[y][x], 0.0, 1.0)
			n = clamp(n, 0.0, 1.0)
			height_map[y].append(n)
	return height_map

func _update_collider(mesh: ArrayMesh) -> void:
	if current_lod <= MAX_COLLISION_LOD:
		if not _collision_body:
			_collision_body = StaticBody3D.new()
			add_child(_collision_body)
			_collision_shape = CollisionShape3D.new()
			_collision_body.add_child(_collision_shape)
			_collision_shape.disabled = false
		var arrs = mesh.surface_get_arrays(0)
		var shape = ConcavePolygonShape3D.new()
		shape.data = arrs[Mesh.ARRAY_VERTEX]
		_collision_shape.shape = shape
	else:
		if _collision_body:
			_collision_body.queue_free()
			_collision_body = null
			_collision_shape = null

func generate_terrain_mesh(height_map: Array) -> ArrayMesh:
	var w = height_map[0].size()
	var h = height_map.size()
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step = max(1, current_lod)
	var uv_scale = 8.0  # adjust to control tiling density

	for y in range(0, h - 1, step):
		for x in range(0, w - 1, step):
			var x1 = min(x + step, w - 1)
			var y1 = min(y + step, h - 1)

			# Heights
			var n00 = height_map[y][x]
			var n10 = height_map[y][x1]
			var n01 = height_map[y1][x]
			var n11 = height_map[y1][x1]
			# Positions
			var p00 = Vector3(x,  apply_height_curve(n00) * mesh_height, y)
			var p10 = Vector3(x1, apply_height_curve(n10) * mesh_height, y)
			var p01 = Vector3(x,  apply_height_curve(n01) * mesh_height, y1)
			var p11 = Vector3(x1, apply_height_curve(n11) * mesh_height, y1)

			# UVs (normalized 0→1 then scaled)
			var uv00 = Vector2(x  / float(w - 1), y  / float(h - 1)) * uv_scale
			var uv10 = Vector2(x1 / float(w - 1), y  / float(h - 1)) * uv_scale
			var uv01 = Vector2(x  / float(w - 1), y1 / float(h - 1)) * uv_scale
			var uv11 = Vector2(x1 / float(w - 1), y1 / float(h - 1)) * uv_scale

			if use_flat_shading:
				# Triangle A
				var nrmA = (p11 - p00).cross(p10 - p00).normalized()
				st.set_normal(nrmA)
				st.set_uv(uv00); st.add_vertex(p00)
				st.set_uv(uv10); st.add_vertex(p10)
				st.set_uv(uv11); st.add_vertex(p11)

				# Triangle B
				var nrmB = (p01 - p00).cross(p11 - p00).normalized()
				st.set_normal(nrmB)
				st.set_uv(uv00); st.add_vertex(p00)
				st.set_uv(uv11); st.add_vertex(p11)
				st.set_uv(uv01); st.add_vertex(p01)
			else:
				# Triangle A
				st.set_uv(uv00); st.add_vertex(p00)
				st.set_uv(uv10); st.add_vertex(p10)
				st.set_uv(uv11); st.add_vertex(p11)
				# Triangle B
				st.set_uv(uv00); st.add_vertex(p00)
				st.set_uv(uv11); st.add_vertex(p11)
				st.set_uv(uv01); st.add_vertex(p01)

	if not use_flat_shading:
		st.generate_normals()

	return st.commit()
