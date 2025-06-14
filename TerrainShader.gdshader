shader_type spatial;

// Thresholds (poți modifica valorile de mai jos din Godot după preferințe)
uniform float water_level    = 0.05;
uniform float beach_level    = 0.10;
uniform float grass_level    = 0.45;
uniform float mountain_level = 0.92;

// Blending zone (tranziție lină)
uniform float blend_width = 0.045;

// Biome colors
uniform vec3 water_color   = vec3(0.25, 0.376, 1.0);      // albastru
uniform vec3 sand_color    = vec3(0.933, 0.867, 0.533);   // galben nisip
uniform vec3 grass_color   = vec3(0.533, 0.8,   0.4);     // verde
uniform vec3 rock_color    = vec3(0.533, 0.533, 0.533);   // gri
uniform vec3 snow_color    = vec3(1.0,   1.0,   1.0);     // alb

uniform float slope_threshold = 0.6; // cât de abrupt = rock, restul = biome normal

// Height normalization
uniform float min_height = 0.0;
uniform float max_height = 1.0;

// Pentru fragment
varying vec3 world_position;
varying vec3 world_normal;

void vertex() {
    world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    world_normal   = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
    float h = 0.0;
    if (max_height > min_height) {
        h = (world_position.y - min_height) / (max_height - min_height);
        h = clamp(h, 0.0, 1.0);
    }
    float slope = 1.0 - dot(world_normal, vec3(0.0, 1.0, 0.0));

    vec3 biome_col;

    // BLENDING LOGIC
    if (h < water_level) {
        biome_col = water_color;
    } else if (h < beach_level) {
        float t = smoothstep(water_level, water_level + blend_width, h);
        biome_col = mix(water_color, sand_color, t);
    } else if (h < grass_level) {
        float t = smoothstep(beach_level, beach_level + blend_width, h);
        biome_col = mix(sand_color, grass_color, t);
    } else if (h < mountain_level) {
        float t = smoothstep(grass_level, grass_level + blend_width, h);
        biome_col = mix(grass_color, rock_color, t);
    } else {
        float t = smoothstep(mountain_level, mountain_level + blend_width, h);
        biome_col = mix(rock_color, snow_color, t);
    }

    // Steep slopes = rock (slope blending)
    if (slope > slope_threshold) {
        // Blending între rock și biome_col în funcție de cât de abrupt e
        float rock_blend = smoothstep(slope_threshold, 1.0, slope);
        biome_col = mix(biome_col, rock_color, rock_blend);
    }

    ALBEDO = biome_col;
}
