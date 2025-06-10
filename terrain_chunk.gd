class_name TerrainChunk
extends Node3D

signal mesh_ready(mesh: ArrayMesh)

@export var map_width := 241
@export var map_height := 241
@export var noise_scale := 40.0
@export var mesh_height := 20.0
@export var octaves := 4
@export var persistence := 0.5
@export var lacunarity := 5.0
@export var noise_seed := 0
@export var height_curve: Curve
@export var terrain_types := []

# new: filled in by manager
var octave_offsets: Array = []

var chunk_coords = Vector2.ZERO
var current_lod := -1
var height_curve_lookup := []

func _ready():
	connect("mesh_ready", Callable(self, "apply_chunk_job"))

func prepare():
	height_curve_lookup.clear()
	if height_curve:
		for i in range(256):
			height_curve_lookup.append(height_curve.sample(i / 255.0))
	else:
		push_warning("[TerrainChunk] height_curve is null — cannot generate lookup table.")

func reset_chunk():
	if $MeshInstance3D:
		$MeshInstance3D.mesh = null

func update_chunk(viewer_pos: Vector3):
	# compute squared distance to the nearest point on this chunk’s AABB
	var dist_sq = distance_squared_to_chunk(viewer_pos)

	# pick LOD by thresholds
	var lod = 0
	if dist_sq > 700 * 700:
		lod = 4
	elif dist_sq > 500 * 500:
		lod = 3
	elif dist_sq > 300 * 300:
		lod = 2
	elif dist_sq > 100 * 100:
		lod = 1

	if lod == current_lod:
		return

	current_lod = lod
	reset_chunk()
	chunk_coords = Vector2(
		floor(global_position.x / (map_width - 1)),
		floor(global_position.z / (map_height - 1))
	)
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

func apply_chunk_job(mesh: ArrayMesh):
	TerrainManager.active_chunk_jobs -= 1
	$MeshInstance3D.mesh = mesh
	position = Vector3(
		chunk_coords.x * (map_width - 1),
		0,
		chunk_coords.y * (map_height - 1)
	)
	if has_node("LodLabel"):
		$LodLabel.text = "LOD: %d" % current_lod

func apply_height_curve(h: float) -> float:
	var i = clamp(int(h * 255.0), 0, 255)
	return height_curve_lookup[i]

func generate_noise_map(width: int, height: int, scale: float, coords: Vector2) -> Array:
	var noise = FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.seed = noise_seed

	var height_map = []
	var min_n = INF
	var max_n = -INF

	for y in range(height):
		height_map.append([])
		for x in range(width):
			var amp = 1.0
			var freq = 1.0
			var nval = 0.0
			for i in range(octaves):
				# align sample to world-space grid
				var world_x = coords.x * (width - 1) + x
				var world_y = coords.y * (height - 1) + y
				var sx = (world_x / scale) * freq + octave_offsets[i].x
				var sy = (world_y / scale) * freq + octave_offsets[i].y
				nval += noise.get_noise_2d(sx, sy) * amp
				amp *= persistence
				freq *= lacunarity
			min_n = min(min_n, nval)
			max_n = max(max_n, nval)
			height_map[y].append(nval)

	# normalize
	for y in range(height):
		for x in range(width):
			var h = height_map[y][x]
			height_map[y][x] = (h - min_n) / (max_n - min_n)

	return height_map

func get_color_for_height(v: float) -> Color:
	for t in terrain_types:
		if v <= t["height"]:
			return t["color"]
	return Color.WHITE

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

			var n00 = height_map[y][x]
			var n10 = height_map[y][x1]
			var n01 = height_map[y1][x]
			var n11 = height_map[y1][x1]

			var p00 = Vector3(x, apply_height_curve(n00) * mesh_height, y)
			var p10 = Vector3(x1, apply_height_curve(n10) * mesh_height, y)
			var p01 = Vector3(x, apply_height_curve(n01) * mesh_height, y1)
			var p11 = Vector3(x1, apply_height_curve(n11) * mesh_height, y1)

			var col = get_color_for_height(n00)
			st.set_color(col)
			st.add_vertex(p00); st.add_vertex(p10); st.add_vertex(p11)
			st.set_color(col)
			st.add_vertex(p00); st.add_vertex(p11); st.add_vertex(p01)

	var mat = StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	st.set_material(mat)
	st.generate_normals()
	return st.commit()
