// Shader for post-processing effects

#import bevy_core_pipeline::fullscreen_vertex_shader::FullscreenVertexOutput
#import bevy_render::view::View

@group(0) @binding(0) var screen_texture: texture_2d<f32>;
@group(0) @binding(1) var texture_sampler: sampler;
@group(0) @binding(2) var depth_texture: texture_depth_2d;
@group(0) @binding(3) var<uniform> view: View;

struct PostProcessSettings {
    planet_scale: f32,
    camera_position: vec3<f32>,
    sun_position: vec3<f32>,
    proj_mat: mat4x4<f32>,
    inverse_proj: mat4x4<f32>,
    view_mat: mat4x4<f32>,
    inverse_view: mat4x4<f32>,
#ifdef SIXTEEN_BYTE_ALIGNMENT
    // WebGL2 structs must be 16 byte aligned.
    _webgl2_padding: vec3<f32>
#endif
}
@group(0) @binding(4) var<uniform> settings: PostProcessSettings;

// consts
const max_f32 = 99999999.99;
const ocean_depth_mult = 14.4;
const ocean_alpha_mult = 24.4;
const ocean_color_a = vec4(0.4, 1., 0.85, 1.);
const ocean_color_b = vec4(0.1, 0.2, 0.4, 1.);
const ocean_specular_smoothness = 0.9;
const sun_hot = vec4(1., 0.9, 0.5, 1.);
const sun_cool = vec4(9., 0.6, 0., 1.);

/// Convert uv [0.0 .. 1.0] coordinate to ndc space xy [-1.0 .. 1.0]
fn uv_to_ndc(uv: vec2<f32>) -> vec2<f32> {
    return uv * vec2(2.0, -2.0) + vec2(-1.0, 1.0);
}
/// returns the (0.0, 0.0) .. (1.0, 1.0) position within the viewport for the current render target
/// [0 .. render target viewport size] eg. [(0.0, 0.0) .. (1280.0, 720.0)] to [(0.0, 0.0) .. (1.0, 1.0)]
fn frag_coord_to_uv(frag_coord: vec2<f32>) -> vec2<f32> {
    return (frag_coord - view.viewport.xy) / view.viewport.zw;
}
/// Convert frag coord to ndc
fn frag_coord_to_ndc(frag_coord: vec4<f32>) -> vec3<f32> {
    return vec3(uv_to_ndc(frag_coord_to_uv(frag_coord.xy)), frag_coord.z);
}
/// Convert a clip space position to world space
fn position_clip_to_world(clip_pos: vec4<f32>) -> vec3<f32> {
    let world_pos = (settings.view_mat * settings.inverse_proj) * clip_pos;
    return world_pos.xyz;
}
/// Convert ndc depth to linear view z. 
/// Note: Depth values in front of the camera will be negative as -z is forward
fn depth_ndc_to_view_z(ndc_depth: f32) -> f32 {
    return -settings.proj_mat[3][2] / ndc_depth;// + settings.proj_mat[3][2];
}

// gets distances to sphere collisions, 
// or returns [max_f32, 0.0] if no collisions
fn ray_sphere_intersection(
    center: vec3<f32>,
    radius: f32,
    ray_origin: vec3<f32>,
    ray_direction: vec3<f32>,
) -> vec2<f32> {
    let offset = ray_origin - center;
    let a = dot(ray_direction, ray_direction);
    let b = 2.0 * dot(offset, ray_direction);
    let c = dot(offset, offset) - radius * radius;
    let discriminant = b * b - 4 * a * c;
    // discriminant < 0  no intersections
    // discriminant = 0  one intersection
    // discriminant > 0  two intersections
    if (discriminant > 0) {
        let s = sqrt(discriminant);
        let distance_to_sphere_near = max(0.0, (-b - s) / (2.0 * a));
        let distance_to_sphere_far = (-b + s) / (2.0 * a);
        if distance_to_sphere_far >= 0 {
            return vec2<f32>(distance_to_sphere_near, distance_to_sphere_far - distance_to_sphere_near);
        }
    }
    // no intersection
    return vec2<f32>(max_f32, 0.0);
}

@fragment
fn fragment(
#ifdef MULTISAMPLED
    @builtin(sample_index) sample_index: u32,
#endif
    in: FullscreenVertexOutput
) -> @location(0) vec4<f32> {
#ifndef MULTISAMPLED
    let sample_index = 0u;
#endif

    var original_color = textureSample(screen_texture, texture_sampler, in.uv);

    // raycast
    let ndc = frag_coord_to_ndc(in.position);
    let view_vector = position_clip_to_world(vec4<f32>(ndc.xy, 0.0, 1.0));
    let ray_direction = normalize(view_vector);
    let ray_origin = settings.camera_position;

    // scene depth
    let depth_value = textureLoad(depth_texture, vec2<i32>(in.position.xy), i32(sample_index));
    let scene_depth = -depth_ndc_to_view_z(depth_value);

    // space
    if depth_value < 0.000001 {
        let sun_radius = 1.;
        let sun_hit = ray_sphere_intersection(settings.sun_position, sun_radius, ray_origin.xyz, ray_direction);
        if sun_hit.y > 0.0 {
            let sun_intensity = pow(sun_hit.y / (2. * sun_radius), 3.);
            original_color = mix(sun_cool, sun_hot, sun_intensity);
        }
    }

    // ocean
    let sphere_center = vec3<f32>(0.0, 0.0, 0.0);
    let sphere_radius = settings.planet_scale / 2.0;
    let ocean_hit = ray_sphere_intersection(sphere_center, sphere_radius, ray_origin.xyz, ray_direction);
    let dist_to_ocean = ocean_hit.x;
    let dist_through_ocean = ocean_hit.y;
    let ocean_view_depth = min(dist_through_ocean, scene_depth - dist_to_ocean);

    if ocean_view_depth > 0.0 {
        // water color by ocean depth
        let optical_depth = 1 - exp(-ocean_view_depth * ocean_depth_mult);
        let alpha = 1 - exp(-ocean_view_depth * ocean_alpha_mult);
        let ocean_color = mix(ocean_color_a, ocean_color_b, optical_depth);

        /// specular
        let dir_to_sun = normalize(settings.sun_position);
        let ocean_normal = normalize(ray_origin + ray_direction * dist_to_ocean);
        let specular_angle = acos(dot(normalize(dir_to_sun - ray_direction), ocean_normal));
        let specular_exponent = specular_angle / (1. - ocean_specular_smoothness);
        let specular_highlight = exp(-specular_exponent * specular_exponent);
        let diffuse_lighting = clamp(saturate(dot(ocean_normal, dir_to_sun)), 0.03, 1.0);
        let lit_ocean_color = ocean_color * diffuse_lighting + specular_highlight;

        // water transparency by depth
        original_color = mix(original_color, lit_ocean_color, alpha);
    }

    // Sample each color channel with an arbitrary shift
    return original_color;
}
