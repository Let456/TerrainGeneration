shader_type spatial;

// —––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––
// Height thresholds (normalized 0→1)
uniform float water_level     = 0.05;
uniform float beach_level     = 0.10;
uniform float grass_level     = 0.35;
uniform float mountain_level  = 0.92;

// How wide the blend zones are
uniform float blend_width     = 0.045;

// Texture samplers (assign your PNGs in the Material)
uniform sampler2D water_tex;
uniform sampler2D sand_tex;
uniform sampler2D grass_tex;
uniform sampler2D rock_tex;
uniform sampler2D snow_tex;

// UV tiling scale in world‐units (repeats per unit length)
uniform float texture_scale   = 0.1;

// Slope override: how steep before forcing rock
uniform float slope_threshold = 0.6;

// Global height normalization
uniform float min_height = 0.0;
uniform float max_height = 1.0;

// Passed from vertex to fragment
varying vec3 world_position;
varying vec3 world_normal;

void vertex() {
    // capture world‐space position and normal
    world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    world_normal   = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
    // 1) Normalize height to [0,1]
    float h = 0.0;
    if (max_height > min_height) {
        h = (world_position.y - min_height) / (max_height - min_height);
        h = clamp(h, 0.0, 1.0);
    }

    // 2) Compute slope (0=flat, 1=vertical)
    float slope = 1.0 - dot(world_normal, vec3(0.0, 1.0, 0.0));

    // 3) Compute blend‐weights for each biome
    float w_water =       1.0 - smoothstep(water_level,    water_level + blend_width,    h);
    float w_sand  = smoothstep(water_level,    water_level + blend_width,    h)
                   * (1.0 - smoothstep(beach_level,    beach_level + blend_width,    h));
    float w_grass = smoothstep(beach_level,    beach_level + blend_width,    h)
                   * (1.0 - smoothstep(grass_level,    grass_level + blend_width,    h));
    float w_rock  = smoothstep(grass_level,    grass_level + blend_width,    h)
                   * (1.0 - smoothstep(mountain_level, mountain_level + blend_width, h));
    float w_snow  = smoothstep(mountain_level, mountain_level + blend_width,    h);

    // 4) Compute continuous UV from world_position.xz
    //    fract() wraps into [0,1] so the texture tiles seamlessly across chunks
    vec2 uv = fract(world_position.xz * texture_scale);

    // 5) Sample each texture and weight it
    vec3 col =
        w_water * texture(water_tex, uv).rgb +
        w_sand  * texture(sand_tex,  uv).rgb +
        w_grass * texture(grass_tex, uv).rgb +
        w_rock  * texture(rock_tex,  uv).rgb +
        w_snow  * texture(snow_tex,  uv).rgb;

    // 6) Slope override: steep faces become rock
    float rock_blend = smoothstep(slope_threshold, 1.0, slope);
    ALBEDO = mix(col, texture(rock_tex, uv).rgb, rock_blend);
}
