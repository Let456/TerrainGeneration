extends Node3D
class_name TerrainChunk

signal mesh_ready(mesh: ArrayMesh)

@export var map_width: int = 241
@export var map_height: int = 241
@export var noise_scale: float = 40.0
@export var mesh_height: float = 20.0
@export var octaves: int = 4
@export var persistence: float = 0.5
@export var lacunarity: float = 10.0
@export var noise_seed: int = 0
@export var height_curve: Curve
@export var terrain_types: Array = []
@export var skirt_height: float = 2.0  # how far the skirt drops

# sum of all octave amplitudes, used for consistent normalization
var amplitude_sum: float = 0.0

# Populated from TerrainManager
var octave_offsets: Array = []

var chunk_coords: Vector2 = Vector2.ZERO
var current_lod: int = -1
var job_pending: bool = false
var height_curve_lookup: Array = []

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
func apply_height_curve(h: float) -> float:
	var i = clamp(int(h * 255.0), 0, 255)
	return height_curve_lookup[i]

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

			# accumulate multi-octave noise
			for i in range(octaves):
				var world_x = coords.x * (width - 1) + x
				var world_y = coords.y * (height - 1) + y
				var sx = (world_x / scale) * frequency + octave_offsets[i].x
				var sy = (world_y / scale) * frequency + octave_offsets[i].y
				noise_height += noise.get_noise_2d(sx, sy) * amplitude
				amplitude *= persistence
				frequency *= lacunarity

			# 1) global normalization to [0…1]
			var n := (noise_height + amplitude_sum) / (2.0 * amplitude_sum)

			# 2) stretch the observed tight band (e.g. [0.425…0.60] → [0…1])
			n = (n - 0.425) / 0.175
			n = clamp(n, 0.0, 1.0)

			height_map[y].append(n)
	return height_map



func get_color_for_height(value: float) -> Color:
	for t in terrain_types:
		if value <= t["height"]:
			return t["color"]
	return Color.WHITE

func generate_terrain_mesh(height_map: Array) -> ArrayMesh:
	var w = height_map[0].size()
	var h = height_map.size()
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step = max(1, current_lod)
	var sk = skirt_height

	# Main terrain
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

	# Skirts — top edge
	for x in range(0, w - 1, step):
		var n0 = height_map[0][x]
		var n1 = height_map[0][min(x + step, w - 1)]
		var p0 = Vector3(x, apply_height_curve(n0) * mesh_height, 0)
		var p1 = Vector3(min(x + step, w - 1), apply_height_curve(n1) * mesh_height, 0)
		var s0 = p0 + Vector3(0, -sk, 0)
		var s1 = p1 + Vector3(0, -sk, 0)
		var c0 = get_color_for_height(n0)
		st.set_color(c0); st.add_vertex(p0); st.add_vertex(p1); st.add_vertex(s1)
		st.set_color(c0); st.add_vertex(p0); st.add_vertex(s1); st.add_vertex(s0)

	# Skirts — bottom edge
	for x in range(0, w - 1, step):
		var yb = h - 1
		var n0b = height_map[yb][x]
		var n1b = height_map[yb][min(x + step, w - 1)]
		var pb0 = Vector3(x, apply_height_curve(n0b) * mesh_height, yb)
		var pb1 = Vector3(min(x + step, w - 1), apply_height_curve(n1b) * mesh_height, yb)
		var sb0 = pb0 + Vector3(0, -sk, 0)
		var sb1 = pb1 + Vector3(0, -sk, 0)
		var c0b = get_color_for_height(n0b)
		st.set_color(c0b); st.add_vertex(pb1); st.add_vertex(pb0); st.add_vertex(sb0)
		st.set_color(c0b); st.add_vertex(pb1); st.add_vertex(sb0); st.add_vertex(sb1)

	# Skirts — left edge
	for y2 in range(0, h - 1, step):
		var n0l = height_map[y2][0]
		var n1l = height_map[min(y2 + step, h - 1)][0]
		var p0l = Vector3(0, apply_height_curve(n0l) * mesh_height, y2)
		var p1l = Vector3(0, apply_height_curve(n1l) * mesh_height, min(y2 + step, h - 1))
		var s0l = p0l + Vector3(0, -sk, 0)
		var s1l = p1l + Vector3(0, -sk, 0)
		var c0l = get_color_for_height(n0l)
		st.set_color(c0l); st.add_vertex(p1l); st.add_vertex(p0l); st.add_vertex(s0l)
		st.set_color(c0l); st.add_vertex(p1l); st.add_vertex(s0l); st.add_vertex(s1l)

	# Skirts — right edge
	for y2 in range(0, h - 1, step):
		var xr = w - 1
		var n0r = height_map[y2][xr]
		var n1r = height_map[min(y2 + step, h - 1)][xr]
		var pr0 = Vector3(xr, apply_height_curve(n0r) * mesh_height, y2)
		var pr1 = Vector3(xr, apply_height_curve(n1r) * mesh_height, min(y2 + step, h - 1))
		var sr0 = pr0 + Vector3(0, -sk, 0)
		var sr1 = pr1 + Vector3(0, -sk, 0)
		var c0r = get_color_for_height(n0r)
		st.set_color(c0r); st.add_vertex(pr0); st.add_vertex(pr1); st.add_vertex(sr1)
		st.set_color(c0r); st.add_vertex(pr0); st.add_vertex(sr1); st.add_vertex(sr0)

	var mat = StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	st.set_material(mat)
	st.generate_normals()
	return st.commit()
