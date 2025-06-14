extends Node3D

@export var viewer: Node3D
@export var chunk_scene: PackedScene
@export var view_distance: int = 2
@export var height_curve: Curve
@export var octaves: int = 4
@export var use_falloff: bool = false
@export var falloff_a := 3.0
@export var falloff_b := 2.2
@export var use_flat_shading: bool = false

var falloff_map: Array = []
var chunk_size := 240
var visible_chunks := {}
var chunk_pool: Array = []
var last_viewer_position := Vector3.INF
const viewer_move_threshold := 200.0
var active_chunk_jobs: int = 0

var rng_seed: int
var octave_offsets: Array = []

var lod_timer: Timer

func _ready():
	randomize()
	rng_seed = randi()
	for i in range(octaves):
		var ox = randi() % 200000 - 100000
		var oy = randi() % 200000 - 100000
		octave_offsets.append(Vector2(ox, oy))

	falloff_map = generate_falloff_map(241, 241)

	lod_timer = Timer.new()
	lod_timer.wait_time = 0.17
	lod_timer.one_shot = false
	lod_timer.autostart = true
	add_child(lod_timer)
	lod_timer.connect("timeout", Callable(self, "_on_lod_timer_timeout"))

func _process(_delta):
	if not viewer:
		return
	var vp = viewer.global_position
	if vp.distance_squared_to(last_viewer_position) > viewer_move_threshold * viewer_move_threshold:
		last_viewer_position = vp
		var vc = Vector2(floor(vp.x / chunk_size), floor(vp.z / chunk_size))
		update_visible_chunks(vc, vp)

func _on_lod_timer_timeout():
	if not viewer:
		return
	var vp = viewer.global_position
	for chunk in visible_chunks.values():
		chunk.update_chunk(vp)

func update_visible_chunks(viewer_chunk: Vector2, viewer_pos: Vector3):
	var new_chunks := {}
	for y in range(-view_distance, view_distance + 1):
		for x in range(-view_distance, view_distance + 1):
			var coord = viewer_chunk + Vector2(x, y)
			if not visible_chunks.has(coord):
				var c = get_chunk_from_pool()
				if c == null:
					continue
				if c.get_parent() != self:
					if c.get_parent(): c.get_parent().remove_child(c)
					add_child(c)
				c.show()

				# configure all your parameters here
				c.map_width        = 241
				c.map_height       = 241
				c.noise_scale      = 20.0
				c.mesh_height      = 50.0
				c.octaves          = octaves
				c.persistence      = 0.8
				c.lacunarity       = 3.0
				c.noise_seed       = rng_seed
				c.use_falloff      = use_falloff
				c.falloff_map      = falloff_map
				c.height_curve     = height_curve
				c.octave_offsets   = octave_offsets
				c.use_flat_shading = use_flat_shading

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

func generate_falloff_map(w: int, h: int) -> Array:
	var map := []
	for y in range(h):
		map.append([])
		for x in range(w):
			var nx = x / float(w - 1) * 2.0 - 1.0
			var ny = y / float(h - 1) * 2.0 - 1.0
			var d = max(abs(nx), abs(ny))
			var da = pow(d, falloff_a)
			var inv = pow(falloff_b - falloff_b * d, falloff_a)
			map[y].append(da / (da + inv))
	return map
