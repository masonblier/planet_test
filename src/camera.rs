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
            intensity: 0.02,
            ..default()
        },
        GameCamera { },
    ));    
}
