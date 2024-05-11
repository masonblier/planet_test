use crate::GameState;
use bevy::prelude::*;

pub struct OverlayUiPlugin;

/// This plugin is responsible for the ui shown during game play
impl Plugin for OverlayUiPlugin {
    fn build(&self, app: &mut App) {
        app.add_systems(OnEnter(GameState::Playing), setup_overlayui)
            .add_systems(OnExit(GameState::Playing), cleanup_overlayui);
    }
}

#[derive(Component)]
struct OverlayUi;

fn setup_overlayui(mut commands: Commands) {
    commands
        .spawn((
            NodeBundle {
                style: Style {
                    flex_direction: FlexDirection::Row,
                    align_items: AlignItems::Center,
                    justify_content: JustifyContent::SpaceAround,
                    bottom: Val::Px(5.),
                    width: Val::Percent(100.),
                    position_type: PositionType::Absolute,
                    ..default()
                },
                ..default()
            },
            OverlayUi,
        ))
        .with_children(|parent| {
            parent.spawn(TextBundle::from_section(
                "a - toggle atmosphere   s - toggle stars",
                TextStyle {
                    font_size: 15.0,
                    color: Color::rgb(0.9, 0.9, 0.9),
                    ..default()
                },
            ));
        });
}

fn cleanup_overlayui(mut commands: Commands, overlayui: Query<Entity, With<OverlayUi>>) {
    for entity in overlayui.iter() {
        commands.entity(entity).despawn_recursive();
    }
}
