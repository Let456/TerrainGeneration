extends Node3D
class_name TerrainChunk

signal mesh_ready(mesh: ArrayMesh)

#––– constants ––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––
const TREE_MESH: ArrayMesh = preload("res://CombinedTree.tres")

#––– exports ––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––
@export var map_width:           int    = 241
@export var map_height:          int    = 241
@export var noise_scale:         float  = 80.0
@export var mesh_height:         float  = 20.0
@export var octaves:             int    = 3
@export var persistence:         float  = 0.35
@export var lacunarity:          float  = 2.5
@export var noise_seed:          int    = 0
@export var height_curve:        Curve
@export var use_falloff:         bool   = false
@export var use_flat_shading:    bool   = false
@export var global_min_height:   float  = 0.0
@export var global_max_height:   float  = 1.0

#––– tree‐spawn settings –––––––––––––––––––––––––––––––––––––––––––––––––
@export var trees_per_chunk:     int    = 1
@export var enable_tree_spawn: bool = true


#––– internal state –––––––––––––––––––––––––––––––––––––––––––––––––––––
var height_map: Array            = []
var amplitude_sum: float         = 0.0
var octave_offsets: Array        = []
var falloff_map: Array           = []
var height_curve_lookup: Array   = []
var chunk_coords: Vector2        = Vector2.ZERO
var current_lod: int             = -1
var job_pending: bool            = false

const MAX_COLLISION_LOD := 10
var _collision_body: StaticBody3D
var _collision_shape: CollisionShape3D

#––– one‐time flag so we only spawn once per chunk –––––––––––––––––––––––––
var _trees_spawned := false

func _ready():
	# 1) amplitude sum
	amplitude_sum = 0.0
	var amp = 1.0
	for i in range(octaves):
		amplitude_sum += amp
		amp *= persistence

	# 2) random octave offsets
	randomize()
	for i in range(octaves):
		octave_offsets.append(
			Vector2(randi() % 200000 - 100000,
					randi() % 200000 - 100000)
		)

	# 3) optional falloff
	falloff_map = generate_falloff_map(map_width, map_height)

	# 4) connect
	connect("mesh_ready", Callable(self, "_on_mesh_ready"))

func prepare():
	height_curve_lookup.clear()
	if height_curve:
		for i in range(256):
			height_curve_lookup.append(height_curve.sample(i / 255.0))
	else:
		push_warning("TerrainChunk: height_curve is null!")

func reset_chunk():
	if $MeshInstance3D:
		$MeshInstance3D.mesh = null
	_trees_spawned = false   # allow respawn after LOD change

func update_chunk(viewer_pos: Vector3):
	var d2 = distance_squared_to_chunk(viewer_pos)
	var new_lod = 0
	if d2 > 700*700:   new_lod = 4
	elif d2 > 500*500: new_lod = 3
	elif d2 > 300*300: new_lod = 2
	elif d2 > 100*100: new_lod = 1

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

func distance_squared_to_chunk(vp: Vector3) -> float:
	var size = map_width - 1
	var minb = global_position
	var maxb = minb + Vector3(size, mesh_height, size)
	var cx = clamp(vp.x, minb.x, maxb.x)
	var cy = clamp(vp.y, minb.y, maxb.y)
	var cz = clamp(vp.z, minb.z, maxb.z)
	return Vector3(cx,cy,cz).distance_squared_to(vp)

func add_job_to_pool():
	job_pending = true
	TerrainManager.active_chunk_jobs += 1
	WorkerThreadPool.add_task(Callable(self, "thread_generate_chunk"), false, "Generate mesh")

func thread_generate_chunk():
	height_map = generate_noise_map(map_width, map_height, noise_scale, chunk_coords)
	var mesh = generate_terrain_mesh(height_map)
	call_deferred("emit_signal", "mesh_ready", mesh)

func _on_mesh_ready(mesh: ArrayMesh):
	job_pending = false
	TerrainManager.active_chunk_jobs -= 1

	$MeshInstance3D.mesh = mesh
	$MeshInstance3D.material_override = preload("res://TerrainMaterial.tres").duplicate()
	global_transform.origin = Vector3(
		chunk_coords.x * (map_width - 1),
		0,
		chunk_coords.y * (map_height - 1)
	)
	set_shader_minmax($MeshInstance3D.material_override,
					  global_min_height, global_max_height)
	_update_collider(mesh)

	await get_tree().physics_frame
	spawn_trees()

func set_shader_minmax(mat, hmin, hmax):
	if mat is ShaderMaterial:
		mat.set_shader_parameter("min_height", hmin)
		mat.set_shader_parameter("max_height", hmax)

func apply_height_curve(n: float) -> float:
	var idx = clamp(int(n*255.0), 0, 255)
	return height_curve_lookup[idx]

