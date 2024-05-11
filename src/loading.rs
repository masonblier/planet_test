use crate::GameState;
use bevy::{
    asset::{io::Reader, AssetLoader, AsyncReadExt, LoadContext},
    prelude::*,
    utils::BoxedFuture,
};
use bevy_asset_loader::prelude::*;
use serde::Deserialize;
use thiserror::Error;

pub struct LoadingPlugin;

/// This plugin loads all assets using [`AssetLoader`] from a third party bevy plugin
/// Alternatively you can write the logic to load assets yourself
/// If interested, take a look at <https://bevy-cheatbook.github.io/features/assets.html>
impl Plugin for LoadingPlugin {
    fn build(&self, app: &mut App) {
        app.init_asset::<SettingsConfigAsset>();
        app.init_asset_loader::<SettingsConfigAssetLoader>();
        app.add_loading_state(
            LoadingState::new(GameState::Loading)
                .continue_to_state(GameState::Menu)
                .load_collection::<SettingsConfigAssets>()
                .load_collection::<TextureAssets>(),
        );
    }
}

// the following asset collections will be loaded during the State `GameState::Loading`
// when done loading, they will be inserted as resources (see <https://github.com/NiklasEi/bevy_asset_loader>)

#[derive(AssetCollection, Resource)]
pub struct SettingsConfigAssets {
    #[asset(path = "config/settings.config")]
    pub settings: Handle<SettingsConfigAsset>,
}

#[derive(AssetCollection, Resource)]
pub struct TextureAssets {
    #[asset(path = "textures/bevy.png")]
    pub bevy: Handle<Image>,
    #[asset(path = "textures/array_texture.png")]
    pub array_texture: Handle<Image>,
}

// Config asset loader

#[derive(Asset, TypePath, Debug, Deserialize)]
pub struct SettingsConfigAsset {
    pub mouse_speed: f32,
    pub planet_scale: f32,
    pub look_at: Vec3,
    pub min_distance: f32,
    pub max_distance: f32,
    pub enable_atmosphere: bool,
    pub enable_stars: bool,
}

#[derive(Default)]
struct SettingsConfigAssetLoader;

/// Possible errors that can be produced by [`SettingsConfigAssetLoader`]
#[non_exhaustive]
#[derive(Debug, Error)]
enum SettingsConfigAssetLoaderError {
    /// An [IO](std::io) Error
    #[error("Could not load asset: {0}")]
    Io(#[from] std::io::Error),
    /// A [RON](ron) Error
    #[error("Could not parse RON: {0}")]
    RonSpannedError(#[from] ron::error::SpannedError),
}

impl AssetLoader for SettingsConfigAssetLoader {
    type Asset = SettingsConfigAsset;
    type Settings = ();
    type Error = SettingsConfigAssetLoaderError;
    fn load<'a>(
        &'a self,
        reader: &'a mut Reader,
        _settings: &'a (),
        _load_context: &'a mut LoadContext,
    ) -> BoxedFuture<'a, Result<Self::Asset, Self::Error>> {
        Box::pin(async move {
            let mut bytes = Vec::new();
            reader.read_to_end(&mut bytes).await?;
            let config_asset = ron::de::from_bytes::<SettingsConfigAsset>(&bytes)?;
            Ok(config_asset)
        })
    }

    fn extensions(&self) -> &[&str] {
        &["config"]
    }
}
