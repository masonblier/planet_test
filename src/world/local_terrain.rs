use crate::GameState;
use crate::loading::{TextureAssets,SettingsConfigAsset,SettingsConfigAssets};

use bevy::{
    prelude::*,
    reflect::TypePath,  
    render::render_resource::{AsBindGroup, ShaderRef},
};
use noise::{NoiseFn, Perlin};


// This plugin renders local terrain at a higher-lod view for the demo
pub struct LocalTerrainPlugin;
impl Plugin for LocalTerrainPlugin {
    fn build(&self, app: &mut App) {
        app
            .add_plugins((
                MaterialPlugin::<ArrayTextureMaterial>::default(),
            ))
            .add_systems(OnEnter(GameState::Playing), setup_array_texture);
    }
}

fn setup_array_texture(
    mut commands: Commands,
    textures: Res<TextureAssets>,
    mut images: ResMut<Assets<Image>>,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<ArrayTextureMaterial>>,
    config_handles: Res<SettingsConfigAssets>,
    config_assets: Res<Assets<SettingsConfigAsset>>,
) { 
    let image = images.get_mut(&textures.array_texture).unwrap();
    let settings = config_assets.get(config_handles.settings.clone()).unwrap();


    // Create a new array texture asset from the loaded texture.
    let array_layers = 4;
    image.reinterpret_stacked_2d_as_array(array_layers);

    // Spawn some cubes using the array texture
    // let mesh_handle = meshes.add(Cuboid::default());
    let mut sphere_mesh = Sphere::default().mesh().ico(25).unwrap();
    let sphere_pos = sphere_mesh.attribute(Mesh::ATTRIBUTE_POSITION).unwrap();
    let perlin = Perlin::new(1);
    let mut new_sphere_points = Vec::<[f32;3]>::new();
    for pos in sphere_pos.as_float3().unwrap() {
        let perlin_scale = 5.;
        let rd0 = 1.0 + 0.2 * perlin.get([perlin_scale * pos[0] as f64, perlin_scale * pos[1] as f64, perlin_scale * pos[2] as f64]) as f32;
        let rd1 = rd0 - 0.05 * perlin.get([perlin_scale * 3.0 * pos[0] as f64, perlin_scale * 3.0 * pos[1] as f64, perlin_scale * 3.0 * pos[2] as f64]) as f32;
        let rd = rd1 + 0.01 * perlin.get([perlin_scale * 10.0 * pos[0] as f64, perlin_scale * 10.0 * pos[1] as f64, perlin_scale * 10.0 * pos[2] as f64]) as f32;
        new_sphere_points.push([
            (pos[0] * rd), 
            (pos[1] * rd), 
            (pos[2] * rd)]);
    }
    sphere_mesh.insert_attribute(
        Mesh::ATTRIBUTE_POSITION,
        new_sphere_points,
    );

    let mesh_handle = meshes.add(sphere_mesh);
    let material_handle = materials.add(ArrayTextureMaterial {
        array_texture: textures.array_texture.clone(),
    });
    commands.spawn(MaterialMeshBundle {
        mesh: mesh_handle.clone(),
        material: material_handle.clone(),
        transform: Transform::from_xyz(0.0, 0.0, 0.0).with_scale(Vec3::splat(settings.planet_scale)),
        ..Default::default()
    });
}

#[derive(Asset, TypePath, AsBindGroup, Debug, Clone)]
struct ArrayTextureMaterial {
    #[texture(0, dimension = "2d_array")]
    #[sampler(1)]
    array_texture: Handle<Image>,
}

impl Material for ArrayTextureMaterial {
    fn fragment_shader() -> ShaderRef {
        "shaders/array_texture.wgsl".into()
    }
}
