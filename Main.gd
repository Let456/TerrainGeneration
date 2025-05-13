extends Node2D


var terrain_types = [
	{"name": "Water", "height": 0.3, "color": Color8(64, 96, 255)},     # blue
	{"name": "Sand", "height": 0.4, "color": Color8(238, 221, 136)},   # light yellow
	{"name": "Grass", "height": 0.6, "color": Color8(136, 204, 102)},  # green
	{"name": "Mountain", "height": 0.8, "color": Color8(136, 136, 136)}, # grey
	{"name": "Snow", "height": 1.0, "color": Color8(255, 255, 255)}    # white
]


@export var map_width: int = 1920
@export var map_height: int = 1080
@export var noise_scale: float = 5.0

@export var octaves: int = 4;
@export var persistence: float = 0.5
@export var lacunarity: float = 10.0
@export var noise_seed: int = 0  # 0 = random seed 

var noise_map: Image

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	var height_map = generate_noise_map(map_width, map_height, noise_scale)
	var color_map = generate_color_map(height_map)
	display_noise_map(color_map)

func generate_noise_map(width: int, height: int, scale: float) -> Array:
	var seed = noise_seed if noise_seed != 0 else randi()
	var noise = FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.seed = seed

	var offsets = []
	for i in range(octaves):
		var offset_x = randi() % 20000 - 10000
		var offset_y = randi() % 20000 - 10000
		offsets.append(Vector2(offset_x, offset_y))

	var height_map = []
	var max_noise = -INF
	var min_noise = INF

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

			if noise_height > max_noise:
				max_noise = noise_height
			if noise_height < min_noise:
				min_noise = noise_height

			height_map[y].append(noise_height)

	# Normalize
	for y in height:
		for x in width:
			var height_value = height_map[y][x]
			var norm_value = (height_value - min_noise) / (max_noise - min_noise)
			height_map[y][x] = norm_value

	return height_map

func generate_color_map(height_map: Array) -> Image:
	var width = height_map[0].size()
	var height = height_map.size()
	var img = Image.create(width, height, false, Image.FORMAT_RGB8)

	for y in height:
		for x in width:
			var h = height_map[y][x]
			var terrain_color = Color.BLACK
			for terrain in terrain_types:
				if h <= terrain["height"]:
					terrain_color = terrain["color"]
					break
			img.set_pixel(x, y, terrain_color)

	return img

func display_noise_map(img: Image) -> void:
	var texture = ImageTexture.create_from_image(img)
	$TextureRect.texture = texture
