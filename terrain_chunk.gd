class_name TerrainChunk
extends Node3D

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

var chunk_coords = Vector2.ZERO
var current_lod := -1
var thread = null
var thread_result = null
var mutex := Mutex.new()
var viewer_position := Vector3.ZERO

func reset_chunk():
	if thread:
		mutex.lock()
		if thread.is_alive():
			thread.wait_to_finish()
		mutex.unlock()
	thread = null
	thread_result = null
	if $MeshInstance3D:
		$MeshInstance3D.mesh = null
	# DO NOT reset current_lod here!


func update_chunk(viewer_pos: Vector3):
	if thread and thread.is_alive():
		return # already working

	var dist_sq = global_position.distance_squared_to(viewer_pos)
	var lod = 0 # default fallback
	if dist_sq > 700 * 700:
		lod = 4
	elif dist_sq > 500 * 500:
		lod = 3
	elif dist_sq > 300 * 300:
		lod = 2
	elif dist_sq > 100 * 100:
		lod = 1

	if lod == current_lod:
		return # no change, don't regen

	current_lod = lod
	reset_chunk()
	generate_chunk_async(chunk_coords.x, chunk_coords.y)

	if has_node("LodLabel"):
		$LodLabel.text = "LOD: %d" % current_lod

		
func generate_chunk_async(chunk_x: int, chunk_y: int):
	chunk_coords = Vector2(chunk_x, chunk_y)
	thread = Thread.new()
	thread.start(Callable(self, "_threaded_generate_chunk"))

func _threaded_generate_chunk():
	mutex.lock()
	var height_map = generate_noise_map(map_width, map_height, noise_scale, chunk_coords)
	var mesh = generate_terrain_mesh(height_map)
	thread_result = mesh
	mutex.unlock()
	call_deferred("_apply_threaded_result")

func _apply_threaded_result():
	if thread_result:
		$MeshInstance3D.mesh = thread_result
		position = Vector3(chunk_coords.x * (map_width - 1), 0, chunk_coords.y * (map_height - 1))
		thread_result = null

		if has_node("LodLabel"):
			$LodLabel.text = "LOD: %d" % current_lod

		
func apply_height_curve(normalized_height: float) -> float:
	return height_curve.sample(clamp(normalized_height, 0.0, 1.0))

func generate_noise_map(width: int, height: int, scale: float, coords: Vector2) -> Array:
	var seed = noise_seed if noise_seed != 0 else randi()
	var noise = FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.seed = seed

	var offsets = []
	for i in range(octaves):
		offsets.append(Vector2(randi() % 20000 - 10000, randi() % 20000 - 10000))

	var height_map = []
	var min_noise = INF
	var max_noise = -INF

	for y in height:
		height_map.append([])
		for x in width:
			var amplitude = 1.0
			var frequency = 1.0
			var noise_height = 0.0

			for i in range(octaves):
				var sample_x = ((coords.x * width + x) / scale) * frequency + offsets[i].x
				var sample_y = ((coords.y * height + y) / scale) * frequency + offsets[i].y
				var value = noise.get_noise_2d(sample_x, sample_y)
				noise_height += value * amplitude
				amplitude *= persistence
				frequency *= lacunarity

			min_noise = min(min_noise, noise_height)
			max_noise = max(max_noise, noise_height)
			height_map[y].append(noise_height)

	for y in height:
		for x in width:
			var h = height_map[y][x]
			height_map[y][x] = (h - min_noise) / (max_noise - min_noise)

	return height_map

func get_color_for_height(value: float) -> Color:
	for terrain in terrain_types:
		if value <= terrain["height"]:
			return terrain["color"]
	return Color.WHITE
func generate_terrain_mesh(height_map: Array) -> ArrayMesh:
	var width = height_map[0].size()
	var height = height_map.size()
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var lod_step = max(1, current_lod)

	for y in range(0, height - 1, lod_step):
		for x in range(0, width - 1, lod_step):
			var x1 = min(x + lod_step, width - 1)
			var y1 = min(y + lod_step, height - 1)

			var norm00 = height_map[y][x]
			var norm01 = height_map[y1][x]
			var norm10 = height_map[y][x1]
			var norm11 = height_map[y1][x1]

			var h00 = apply_height_curve(norm00) * mesh_height
			var h01 = apply_height_curve(norm01) * mesh_height
			var h10 = apply_height_curve(norm10) * mesh_height
			var h11 = apply_height_curve(norm11) * mesh_height

			var p00 = Vector3(x, h00, y)
			var p01 = Vector3(x, h01, y1)
			var p10 = Vector3(x1, h10, y)
			var p11 = Vector3(x1, h11, y1)

			var color = get_color_for_height(norm00)

			st.set_color(color)
			st.add_vertex(p00)
			st.add_vertex(p10)
			st.add_vertex(p11)

			st.set_color(color)
			st.add_vertex(p00)
			st.add_vertex(p11)
			st.add_vertex(p01)

	var mat = StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	st.set_material(mat)
	st.generate_normals()
	return st.commit()
