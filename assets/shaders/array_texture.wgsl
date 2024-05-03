#import bevy_pbr::{
    forward_io::VertexOutput,
    mesh_view_bindings::view,
    pbr_types::{STANDARD_MATERIAL_FLAGS_DOUBLE_SIDED_BIT, PbrInput, pbr_input_new},
    pbr_functions as fns,
}
#import bevy_core_pipeline::tonemapping::tone_mapping

@group(2) @binding(0) var my_array_texture: texture_2d_array<f32>;
@group(2) @binding(1) var my_array_texture_sampler: sampler;

// shader params
const tex_scale = 10.0;
const planet_scale = 4.0;

@fragment
fn fragment(
    @builtin(front_facing) is_front: bool,
    mesh: VertexOutput,
) -> @location(0) vec4<f32> {

    let terrain_height = length(mesh.world_position) / (planet_scale / 2.0);

    // grass=0 dirt=1 snow=2 sand=3
    var layer: i32 = 3;
    if terrain_height > 1.1 {
        layer = 0;
    }
    if terrain_height > 1.18 {
        layer = 1;
    }
    if terrain_height > 1.22 {
        layer = 2;
    }

    let tex_uv = vec2<f32>(mesh.uv.x * tex_scale * planet_scale % 1.0, mesh.uv.y * tex_scale * planet_scale % 1.0);

    // Prepare a 'processed' StandardMaterial by sampling all textures to resolve
    // the material members
    var pbr_input: PbrInput = pbr_input_new();

    pbr_input.material.base_color = textureSample(my_array_texture, my_array_texture_sampler, tex_uv, layer);
#ifdef VERTEX_COLORS
    pbr_input.material.base_color = pbr_input.material.base_color * mesh.color;
#endif

    let double_sided = (pbr_input.material.flags & STANDARD_MATERIAL_FLAGS_DOUBLE_SIDED_BIT) != 0u;

    pbr_input.frag_coord = mesh.position;
    pbr_input.world_position = mesh.world_position;
    pbr_input.world_normal = fns::prepare_world_normal(
        mesh.world_normal,
        double_sided,
        is_front,
    );

    pbr_input.is_orthographic = view.projection[3].w == 1.0;

    pbr_input.N = fns::apply_normal_mapping(
        pbr_input.material.flags,
        mesh.world_normal,
        double_sided,
        is_front,
#ifdef VERTEX_TANGENTS
#ifdef STANDARD_MATERIAL_NORMAL_MAP
        mesh.world_tangent,
#endif
#endif
        mesh.uv,
        view.mip_bias,
    );
    pbr_input.V = fns::calculate_view(mesh.world_position, pbr_input.is_orthographic);

    return tone_mapping(fns::apply_pbr_lighting(pbr_input), view.color_grading);
}
