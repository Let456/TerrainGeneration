extends Node3D

@export var viewer: Node3D
@export var chunk_scene: PackedScene
@export var view_distance: int = 2
@export var height_curve: Curve
@export var octaves: int = 4  # must match the chunks' octaves

var chunk_size = 240
var visible_chunks := {}
var chunk_pool: Array = []
var last_viewer_position := Vector3.INF
const viewer_move_threshold := 200.0

# new shared seed & offsets
var rng_seed: int
var octave_offsets: Array = []

var active_chunk_jobs := 0

func _ready():
	randomize()
	rng_seed = randi()
	# generate one shared list of random offsets for each octave
	for i in range(octaves):
		var ox = randi() % 200000 - 100000
		var oy = randi() % 200000 - 100000
		octave_offsets.append(Vector2(ox, oy))

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
	var new_chunks := {}

	for y in range(-view_distance, view_distance + 1):
		for x in range(-view_distance, view_distance + 1):
			var coord = viewer_chunk + Vector2(x, y)
			if not visible_chunks.has(coord):
				var c = get_chunk_from_pool()
				if c == null:
					continue

				# parent & show
				if c.get_parent() != self:
					if c.get_parent():
						c.get_parent().remove_child(c)
					add_child(c)
				c.show()

				# initialize
				c.map_width     = 241
				c.map_height    = 241
				c.noise_scale   = 40.0
				c.mesh_height   = 20.0
				c.octaves       = octaves
				c.persistence   = 0.5
				c.lacunarity    = 5.0
				c.noise_seed    = rng_seed
				c.height_curve  = height_curve
				c.octave_offsets = octave_offsets  # pass the shared offsets
				c.terrain_types = [
					{ "name": "Water",    "height": 0.3, "color": Color8(64,  96,  255) },
					{ "name": "Sand",     "height": 0.4, "color": Color8(238, 221, 136) },
					{ "name": "Grass",    "height": 0.6, "color": Color8(136, 204, 102) },
					{ "name": "Mountain", "height": 0.8, "color": Color8(136, 136, 136) },
					{ "name": "Snow",     "height": 1.0, "color": Color8(255, 255, 255) }
				]

				c.prepare()
				c.chunk_coords = coord
				c.position = Vector3(
					coord.x * (c.map_width - 1),
					0,
					coord.y * (c.map_height - 1)
				)

				c.update_chunk(viewer_pos)
				visible_chunks[coord] = c
			else:
				visible_chunks[coord].update_chunk(viewer_pos)

			new_chunks[coord] = visible_chunks[coord]

	# recycle old chunks
	for old in visible_chunks.keys():
		if not new_chunks.has(old):
			var c = visible_chunks[old]
			c.reset_chunk()
			c.hide()
			chunk_pool.append(c)

	visible_chunks = new_chunks

func get_chunk_from_pool() -> Node:
	if chunk_pool.size() > 0:
		return chunk_pool.pop_back()
	return chunk_scene.instantiate()
