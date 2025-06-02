extends Node3D

@export var map_width: int = 241
@export var map_height: int = 241
@export var noise_scale: float = 40.0
@export var mesh_height: float = 20.0
@export var octaves: int = 4
@export var persistence: float = 0.5
@export var lacunarity: float = 5.0
@export var noise_seed: int = 0
@export var level_of_detail: int = 0  # 0 = max detail
@export var height_curve: Curve

var terrain_types = [
	{ "name": "Water",    "height": 0.3, "color": Color8(64, 96, 255) },
	{ "name": "Sand",     "height": 0.4, "color": Color8(238, 221, 136) },
	{ "name": "Grass",    "height": 0.6, "color": Color8(136, 204, 102) },
	{ "name": "Mountain", "height": 0.8, "color": Color8(136, 136, 136) },
	{ "name": "Snow",     "height": 1.0, "color": Color8(255, 255, 255) }
]

func _ready() -> void:
	var height_map = generate_noise_map(map_width, map_height, noise_scale)
	var mesh = generate_terrain_mesh(height_map)
	$MeshInstance3D.mesh = mesh

func _process(delta):
	if Input.is_action_just_pressed("ui_accept"):
		level_of_detail = (level_of_detail + 1) % 6
		print("Switched to LOD:", level_of_detail)
		var height_map = generate_noise_map(map_width, map_height, noise_scale)
		var mesh = generate_terrain_mesh(height_map)
		$MeshInstance3D.mesh = mesh

func apply_height_curve(normalized_height: float) -> float:
	return height_curve.sample(clamp(normalized_height, 0.0, 1.0))

func generate_noise_map(width: int, height: int, scale: float) -> Array:
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
				var sample_x = (float(x) / scale) * frequency + offsets[i].x
				var sample_y = (float(y) / scale) * frequency + offsets[i].y
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

	var lod_step = max(1, level_of_detail)

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
