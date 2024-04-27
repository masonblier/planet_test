use crate::GameState;
use crate::camera::GameCamera;
use crate::loading::{SettingsConfigAsset,SettingsConfigAssets};

use bevy::{
    asset::LoadState,
    prelude::*,
    reflect::TypePath,
    pbr::NotShadowCaster,
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
                MaterialPlugin::<WaterTextureMaterial> {
                    prepass_enabled: false,
                    ..default()
                },
            ))
            .add_systems(OnEnter(GameState::Playing), setup_demo)
            .add_systems(Update, (
                create_array_texture.run_if(in_state(GameState::Playing)),
                move_camera.run_if(in_state(GameState::Playing)),
            ));
    }
}

#[derive(Resource)]
struct LoadingTexture {
    is_loaded: bool,
    handle: Handle<Image>,
}

fn setup_demo(mut commands: Commands, asset_server: Res<AssetServer>) {
    // Start loading the texture.
    commands.insert_resource(LoadingTexture {
        is_loaded: false,
        handle: asset_server.load("textures/array_texture.png"),
    });

    // light
    commands.spawn(DirectionalLightBundle {
        transform: Transform::from_xyz(3.0, 2.0, 1.0).looking_at(Vec3::ZERO, Vec3::Y),
        ..Default::default()
    });
}

fn create_array_texture(
    mut commands: Commands,
    asset_server: Res<AssetServer>,
    mut loading_texture: ResMut<LoadingTexture>,
    mut images: ResMut<Assets<Image>>,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<ArrayTextureMaterial>>,
    mut water_materials: ResMut<Assets<WaterTextureMaterial>>,
    config_handles: Res<SettingsConfigAssets>,
    config_assets: Res<Assets<SettingsConfigAsset>>,
) {
    if loading_texture.is_loaded
        || asset_server.load_state(loading_texture.handle.clone()) != LoadState::Loaded
    {
        return;
    }
    loading_texture.is_loaded = true;
    
    let image = images.get_mut(&loading_texture.handle).unwrap();
    let settings = config_assets.get(config_handles.settings.clone()).unwrap();


    // Create a new array texture asset from the loaded texture.
    let array_layers = 4;
    image.reinterpret_stacked_2d_as_array(array_layers);

    // Spawn some cubes using the array texture
    // let mesh_handle = meshes.add(Cuboid::default());
    let mut sphere_mesh = Sphere::default().mesh().ico(15).unwrap();
    let sphere_pos = sphere_mesh.attribute(Mesh::ATTRIBUTE_POSITION).unwrap();
    let perlin = Perlin::new(1);
    let mut new_sphere_points = Vec::<[f32;3]>::new();
    for pos in sphere_pos.as_float3().unwrap() {
        let perlin_scale = 5.;
        let rd = (perlin.get([perlin_scale * pos[0] as f64, perlin_scale * pos[1] as f64, perlin_scale * pos[2] as f64]) * 0.2 + 1.) as f32;
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
        array_texture: loading_texture.handle.clone(),
    });
    commands.spawn(MaterialMeshBundle {
        mesh: mesh_handle.clone(),
        material: material_handle.clone(),
        transform: Transform::from_xyz(0.0, 0.0, 0.0).with_scale(Vec3::splat(settings.planet_scale)),
        ..Default::default()
    });

    let water_mesh_handle = meshes.add(Sphere::default().mesh().ico(10).unwrap());
    let water_material_handle = water_materials.add(WaterTextureMaterial { });
    commands.spawn((
        MaterialMeshBundle {
            mesh: water_mesh_handle.clone(),
            material: water_material_handle.clone(),
            transform: Transform::from_xyz(0.0, 0.0, 0.0).with_scale(Vec3::splat(settings.planet_scale)),
            ..Default::default()
        },
        NotShadowCaster,
    ));
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

#[derive(Asset, TypePath, AsBindGroup, Debug, Clone)]
struct WaterTextureMaterial {
}

impl Material for WaterTextureMaterial {
    fn fragment_shader() -> ShaderRef {
        "shaders/water_texture.wgsl".into()
    }

    fn alpha_mode(&self) -> AlphaMode {
        AlphaMode::Blend
    }
}


fn move_camera(
    time: Res<Time>,
    mut camera_query: Query<&mut Transform, With<GameCamera>>,
    config_handles: Res<SettingsConfigAssets>,
    config_assets: Res<Assets<SettingsConfigAsset>>,
) {
    if let Some(settings) = config_assets.get(config_handles.settings.clone()) {
        let camera_offset = (f32::sin(time.elapsed_seconds() * 0.5) * 0.5 + 0.5) * (settings.max_distance - settings.min_distance) + settings.min_distance;

        for mut camera_transform in &mut camera_query {
            camera_transform.translation = Vec3::new(0., 0., camera_offset);
            camera_transform.look_at(settings.look_at, Vec3::Y);
        }
    }    
}
