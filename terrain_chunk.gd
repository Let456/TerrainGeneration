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
@export var terrain_types: Array = []
@export var use_falloff: bool = false
@export var falloff_curve: Curve
@export var use_flat_shading: bool = false


# sum of all octave amplitudes, used for consistent normalization
var amplitude_sum: float = 0.0

# Populated from TerrainManager
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

	# If LOD unchanged and job still pending, skip
	if new_lod == current_lod and job_pending:
		return

	# If LOD changed, queue rebuild
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
	var closest = Vector3(cx, cy, cz)
	return closest.distance_squared_to(viewer_pos)

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
	position = Vector3(
		chunk_coords.x * (map_width - 1),
		0,
		chunk_coords.y * (map_height - 1)
	)
	if has_node("LodLabel"):
		$LodLabel.text = "LOD: %d" % current_lod
	
	_update_collider(mesh)
	
func apply_height_curve(h: float) -> float:
	var i = clamp(int(h * 255.0), 0, 255)
	return height_curve_lookup[i]

func generate_noise_map(width: int, height: int, scale: float, coords: Vector2) -> Array:
	var noise = FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.seed = noise_seed

	# Pre‐defined remap window
	const LOW := 0.30
	const HIGH := 0.75

	var height_map := []
	for y in range(height):
		height_map.append([])
		for x in range(width):
			var amplitude := 1.0
			var frequency := 1.0
			var noise_height := 0.0

			# 1) accumulate multi‐octave noise
			for i in range(octaves):
				var world_x = coords.x * (width - 1) + x
				var world_y = coords.y * (height - 1) + y
				var sx = (world_x / scale) * frequency + octave_offsets[i].x
				var sy = (world_y / scale) * frequency + octave_offsets[i].y
				noise_height += noise.get_noise_2d(sx, sy) * amplitude
				amplitude *= persistence
				frequency *= lacunarity

			# 2) global normalization to [0..1]
			var n := (noise_height + amplitude_sum) / (2.0 * amplitude_sum)

			# 3) optional falloff mask
			if use_falloff:
				var f = falloff_map[y][x]
				n = clamp(n - f, 0.0, 1.0)

			# 4) remap window [LOW..HIGH] to [0..1]
			n = (n - LOW) / (HIGH - LOW)
			n = clamp(n, 0.0, 1.0)

			height_map[y].append(n)
	return height_map

func get_color_for_height(value: float) -> Color:
	for t in terrain_types:
		if value <= t["height"]:
			return t["color"]
	return Color.WHITE

func _update_collider(mesh: ArrayMesh) -> void:

	if current_lod <= MAX_COLLISION_LOD:

		if not _collision_body:
			_collision_body = StaticBody3D.new()
			add_child(_collision_body)
			_collision_shape  = CollisionShape3D.new()
			_collision_body.add_child(_collision_shape)
			_collision_shape.disabled = false   # <— this line turns it on

		var arrs  = mesh.surface_get_arrays(0)
		var shape = ConcavePolygonShape3D.new()
		shape.data = arrs[Mesh.ARRAY_VERTEX]
		_collision_shape.shape = shape

	else:
		if _collision_body:
			_collision_body.queue_free()
			_collision_body  = null
			_collision_shape = null

func generate_terrain_mesh(height_map: Array) -> ArrayMesh:
	var w = height_map[0].size()
	var h = height_map.size()
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step = max(1, current_lod)

	for y in range(0, h - 1, step):
		for x in range(0, w - 1, step):
			var x1 = min(x + step, w - 1)
			var y1 = min(y + step, h - 1)

			# 1) sample heights & build corners
			var n00 = height_map[y][x]
			var n10 = height_map[y][x1]
			var n01 = height_map[y1][x]
			var n11 = height_map[y1][x1]
			var p00 = Vector3(x,  apply_height_curve(n00) * mesh_height, y)
			var p10 = Vector3(x1, apply_height_curve(n10) * mesh_height, y)
			var p01 = Vector3(x,  apply_height_curve(n01) * mesh_height, y1)
			var p11 = Vector3(x1, apply_height_curve(n11) * mesh_height, y1)

			var col = get_color_for_height(n00)
			st.set_color(col)

			if use_flat_shading:
				# --- Flat shading: duplicate vertices, one normal per face ---

				# First triangle: (p00 → p10 → p11)
				# Compute normal as cross(p11 - p00, p10 - p00) → up-pointing
				var nrmA = (p11 - p00).cross(p10 - p00).normalized()
				st.set_normal(nrmA)
				st.add_vertex(p00)
				st.add_vertex(p10)
				st.add_vertex(p11)

				# Second triangle: (p00 → p11 → p01)
				# Compute normal as cross(p01 - p00, p11 - p00)
				var nrmB = (p01 - p00).cross(p11 - p00).normalized()
				st.set_normal(nrmB)
				st.add_vertex(p00)
				st.add_vertex(p11)
				st.add_vertex(p01)
			else:
				# --- Smooth shading: shared vertices, normals interpolated later ---
				st.add_vertex(p00)
				st.add_vertex(p10)
				st.add_vertex(p11)
				st.add_vertex(p00)
				st.add_vertex(p11)
				st.add_vertex(p01)

	# If we're doing smooth, generate averaged normals now
	if not use_flat_shading:
		st.generate_normals()

	# One material for both modes; we handle flat vs smooth by our normals:
	var mat = StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.flags_use_flat_shading = false   # OFF, since we do flat by hand
	# Optional debug: disable culling so you can see both sides
	# mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	st.set_material(mat)

	return st.commit()















	
