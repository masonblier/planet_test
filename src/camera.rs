use crate::GameState;
use crate::post_processing::PostProcessSettings;
use bevy::{
    core_pipeline::prepass::DepthPrepass,
    prelude::*
};

pub struct CameraPlugin;

/// This plugin is responsible for the game camera
impl Plugin for CameraPlugin {
    fn build(&self, app: &mut App) {
        app.add_systems(OnEnter(GameState::Menu), setup_camera);
        app.add_systems(OnEnter(GameState::Playing), setup_sun);
    }
}

#[derive(Component)]
pub struct GameCamera;

fn setup_camera(mut commands: Commands) {
    // camera
    commands.spawn((
        Camera3dBundle {
            transform: Transform::from_xyz(5.0, 5.0, 5.0).looking_at(Vec3::new(1.5, 0.0, 0.0), Vec3::Y),
            ..Default::default()
        },
        DepthPrepass,
        PostProcessSettings {
            ..default()
        },
        GameCamera { },
    ));    
}

#[derive(Component)]
pub struct GameSunLight;

fn setup_sun(mut commands: Commands) {
    // light
    commands.spawn((DirectionalLightBundle {
        transform: Transform::from_xyz(3.0, 2.0, 1.0).looking_at(Vec3::ZERO, Vec3::Y),
        ..Default::default()
    },
    GameSunLight { }));
}
