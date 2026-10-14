shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// =============================================================================
// Ground Shader with Hard Corners, 3 Colors / Textures, and Connectivity Mask
// =============================================================================

// Colors
uniform vec4 color_base : source_color = vec4(0.24, 0.27, 0.31, 1.0);        // Default base ground
uniform vec4 color_slash : source_color = vec4(0.12, 0.82, 1.0, 1.0);       // Disconnected slash (cyan)
uniform vec4 color_connected : source_color = vec4(0.15, 0.95, 0.35, 1.0);   // Connected to center (green!)

// Textures (filter_nearest gives sharp hard pixel corners!)
uniform sampler2D texture_base : hint_default_white, filter_nearest, repeat_enable;
uniform sampler2D texture_slash : hint_default_white, filter_nearest, repeat_enable;
uniform bool use_texture_base = false;
uniform bool use_texture_slash = false;
uniform vec4 texture_base_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 texture_slash_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);

// Mask Map (filter_nearest produces razor-sharp hard square corners)
// R = Disconnected slash fading intensity (1.0 -> 0.0 over 5s)
// G = Connected state (turns green & boosts speed)
// B = Center permanent patch (always green & boosted)
uniform sampler2D mask_texture : hint_default_black, filter_nearest, repeat_disable;

// Dimensions & Mapping
uniform vec2 ground_size = vec2(60.0, 60.0);
uniform vec2 ground_offset = vec2(0.0, 0.0);
uniform vec2 uv_scale_base = vec2(12.0, 12.0);
uniform vec2 uv_scale_slash = vec2(12.0, 12.0);

// Surface properties
uniform float base_roughness : hint_range(0.0, 1.0) = 0.85;
uniform float slash_roughness : hint_range(0.0, 1.0) = 0.25;
uniform float slash_emission_energy : hint_range(0.0, 5.0) = 1.0;
uniform float connected_emission_energy : hint_range(0.0, 5.0) = 1.8;

varying vec3 v_world_pos;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Normalized mask UV (0.0 to 1.0)
	vec2 mask_uv = (v_world_pos.xz - ground_offset) / ground_size + vec2(0.5, 0.5);
	mask_uv = clamp(mask_uv, vec2(0.0), vec2(1.0));

	// Sample mask with filter_nearest for hard 90-degree corners
	vec4 mask_sample = texture(mask_texture, mask_uv);
	float disconnected_val = mask_sample.r;
	float connected_val = mask_sample.g;
	float center_val = mask_sample.b;

	// Hard thresholding (sharp boundaries, no blurry transition)
	bool is_connected = (connected_val > 0.4) || (center_val > 0.4);
	bool is_slashed = (disconnected_val > 0.02);

	vec2 tex_uv = (v_world_pos.xz - ground_offset) / ground_size;

	// 1. Base ground appearance
	vec3 base_result = color_base.rgb;
	if (use_texture_base) {
		vec4 base_tex_sample = texture(texture_base, tex_uv * uv_scale_base);
		base_result = base_tex_sample.rgb * texture_base_tint.rgb;
	}

	// 2. Disconnected slash appearance
	vec3 slash_result = color_slash.rgb;
	if (use_texture_slash) {
		vec4 slash_tex_sample = texture(texture_slash, tex_uv * uv_scale_slash);
		slash_result = slash_tex_sample.rgb * texture_slash_tint.rgb;
	}

	// 3. Connected slash & center patch appearance (GREEN!)
	vec3 connected_result = color_connected.rgb;
	if (use_texture_slash) {
		vec4 slash_tex_sample = texture(texture_slash, tex_uv * uv_scale_slash);
		connected_result = slash_tex_sample.rgb * color_connected.rgb;
	}

	// Final surface blending with hard corners
	vec3 final_color = base_result;
	float final_roughness = base_roughness;
	vec3 final_emission = vec3(0.0);

	if (is_connected) {
		// Connected to center: TURN GREEN with glowing emission
		final_color = connected_result;
		final_roughness = slash_roughness;
		final_emission = connected_result * connected_emission_energy;
	} else if (is_slashed) {
		// Disconnected: slash color with fading intensity over 5 seconds
		float fade_factor = clamp(disconnected_val, 0.0, 1.0);
		final_color = mix(base_result, slash_result, fade_factor);
		final_roughness = mix(base_roughness, slash_roughness, fade_factor);
		final_emission = slash_result * (fade_factor * slash_emission_energy);
	}

	ALBEDO = final_color;
	ROUGHNESS = final_roughness;
	EMISSION = final_emission;
}
