shader_type spatial;

// Height thresholds (normalized 0→1) matching your terrain_types:
uniform float water_level    = 0.30;
uniform float beach_level    = 0.40;
uniform float grass_level    = 0.60;
uniform float mountain_level = 0.80;

// Biome colours from Color8 values, normalized to [0..1]:
uniform vec3 water_color   = vec3(64.0, 96.0, 255.0);
uniform vec3 sand_color    = vec3(238.0, 221.0, 136.0);
uniform vec3 grass_color   = vec3(136.0, 204.0, 102.0);
uniform vec3 rock_color    = vec3(136.0, 136.0, 136.0);
uniform vec3 snow_color    = vec3(255.0, 255.0, 255.0);

// How steep before we treat it as cliff [0=only vertical, 1=gentle]:
uniform float slope_threshold = 0.6;

// Must match your GDScript mesh_height export (set in Inspector or via code):
uniform float mesh_height = 50.0;

// Varyings to carry data from vertex → fragment:
varying vec3 world_position;
varying vec3 world_normal;

void vertex() {
    // Compute world‐space position
    world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    // Transform normal as a direction, then normalize
    world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
    // Normalize height to [0..1]
    float h = clamp(world_position.y / mesh_height, 0.0, 1.0);

    // Compute slope: how "steep" this fragment is
    float slope = 1.0 - dot(world_normal, vec3(0.0, 1.0, 0.0));

    // Base biome colour by height thresholds:
    vec3 base_col;
    if      (h < water_level)      base_col = water_color;
    else if (h < beach_level)      base_col = sand_color;
    else if (h < grass_level)      base_col = grass_color;
    else if (h < mountain_level)   base_col = rock_color;
    else                            base_col = snow_color;

    // Override with rock on steep slopes:
    if (slope > slope_threshold) {
        base_col = rock_color;
    }

    ALBEDO = base_col;
}
