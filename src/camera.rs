use crate::GameState;
use crate::loading::{SettingsConfigAsset,SettingsConfigAssets};
use crate::post_processing::PostProcessSettings;

use bevy::{
    core_pipeline::prepass::DepthPrepass,
    input::mouse::MouseMotion,
    prelude::*,
    window::CursorGrabMode,
};

pub struct CameraPlugin;

/// This plugin is responsible for the game camera
impl Plugin for CameraPlugin {
    fn build(&self, app: &mut App) {
        app.add_systems(OnEnter(GameState::Menu), setup_camera);
        app.add_systems(OnEnter(GameState::Playing), setup_sun);
        app.add_systems(Update, (
            grab_mouse.run_if(in_state(GameState::Playing)),
            move_camera.run_if(in_state(GameState::Playing)),
        ));
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

// This system grabs the mouse when the left mouse button is pressed
// and releases it when the escape key is pressed
fn grab_mouse(
    mut windows: Query<&mut Window>,
    mouse: Res<ButtonInput<MouseButton>>,
    key: Res<ButtonInput<KeyCode>>,
) {
    let mut window = windows.single_mut();

    if mouse.just_pressed(MouseButton::Left) {
        window.cursor.visible = false;
        window.cursor.grab_mode = CursorGrabMode::Locked;
    }

    if key.just_pressed(KeyCode::Escape) {
        window.cursor.visible = true;
        window.cursor.grab_mode = CursorGrabMode::None;
    }
}

// update camera transform
fn move_camera(
    time: Res<Time>,
    mut camera_query: Query<&mut Transform, With<GameCamera>>,
    config_handles: Res<SettingsConfigAssets>,
    config_assets: Res<Assets<SettingsConfigAsset>>,
    mut windows: Query<&Window>,
    mut mouse_motion_events: EventReader<MouseMotion>,
) {
    if let Some(config) = config_assets.get(config_handles.settings.clone()) {
        // check if paused
        let window = windows.single_mut();
        if window.cursor.grab_mode == CursorGrabMode::None {
            // move camera automatically
            let camera_offset = (f32::sin(time.elapsed_seconds() * 0.5) * 0.5 + 0.5) * 
                (config.max_distance - config.min_distance) + config.min_distance;
            for mut camera_transform in &mut camera_query {
                camera_transform.translation = Vec3::new(0., 0., camera_offset);
                camera_transform.look_at(config.look_at, Vec3::Y);
            }
            // clear mouse motion events
            for _event in mouse_motion_events.read() { }
        } else {
            let mut total_move = Vec2::splat(0.);
            for event in mouse_motion_events.read() {
                total_move += event.delta;
            }
            for mut camera_transform in &mut camera_query {
                camera_transform.rotation *= Quat::from_axis_angle(Vec3::Y, -total_move.x * config.mouse_speed);
                camera_transform.rotation *= Quat::from_axis_angle(Vec3::X, -total_move.y * config.mouse_speed);
            }
        }
    }
}
