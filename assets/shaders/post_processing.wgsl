// Shader for post-processing effects

#import bevy_core_pipeline::fullscreen_vertex_shader::FullscreenVertexOutput
#import bevy_render::view::View

@group(0) @binding(0) var screen_texture: texture_2d<f32>;
@group(0) @binding(1) var texture_sampler: sampler;
@group(0) @binding(2) var depth_texture: texture_depth_2d;
@group(0) @binding(3) var<uniform> view: View;

struct PostProcessSettings {
    planet_center: vec3<f32>,
    planet_scale: f32,
    sun_position: vec3<f32>,
    camera_position: vec3<f32>,
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
const epsilon_f32 = 0.0000001;
const ocean_depth_mult = 14.4;
const ocean_alpha_mult = 24.4;
const ocean_color_a = vec4(0.4, 1., 0.85, 1.);
const ocean_color_b = vec4(0.1, 0.2, 0.4, 1.);
const ocean_specular_smoothness = 0.9;
const sun_hot = vec4(1., 0.9, 0.5, 1.);
const sun_cool = vec4(9., 0.6, 0., 1.);
const atmo_scale = 2.;
const num_optical_depth_points = 10;
const num_in_scattering_points = 10;
const density_falloff = 13.;
const scattering_wavelengths = vec3(700., 530., 440.);
const scattering_strength = 4.;

/// Convert uv [0.0 .. 1.0] coordinate to ndc space xy [-1.0 .. 1.0]
fn uv_to_ndc(uv: vec2<f32>) -> vec2<f32> {
    return uv * vec2(2., -2.) + vec2(-1., 1.);
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
    let b = 2. * dot(offset, ray_direction);
    let c = dot(offset, offset) - radius * radius;
    let discriminant = b * b - 4 * a * c;
    // discriminant < 0  no intersections
    // discriminant = 0  one intersection
    // discriminant > 0  two intersections
    if (discriminant > 0) {
        let s = sqrt(discriminant);
        let distance_to_sphere_near = max(0., (-b - s) / (2. * a));
        let distance_to_sphere_far = (-b + s) / (2. * a);
        if distance_to_sphere_far >= 0 {
            return vec2<f32>(distance_to_sphere_near, distance_to_sphere_far - distance_to_sphere_near);
        }
    }
    // no intersection
    return vec2<f32>(max_f32, 0.);
}

// approximation of atmospheric density at point
fn atmo_density_at_point(
    density_sample_point: vec3<f32>,
    atmo_radius: f32,
) -> f32 {
    let planet_radius = settings.planet_scale / 2.;

    let height_above_surface = length(density_sample_point - settings.planet_center) - planet_radius;
    let height_01 = height_above_surface / (atmo_radius - planet_radius);
    return exp(-height_01 * density_falloff) * (1. - height_01);
}

// approximation of average atmospheric density along a ray
fn calculate_optical_depth(
    ray_origin: vec3<f32>,
    ray_direction: vec3<f32>,
    ray_length: f32,
    atmo_radius: f32,
) -> f32 {
    let step_size = ray_length / (f32(num_optical_depth_points) - 1.);
    var density_sample_point = ray_origin;
    var optical_depth = 0.;

    for (var i = 0; i < num_optical_depth_points; i += 1) {
        let local_density = atmo_density_at_point(density_sample_point, atmo_radius);
        optical_depth += local_density * step_size;
        density_sample_point += ray_direction * step_size;
    }

    return optical_depth;
}

// statistical approximation of atmospheric scattering
fn calculate_light(
    ray_origin: vec3<f32>,
    ray_direction: vec3<f32>,
    ray_length: f32,
    original_color: vec3<f32>,
    atmo_radius: f32,
    dir_to_sun: vec3<f32>,
) -> vec3<f32> {
    let planet_radius = settings.planet_scale / 2.;
    let scattering_coeff = vec3<f32>(
        pow(400. / scattering_wavelengths.x, 4.) * scattering_strength,
        pow(400. / scattering_wavelengths.y, 4.) * scattering_strength,
        pow(400. / scattering_wavelengths.z, 4.) * scattering_strength,
    );

    let step_size = ray_length / (f32(num_in_scattering_points) - 1.);
    var in_scatter_point = ray_origin;
    var in_scattered_light = vec3<f32>(0., 0., 0.);
    var view_ray_optical_depth = 0.;

    for (var i = 0; i < num_in_scattering_points; i += 1) {
        let sun_ray_length = ray_sphere_intersection(settings.planet_center, atmo_radius, in_scatter_point, dir_to_sun).y;
        let sun_ray_optical_depth = calculate_optical_depth(in_scatter_point, dir_to_sun, sun_ray_length, atmo_radius);
        view_ray_optical_depth = calculate_optical_depth(in_scatter_point, -ray_direction, step_size * f32(i), atmo_radius);
        let transmittance = exp(-(sun_ray_optical_depth + view_ray_optical_depth) * scattering_coeff);
        let local_density = atmo_density_at_point(in_scatter_point, atmo_radius);

        in_scattered_light += local_density * transmittance * scattering_coeff * step_size;
        in_scatter_point += ray_direction * step_size;
    }

    let original_color_transmittance = exp(-view_ray_optical_depth);
    return original_color * original_color_transmittance + in_scattered_light;
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
    let view_vector = position_clip_to_world(vec4<f32>(ndc.xy, 0., 1.));
    let ray_direction = normalize(view_vector);
    let ray_origin = settings.camera_position;
    let dir_to_sun = normalize(settings.sun_position);

    // scene depth
    let depth_value = textureLoad(depth_texture, vec2<i32>(in.position.xy), i32(sample_index));
    let scene_depth = -depth_ndc_to_view_z(depth_value);

    // space
    if depth_value < 0.000001 {
        let sun_radius = 1.;
        let sun_hit = ray_sphere_intersection(settings.sun_position, sun_radius, ray_origin.xyz, ray_direction);
        if sun_hit.y > 0. {
            let sun_intensity = pow(sun_hit.y / (2. * sun_radius), 3.);
            original_color = mix(sun_cool, sun_hot, sun_intensity);
        }
    }

    // ocean
    let ocean_radius = settings.planet_scale / 2.;
    let ocean_hit = ray_sphere_intersection(settings.planet_center, ocean_radius, ray_origin.xyz, ray_direction);
    let dist_to_ocean = ocean_hit.x;
    let dist_through_ocean = ocean_hit.y;
    let ocean_view_depth = min(dist_through_ocean, scene_depth - dist_to_ocean);

    if ocean_view_depth > 0. {
        // water color by ocean depth
        let optical_depth = 1 - exp(-ocean_view_depth * ocean_depth_mult);
        let alpha = 1 - exp(-ocean_view_depth * ocean_alpha_mult);
        let ocean_color = mix(ocean_color_a, ocean_color_b, optical_depth);

        /// specular
        let ocean_normal = normalize(ray_origin + ray_direction * dist_to_ocean);
        let specular_angle = acos(dot(normalize(dir_to_sun - ray_direction), ocean_normal));
        let specular_exponent = specular_angle / (1. - ocean_specular_smoothness);
        let specular_highlight = exp(-specular_exponent * specular_exponent);
        let diffuse_lighting = clamp(saturate(dot(ocean_normal, dir_to_sun)), 0.03, 1.);
        let lit_ocean_color = ocean_color * diffuse_lighting + specular_highlight;

        // water transparency by depth
        original_color = mix(original_color, lit_ocean_color, alpha);
    }

    // atmosphere
    let atmo_radius = atmo_scale * settings.planet_scale / 2.;
    let atmo_hit = ray_sphere_intersection(settings.planet_center, atmo_radius, ray_origin.xyz, ray_direction);
    let dist_to_atmo = atmo_hit.x;
    let surface_dist = min(scene_depth, dist_to_ocean);
    let dist_through_atmo = min(atmo_hit.y, surface_dist - dist_to_atmo);

    if dist_through_atmo > 0. {
        let point_in_atmo = ray_origin + ray_direction * (dist_to_atmo + epsilon_f32);
        let light = calculate_light(point_in_atmo, ray_direction, (dist_through_atmo - epsilon_f32 * 2.), original_color.rgb, atmo_radius, dir_to_sun);
        original_color = vec4<f32>(light, 1.);
    }

    // Sample each color channel with an arbitrary shift
    return original_color;
}
