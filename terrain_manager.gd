extends Node3D

@export var viewer: Node3D
@export var chunk_scene: PackedScene
@export var view_distance: int = 2
@export var height_curve: Curve

var chunk_size = 240
var visible_chunks = {}
var chunk_pool: Array = []
var last_viewer_position := Vector3.INF
const viewer_move_threshold := 35.0
var active_chunk_jobs := 0

func _process(_delta):
	if not viewer:
		return

	var viewer_pos = viewer.global_position
	if viewer_pos.distance_squared_to(last_viewer_position) > viewer_move_threshold * viewer_move_threshold:
		last_viewer_position = viewer_pos

		var viewer_chunk = Vector2(
			floor(viewer_pos.x / chunk_size),
			floor(viewer_pos.z / chunk_size)
		)
		update_visible_chunks(viewer_chunk, viewer_pos)

func update_visible_chunks(viewer_chunk: Vector2, viewer_pos: Vector3):
	var new_chunks = {}

	for y in range(-view_distance, view_distance + 1):
		for x in range(-view_distance, view_distance + 1):
			var chunk_coord = viewer_chunk + Vector2(x, y)

			if not visible_chunks.has(chunk_coord):
				var chunk_instance = get_chunk_from_pool()
				if chunk_instance == null:
					continue

				chunk_instance.show()
				if chunk_instance.get_parent() != self:
					if chunk_instance.get_parent():
						chunk_instance.get_parent().remove_child(chunk_instance)
					add_child(chunk_instance)

				# Initialize parameters
				chunk_instance.map_width = 241
				chunk_instance.map_height = 241
				chunk_instance.noise_scale = 40.0
				chunk_instance.mesh_height = 20.0
				chunk_instance.octaves = 4
				chunk_instance.persistence = 0.5
				chunk_instance.lacunarity = 5.0
				chunk_instance.noise_seed = 0
				chunk_instance.height_curve = height_curve
				chunk_instance.terrain_types = [
					{ "name": "Water", "height": 0.3, "color": Color8(64, 96, 255) },
					{ "name": "Sand", "height": 0.4, "color": Color8(238, 221, 136) },
					{ "name": "Grass", "height": 0.6, "color": Color8(136, 204, 102) },
					{ "name": "Mountain", "height": 0.8, "color": Color8(136, 136, 136) },
					{ "name": "Snow", "height": 1.0, "color": Color8(255, 255, 255) }
				]

				chunk_instance.prepare()

				# ✅ Position chunk in world immediately
				chunk_instance.chunk_coords = chunk_coord
				chunk_instance.position = Vector3(
					chunk_coord.x * (chunk_instance.map_width - 1),
					0,
					chunk_coord.y * (chunk_instance.map_height - 1)
				)

				chunk_instance.update_chunk(viewer_pos)
				visible_chunks[chunk_coord] = chunk_instance
			else:
				visible_chunks[chunk_coord].update_chunk(viewer_pos)

			new_chunks[chunk_coord] = visible_chunks[chunk_coord]

	for old_coord in visible_chunks.keys():
		if not new_chunks.has(old_coord):
			var chunk = visible_chunks[old_coord]
			chunk.reset_chunk()
			chunk.hide()
			chunk_pool.append(chunk)

	visible_chunks = new_chunks

func get_chunk_from_pool() -> TerrainChunk:
	if chunk_pool.size() > 0:
		return chunk_pool.pop_back()
	else:
		return chunk_scene.instantiate() as TerrainChunk