func spawn_trees() -> void:
	# global on/off from TerrainManager
	if not enable_tree_spawn:
		return

	# only spawn once per chunk
	if _trees_spawned:
		return
	_trees_spawned = true

	# place exactly `trees_per_chunk` large trees at Y=0
	for i in range(trees_per_chunk):
		var mi = MeshInstance3D.new()
		mi.mesh = TREE_MESH
		# make them super‐tall
		mi.scale = Vector3(7, 10, 7)

		# random X,Z within this chunk
		var wx = chunk_coords.x * (map_width - 1) + randf() * (map_width - 1)
		var wz = chunk_coords.y * (map_height - 1) + randf() * (map_height - 1)
		mi.position = Vector3(wx, 5, wz)

		add_child(mi)


func generate_noise_map(w: int, h: int, scale: float, coords: Vector2) -> Array:
	var noise = FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.seed = noise_seed

	var m := []
	for yy in range(h):
		m.append([])
		for xx in range(w):
			var val = 0.0
			var amp = 1.0
			var freq = 1.0
			for o in range(octaves):
				val += noise.get_noise_2d(
					((coords.x*(w-1)+xx)/scale)*freq + octave_offsets[o].x,
					((coords.y*(h-1)+yy)/scale)*freq + octave_offsets[o].y
				) * amp
				amp *= persistence
				freq *= lacunarity
			var n = (val + amplitude_sum)/(2*amplitude_sum)
			if use_falloff and falloff_map.size() == h:
				n = clamp(n - falloff_map[yy][xx], 0.0, 1.0)
			m[yy].append(clamp(n, 0.0, 1.0))
	return m

func generate_falloff_map(w: int, h: int) -> Array:
	var f := []
	for y in range(h):
		f.append([])
		for x in range(w):
			var nx = x/float(w-1)*2 - 1
			var ny = y/float(h-1)*2 - 1
			var d  = max(abs(nx), abs(ny))
			var da = pow(d, 3.0)
			var inv= pow(2.2 - 2.2*d, 3.0)
			f[y].append(da/(da+inv))
	return f

func _update_collider(mesh: ArrayMesh):
	if current_lod <= MAX_COLLISION_LOD:
		if not _collision_body:
			_collision_body = StaticBody3D.new()
			add_child(_collision_body)
		if not _collision_shape:
			_collision_shape = CollisionShape3D.new()
			_collision_body.add_child(_collision_shape)
		var arr = mesh.surface_get_arrays(0)
		var shape = ConcavePolygonShape3D.new()
		shape.data = arr[Mesh.ARRAY_VERTEX]
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
	var uv_scale = 8.0

	for yy in range(0, h-1, step):
		for xx in range(0, w-1, step):
			var xx1 = min(xx+step, w-1)
			var yy1 = min(yy+step, h-1)
			var n00 = height_map[yy][xx]
			var n10 = height_map[yy][xx1]
			var n01 = height_map[yy1][xx]
			var n11 = height_map[yy1][xx1]
			var p00 = Vector3(xx,  apply_height_curve(n00)*mesh_height, yy)
			var p10 = Vector3(xx1, apply_height_curve(n10)*mesh_height, yy)
			var p01 = Vector3(xx,  apply_height_curve(n01)*mesh_height, yy1)
			var p11 = Vector3(xx1,apply_height_curve(n11)*mesh_height,yy1)
			var u00 = Vector2(xx/float(w-1),yy/float(h-1))*uv_scale
			var u10 = Vector2(xx1/float(w-1),yy/float(h-1))*uv_scale
			var u01 = Vector2(xx/float(w-1),yy1/float(h-1))*uv_scale
			var u11 = Vector2(xx1/float(w-1),yy1/float(h-1))*uv_scale

			if use_flat_shading:
				var nA = (p11-p00).cross(p10-p00).normalized()
				st.set_normal(nA)
				st.set_uv(u00); st.add_vertex(p00)
				st.set_uv(u10); st.add_vertex(p10)
				st.set_uv(u11); st.add_vertex(p11)
				var nB = (p01-p00).cross(p11-p00).normalized()
				st.set_normal(nB)
				st.set_uv(u00); st.add_vertex(p00)
				st.set_uv(u11); st.add_vertex(p11)
				st.set_uv(u01); st.add_vertex(p01)
			else:
				st.set_uv(u00); st.add_vertex(p00)
				st.set_uv(u10); st.add_vertex(p10)
				st.set_uv(u11); st.add_vertex(p11)
				st.set_uv(u00); st.add_vertex(p00)
				st.set_uv(u11); st.add_vertex(p11)
				st.set_uv(u01); st.add_vertex(p01)

	if not use_flat_shading:
		st.generate_normals()

	return st.commit()
