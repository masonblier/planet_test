# planet_test

Procedural planet generation and renderer. Uses the [Bevy engine](https://bevyengine.org/) and [Rapier physics engine](https://rapier.rs). Based on the [Bevy Game Template](https://github.com/NiklasEi/bevy_game_template).

# Running from source

* Start the native app: `cargo run`
* Start the web build: `trunk serve`
    * requires [trunk]: `cargo install --locked trunk`
    * requires `wasm32-unknown-unknown` target: `rustup target add wasm32-unknown-unknown`
    * this will serve your app on `8080` and automatically rebuild + reload it after code changes

# License

This project is licensed under [CC0 1.0 Universal](LICENSE)
